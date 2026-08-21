/*
 * RoboChess - limit switch probe
 * -----------------------------------------------------------------------
 * TEMPORARY diagnostic sketch. Upload it INSTEAD of robochess_gantry.ino,
 * find out what your switches actually do, then re-upload the real firmware.
 *
 * It watches every usable digital pin at once, so you do not need to know
 * or remember your wiring. Every pin is set to INPUT_PULLUP, which also
 * means the A4988 ENABLE line floats high = drivers disabled = the motors
 * will not move while you poke at things.
 *
 * WHAT TO DO
 *   1. Upload. Open Serial Monitor at 115200, line ending "Newline".
 *   2. Read the startup dump. With NOTHING pressed, every switch pin should
 *      read HIGH. Any pin already reading LOW is either wired
 *      normally-closed, wired to +5V/GND directly, or physically held down.
 *   3. Press and release each limit switch by hand. The pin it is wired to
 *      will announce itself.
 *   4. Slide the carriage onto each switch the way homing does, and watch
 *      how far you have to move it back before the pin returns to HIGH.
 *      That distance is your minimum safe back-off.
 *
 * READING THE RESULT
 *   Pin goes HIGH -> LOW when pressed  = normally-open to GND. Correct for
 *                                        INPUT_PULLUP. Code should treat
 *                                        LOW as "triggered".
 *   Pin goes LOW -> HIGH when pressed  = normally-closed. Your firmware's
 *                                        logic is inverted for this switch.
 *   Pin never changes                  = wrong pin, broken switch, or a
 *                                        broken/unseated wire.
 *   Pin flickers while you hold it     = contact bounce; needs debouncing.
 */

#include <Arduino.h>

// D0/D1 are the USB serial pins - leave them alone.
const uint8_t PINS[] = {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
                        A0, A1, A2, A3, A4, A5};
const uint8_t N_PINS = sizeof(PINS) / sizeof(PINS[0]);

uint8_t lastState[N_PINS];
unsigned long lastChangeMs[N_PINS];
uint16_t changeCount[N_PINS];

void printPinName(uint8_t i) {
  if (PINS[i] >= A0) {
    Serial.print(F("A"));
    Serial.print(PINS[i] - A0);
  } else {
    Serial.print(F("D"));
    Serial.print(PINS[i]);
  }
}

void dumpAll() {
  Serial.println(F("---- current state (LOW = pulled to ground) ----"));
  uint8_t lowCount = 0;
  for (uint8_t i = 0; i < N_PINS; i++) {
    uint8_t v = digitalRead(PINS[i]);
    Serial.print(F("  "));
    printPinName(i);
    Serial.print(F("  "));
    Serial.print(v ? F("HIGH") : F("LOW "));
    if (!v) {
      Serial.print(F("   <-- reading LOW right now"));
      lowCount++;
    }
    if (changeCount[i]) {
      Serial.print(F("   ("));
      Serial.print(changeCount[i]);
      Serial.print(F(" changes seen)"));
    }
    Serial.println();
  }
  Serial.print(F("  pins currently LOW: "));
  Serial.println(lowCount);
  Serial.println(F("-----------------------------------------------"));
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { ; }
  delay(200);

  for (uint8_t i = 0; i < N_PINS; i++) {
    pinMode(PINS[i], INPUT_PULLUP);
    changeCount[i] = 0;
    lastChangeMs[i] = 0;
  }
  delay(50);  // let the pull-ups settle
  for (uint8_t i = 0; i < N_PINS; i++) {
    lastState[i] = digitalRead(PINS[i]);
  }

  Serial.println();
  Serial.println(F("=== RoboChess limit switch probe ==="));
  Serial.println(F("All pins INPUT_PULLUP. Motors are disabled."));
  Serial.println(F("Press each limit switch by hand and watch below."));
  Serial.println(F("Send 'd' to re-dump state, 'r' to reset change counters."));
  Serial.println();
  dumpAll();
  Serial.println(F("With nothing pressed, every switch pin should read HIGH."));
  Serial.println(F("A switch pin already reading LOW is your bug."));
  Serial.println();
}

void loop() {
  unsigned long now = millis();

  for (uint8_t i = 0; i < N_PINS; i++) {
    uint8_t v = digitalRead(PINS[i]);
    if (v != lastState[i]) {
      lastState[i] = v;
      changeCount[i]++;
      unsigned long dt = now - lastChangeMs[i];
      lastChangeMs[i] = now;

      Serial.print(F("["));
      Serial.print(now);
      Serial.print(F(" ms] "));
      printPinName(i);
      Serial.print(v ? F("  HIGH  (released / open)")
                     : F("  LOW   (pressed / closed)"));
      if (dt < 25 && changeCount[i] > 1) {
        Serial.print(F("   <-- BOUNCE, only "));
        Serial.print(dt);
        Serial.print(F(" ms since last change"));
      }
      Serial.println();
    }
  }

  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == 'd' || ch == 'D') {
      dumpAll();
    } else if (ch == 'r' || ch == 'R') {
      for (uint8_t i = 0; i < N_PINS; i++) changeCount[i] = 0;
      Serial.println(F("change counters reset"));
    }
  }

  delay(2);
}
