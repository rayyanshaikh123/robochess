/*
 * RoboChess - stepper bring-up tester
 * -----------------------------------------------------------------------
 * TEMPORARY diagnostic sketch. Upload INSTEAD of robochess_gantry.ino.
 *
 * Purpose: prove that a driver + motor can move AT ALL, with none of the
 * homing, limit-switch or soft-limit logic in the way. If an axis steps
 * here but not in the real firmware, the hardware is fine and the bug is
 * in the firmware. If it will not step here either, it is hardware.
 *
 * Pins are set at RUNTIME - you do not have to recompile to try different
 * ones, and you do not need to remember your wiring.
 *
 * -------------------------------- USE --------------------------------
 * Serial Monitor, 115200 baud, line ending set to "Newline".
 *
 *   pins 2 5 8      STEP=D2, DIR=D5, ENABLE=D8   (use -1 for no enable pin)
 *   en on           energise the driver (A4988 ENABLE is ACTIVE LOW)
 *   fwd 200         step 200 steps forward
 *   rev 200         step 200 steps back
 *   speed 800       microseconds between step edges (bigger = slower)
 *   pulse 3         STEP high time in microseconds (A4988 needs >= 1)
 *   en off          release the motor
 *   info            show current settings
 *
 * A 1.8 deg motor is 200 full steps per revolution. At 1/16 microstepping
 * that is 3200 steps per revolution, so "fwd 3200" should be exactly one
 * turn of the shaft.
 *
 * ---------------------------- WHAT IT MEANS ----------------------------
 *   Turns smoothly              driver + motor + wiring are all good.
 *   Locked stiff, will not turn no STEP pulses reaching it, OR speed is
 *                               far too fast for the motor to follow.
 *                               Try "speed 3000" before blaming anything.
 *   Buzzes / vibrates in place  one coil is not connected. Check the pair
 *                               grouping in your motor cable.
 *   Free to turn by hand while
 *   enabled                     driver is delivering no current: Vref at
 *                               zero, ENABLE not actually low, or the
 *                               module is dead.
 *   Wrong direction             swap the DIR logic in the firmware, or
 *                               swap one coil pair.
 *
 * SAFETY: never plug or unplug a motor while the driver is powered.
 */

#include <Arduino.h>

int pinStep   = -1;
int pinDir    = -1;
int pinEnable = -1;

unsigned int stepIntervalUs = 800;   // between step edges
unsigned int pulseWidthUs   = 3;     // STEP high time
bool enabled = false;

long totalSteps = 0;   // net position in steps, for sanity checking

char buf[48];
uint8_t buflen = 0;

void showInfo() {
  Serial.println(F("---- settings ----"));
  Serial.print(F("  STEP pin    : ")); Serial.println(pinStep);
  Serial.print(F("  DIR pin     : ")); Serial.println(pinDir);
  Serial.print(F("  ENABLE pin  : "));
  if (pinEnable < 0) Serial.println(F("(none)")); else Serial.println(pinEnable);
  Serial.print(F("  driver      : ")); Serial.println(enabled ? F("ENABLED") : F("disabled"));
  Serial.print(F("  step interval: ")); Serial.print(stepIntervalUs); Serial.println(F(" us"));
  Serial.print(F("  pulse width : ")); Serial.print(pulseWidthUs); Serial.println(F(" us"));
  Serial.print(F("  net position: ")); Serial.print(totalSteps); Serial.println(F(" steps"));
  Serial.println(F("------------------"));
}

void applyEnable(bool on) {
  enabled = on;
  if (pinEnable >= 0) {
    // A4988 / DRV8825 ENABLE is active LOW.
    digitalWrite(pinEnable, on ? LOW : HIGH);
  }
  Serial.print(F("driver "));
  Serial.println(on ? F("ENABLED (motor should now feel locked)")
                    : F("disabled (motor should now turn freely)"));
  if (on && pinEnable < 0) {
    Serial.println(F("  note: no ENABLE pin set - relying on the driver's"));
    Serial.println(F("        own pulldown. If the motor is not locked,"));
    Serial.println(F("        set the real ENABLE pin with 'pins'."));
  }
}

void doSteps(long n, bool forward) {
  if (pinStep < 0) {
    Serial.println(F("ERR: no STEP pin set. Use: pins <step> <dir> <enable>"));
    return;
  }
  if (!enabled) {
    Serial.println(F("note: driver not enabled, doing it for you ('en on')"));
    applyEnable(true);
    delay(5);
  }
  if (pinDir >= 0) {
    digitalWrite(pinDir, forward ? HIGH : LOW);
    delayMicroseconds(10);   // DIR setup time before the first edge
  }

  Serial.print(F("stepping "));
  Serial.print(n);
  Serial.println(forward ? F(" forward...") : F(" reverse..."));

  unsigned long t0 = millis();
  for (long i = 0; i < n; i++) {
    digitalWrite(pinStep, HIGH);
    delayMicroseconds(pulseWidthUs);
    digitalWrite(pinStep, LOW);
    if (stepIntervalUs > pulseWidthUs) {
      delayMicroseconds(stepIntervalUs - pulseWidthUs);
    }
  }
  totalSteps += forward ? n : -n;

  Serial.print(F("done in "));
  Serial.print(millis() - t0);
  Serial.print(F(" ms, net position "));
  Serial.print(totalSteps);
  Serial.println(F(" steps"));
  Serial.println(F("If the shaft did NOT move, try a slower 'speed 3000'."));
}

void setPins(int s, int d, int e) {
  pinStep = s; pinDir = d; pinEnable = e;
  if (pinStep >= 0)   { pinMode(pinStep, OUTPUT);   digitalWrite(pinStep, LOW); }
  if (pinDir >= 0)    { pinMode(pinDir, OUTPUT);    digitalWrite(pinDir, LOW); }
  if (pinEnable >= 0) { pinMode(pinEnable, OUTPUT); digitalWrite(pinEnable, HIGH); }
  enabled = false;
  totalSteps = 0;
  Serial.println(F("pins set, driver left disabled"));
  showInfo();
}

void handleLine(char *line) {
  while (*line == ' ') line++;
  if (!*line) return;

  int a, b, c;
  if (strncmp(line, "pins", 4) == 0) {
    if (sscanf(line + 4, "%d %d %d", &a, &b, &c) == 3) setPins(a, b, c);
    else if (sscanf(line + 4, "%d %d", &a, &b) == 2)   setPins(a, b, -1);
    else Serial.println(F("usage: pins <step> <dir> [enable]   (-1 = none)"));

  } else if (strncmp(line, "en ", 3) == 0) {
    applyEnable(strncmp(line + 3, "on", 2) == 0);

  } else if (strncmp(line, "fwd", 3) == 0) {
    doSteps(sscanf(line + 3, "%d", &a) == 1 ? a : 200, true);

  } else if (strncmp(line, "rev", 3) == 0) {
    doSteps(sscanf(line + 3, "%d", &a) == 1 ? a : 200, false);

  } else if (strncmp(line, "speed", 5) == 0) {
    if (sscanf(line + 5, "%d", &a) == 1 && a > 0) {
      stepIntervalUs = a;
      Serial.print(F("step interval = ")); Serial.print(stepIntervalUs);
      Serial.println(F(" us"));
    } else Serial.println(F("usage: speed <microseconds>"));

  } else if (strncmp(line, "pulse", 5) == 0) {
    if (sscanf(line + 5, "%d", &a) == 1 && a > 0) {
      pulseWidthUs = a;
      Serial.print(F("pulse width = ")); Serial.print(pulseWidthUs);
      Serial.println(F(" us"));
    } else Serial.println(F("usage: pulse <microseconds>"));

  } else if (strncmp(line, "info", 4) == 0) {
    showInfo();

  } else {
    Serial.println(F("commands: pins S D E | en on|off | fwd N | rev N |"));
    Serial.println(F("          speed US | pulse US | info"));
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println(F("=== RoboChess stepper bring-up tester ==="));
  Serial.println(F("No homing, no limits, no soft limits - just raw pulses."));
  Serial.println();
  Serial.println(F("Start with:  pins <STEP> <DIR> <ENABLE>"));
  Serial.println(F("then:        fwd 400"));
  Serial.println();
  Serial.println(F("Test the KNOWN-GOOD X axis first to confirm your pin"));
  Serial.println(F("numbers are right, then try the same on Y."));
  Serial.println();
}

void loop() {
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      buf[buflen] = 0;
      handleLine(buf);
      buflen = 0;
    } else if (buflen < sizeof(buf) - 1) {
      buf[buflen++] = ch;
    }
  }
}
