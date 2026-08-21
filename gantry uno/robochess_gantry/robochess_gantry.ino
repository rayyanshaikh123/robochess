/*
 * RoboChess gantry firmware v2  -  Arduino Uno
 * =======================================================================
 * Written fresh 2026-08-19 after the v1 homing routine proved unfixable
 * blind. Nothing here depends on an external library: no AccelStepper, no
 * Servo. Upload and go.
 *
 * WHAT WAS WRONG BEFORE (and is fixed here)
 *   - homing backed off by a few STEPS instead of millimetres, so the
 *     carriage stopped with the switch still held closed. The next move
 *     then tripped the limit check, reported ERR LIMIT and silently
 *     cleared the homed flag. Back-off is now a real distance in mm
 *     (default 8.0) and EVERY retreat verifies the switch actually
 *     released, retrying in backoff-sized steps until it does.
 *   - homing had no timeout, so an axis that could not move looped
 *     forever. Every seek is now bounded; it reports ERR TIMEOUT_X / _Y.
 *   - "ERR LIMIT" meant two different things. Now:
 *         ERR RANGE      target outside the soft travel limits
 *         ERR LIMIT_X    a physical switch was hit mid-move
 *         ERR TIMEOUT_Y  an axis never reached its switch
 *     and a soft-limit rejection no longer un-homes you.
 *
 * EVERY SETTING IS RUNTIME-CONFIGURABLE AND STORED IN EEPROM.
 * Type CFG to list, SET <key> <value> to change. No reflashing to
 * change a pin, a speed, or a switch polarity.
 *
 * -----------------------------------------------------------------------
 * QUICK START
 *   1. Upload. Serial Monitor at 115200, line ending "Newline".
 *   2. Type  CFG  and check the pin block matches your wiring.
 *      Defaults come from your working WASD sketch:
 *          X STEP=2 DIR=5   Y STEP=3 DIR=6   ENABLE=8
 *      Set the three you have not told me yet, e.g.
 *          SET pin.limx 9
 *          SET pin.limy 10
 *          SET pin.mag 11
 *   3. Type  SWITCH  and press each limit switch by hand. It live-prints
 *      both switch states so you can confirm pins and polarity before
 *      anything moves.
 *   4. Type  TEST X 400  - raw pulses, no homing, no limits. Confirms
 *      motion the same way your WASD sketch did.
 *
 *   *** BEFORE STEP 5, IF YOUR LIMIT SWITCHES ARE SERIES-CHAINED ***
 *   (two NC switches per axis sharing one pin, min+max on the same wire):
 *   the firmware CANNOT electrically distinguish which of the two
 *   switches it hit. A wrong homeDirX/homeDirY or a wrong invDirX/invDirY
 *   makes HOME seek the FAR end, trigger that switch, and declare it
 *   "home" with zero indication anything is wrong - everything computed
 *   from that zero (soft limits, every square coordinate) is then wrong.
 *   Verify direction on real, un-faked movement first:
 *     JOG X 20          (small, well inside travel either way)
 *     -> carriage should move TOWARD the home corner if homeDirX is -1.
 *        If it moved away, either physically swap the motor's coil pair
 *        or  SET inv.dirx <0 or 1, whichever it currently is not>.
 *     JOG X -20          back to where it started - confirms it is not
 *                        stuck against a switch skewing your read.
 *     repeat for Y.
 *   Only run HOME once a JOG in the "toward home" direction visibly moves
 *   the carriage toward the corner you intend to be (0,0).
 *
 *   5. Type  HOME.
 *
 * COMMANDS
 *   PING                    -> OK PONG
 *   STATUS                  -> OK X=.. Y=.. HOMED=.. MAG=.. LIMX=.. LIMY=..
 *   HOME                    home both axes
 *   MOVEXY <x> <y>          absolute move, mm
 *   JOG <X|Y> <mm>          relative move, allowed before homing
 *   MAG <ON|OFF>            electromagnet: ON = carrying a piece
 *   STOP                    abort immediately
 *   TEST <X|Y> <steps>      raw step pulses, bypasses everything
 *   SWITCH                  live limit-switch readout (any key exits)
 *   CFG                     list all settings
 *   SET <key> <value>       change a setting and save it
 *   DEFAULTS                restore factory settings
 *
 * MOTION NOTES
 *   Two-axis Bresenham interpolation on Timer1, so a diagonal is a real
 *   straight line, not two independent ramps that dogleg. Trapezoidal
 *   accel is updated on Timer2 at 1 kHz.
 *
 * MAGNET
 *   An electromagnet on cfg.pinMag, switched through a MOSFET. There is no
 *   servo and no arm - that hardware was removed, so the servo code is
 *   deleted rather than disabled. The coil is energised ONLY while a piece
 *   is being carried: off at boot, off between moves, off after STOP, off
 *   on any fault, and force-released if it is ever on for over 30 s.
 *   If the magnet comes on when it should be off, SET mag.high 0.
 *
 *   TWO THINGS THE COIL NEEDS IN HARDWARE, not in code:
 *     - A FLYBACK DIODE across the coil (cathode to +V). An electromagnet
 *       is an inductor; switching it off collapses the field into a large
 *       reverse spike that will destroy the MOSFET. This is not optional.
 *     - A GATE PULLDOWN, ~100k from gate to GND. During reset and while the
 *       bootloader runs, D11 is high-impedance, and a floating gate can
 *       drift high enough to partially turn the FET on - which dissipates
 *       heat in both the FET and the coil with nothing driving it.
 *
 *   Default speed is 80 mm/s with 1000 mm/s^2 accel. At 40 steps/mm that
 *   is 3200 steps/s, which an Uno handles comfortably. If the motors
 *   stall or skip, lower max.speed first, then max.accel.
 */

#include <Arduino.h>
#include <EEPROM.h>
#include <avr/pgmspace.h>

#define FW_VERSION "2.0"
#define CFG_MAGIC  0x5243     // 'RC'
#define CFG_ADDR   0

// Timer1 runs at 16 MHz / 8 = 2 MHz, so one tick is 0.5 us.
#define TIMER1_HZ 2000000UL
#define MIN_STEP_RATE 40      // steps/s floor, keeps OCR1A inside 16 bits

// ======================================================================
// Configuration (mirrored in EEPROM)
// ======================================================================
struct Config {
  uint16_t magic;
  uint8_t  version;

  uint8_t  pinStepX, pinDirX;
  uint8_t  pinStepY, pinDirY;
  uint8_t  pinEnable;
  uint8_t  pinLimX, pinLimY;
  uint8_t  pinMag;                 // MOSFET gate driving the electromagnet

  uint8_t  invDirX, invDirY;       // 1 = flip that axis's direction
  uint8_t  limActiveLow;           // 1 = LOW reading means triggered, 0 = HIGH does.
                                   // Pull-up is ALWAYS on regardless (applyPinModes) -
                                   // this only changes how the reading is interpreted.
  uint8_t  enableActiveLow;        // A4988 ENABLE is active low = 1

  int8_t   homeDirX, homeDirY;     // -1 = home toward negative

  float    stepsPerMmX, stepsPerMmY;
  float    maxSpeed;               // mm/s
  float    maxAccel;               // mm/s^2
  float    homeSeek;               // mm/s, fast approach
  float    homeSlow;               // mm/s, precision re-approach
  float    backoffMm;              // how far to retreat off the switch
  float    maxX, maxY;             // soft travel limits, mm

  // Electromagnet, switched by a MOSFET. magActiveHigh = 1 means driving
  // the gate HIGH energises the coil - correct for the usual N-channel
  // low-side MOSFET. Set it to 0 if you used an inverting driver or a
  // high-side P-channel arrangement and the magnet comes on backwards.
  uint8_t  magActiveHigh;
  // Settle time after switching the coil, in ms. On: let the field build and
  // the piece pull into place before moving. Off: let residual magnetism
  // decay so the piece is actually released before the gantry drives away.
  uint16_t magDwellMs;

  uint8_t  checksum;
};

Config cfg;

void loadDefaults() {
  cfg.magic = CFG_MAGIC;
  cfg.version = 3;   // v3: servo replaced by MOSFET-switched electromagnet
  // From the user's verified-working WASD test sketch.
  cfg.pinStepX = 2;  cfg.pinDirX = 5;
  cfg.pinStepY = 3;  cfg.pinDirY = 6;
  cfg.pinEnable = 8;
  // Confirmed from the user's wiring table 2026-08-19.
  cfg.pinLimX = 9;   cfg.pinLimY = 10;
  cfg.pinMag = 11;      // was the servo signal pin; now the MOSFET gate

  // X needed a direction flip during bring-up; Y's fault was still open
  // when this was written, so Y is left un-flipped. VERIFY BOTH with JOG
  // before trusting HOME - see the wiring note below.
  cfg.invDirX = 1;   cfg.invDirY = 0;

  // Both limit switches per axis are NC and series-chained to one pin:
  //   GND -> switch -> switch -> pin
  // Idle (nothing pressed) reads LOW (closed path to GND through both
  // switches). Triggering EITHER switch opens that leg and the internal
  // pull-up pulls the pin HIGH. That is the opposite of a normally-open
  // switch to ground, so limActiveLow must be 0 here (triggered = HIGH),
  // not 1. Getting this backwards makes the firmware think it is
  // permanently on a limit switch it never actually reached - which
  // produces exactly the "homes, then immediately re-faults" symptom
  // this bring-up hit before this wiring was known.
  cfg.limActiveLow = 0;
  cfg.enableActiveLow = 1;
  cfg.homeDirX = -1; cfg.homeDirY = -1;

  // 1/8 microstep (MS1=H MS2=H MS3=L) x 200 step motor = 1600 steps/rev
  // GT2 20-tooth pulley = 40 mm/rev  ->  40 steps/mm
  cfg.stepsPerMmX = 40.0f;
  cfg.stepsPerMmY = 40.0f;

  cfg.maxSpeed  = 80.0f;
  cfg.maxAccel  = 1000.0f;
  // Both axes seek together, so homing time is the slower axis rather than
  // the sum of the two - most of the speed-up comes from that, not from a
  // high seek rate. This was briefly set to 70, which is where TIMEOUT_X
  // started appearing mid-game: a seek holds its top speed for the whole
  // travel, so an axis that is fine on short game moves can still stall on
  // a long seek and then never reach its switch. 45 keeps the margin.
  cfg.homeSeek  = 45.0f;
  cfg.homeSlow  = 8.0f;
  // 3.0 was not enough on the real machine: the Y lever stayed closed after
  // a 3 mm retreat and homing failed with NORELEASE_Y. Measured evidence
  // said it needs somewhere between 3 and 12 mm, so 8 gives real margin
  // while staying well inside the 5 cm frame gap at the home corner.
  cfg.backoffMm = 8.0f;

  // X must reach past the board to cover the captured-piece parking strip
  // (board 50..450, strip 450..560). Y only ever covers the board itself.
  cfg.maxX = 560.0f;
  cfg.maxY = 450.0f;

  cfg.magActiveHigh = 1;
  cfg.magDwellMs = 150;
}

uint8_t cfgChecksum() {
  const uint8_t *p = (const uint8_t *)&cfg;
  uint8_t sum = 0;
  for (size_t i = 0; i < sizeof(Config) - 1; i++) sum += p[i];
  return sum;
}

void saveConfig() {
  cfg.checksum = cfgChecksum();
  EEPROM.put(CFG_ADDR, cfg);
}

bool loadConfig() {
  Config tmp;
  EEPROM.get(CFG_ADDR, tmp);
  Config keep = cfg;
  cfg = tmp;
  uint8_t want = cfgChecksum();
  cfg = keep;
  // Version must match exactly. v2 EEPROM holds the old servo layout
  // (two uint16 pulse widths where v3 has a uint8 polarity flag), so
  // reading it through the v3 struct would silently produce garbage pins
  // and speeds. A mismatch falls through to factory defaults instead.
  if (tmp.magic == CFG_MAGIC && tmp.version == 3 && tmp.checksum == want) {
    cfg = tmp;
    return true;
  }
  return false;
}

// ======================================================================
// Motion engine
// ======================================================================
volatile long  posXsteps = 0, posYsteps = 0;
volatile long  remainSteps = 0;         // dominant-axis steps left
volatile long  totalSteps = 0;
volatile long  errX = 0, errY = 0;
volatile long  absDX = 0, absDY = 0;
volatile int8_t dirSignX = 1, dirSignY = 1;
volatile bool  moving = false;
volatile bool  homingMode = false;      // suppresses the limit auto-abort
volatile bool  limitTripped = false;
volatile char  limitAxis = 0;
volatile bool  stopRequested = false;
// Per-axis step suppression. Used by simultaneous homing: when one axis
// reaches its switch it stops pulsing while the other keeps going, instead
// of aborting the whole move. The interpolation tick count is unaffected,
// so the move still terminates normally.
volatile bool  freezeX = false, freezeY = false;

volatile uint32_t velQ8 = 0;            // current speed, steps/s in Q8.8
volatile uint32_t accelPerMsQ8 = 0;     // speed gain per ms, Q8.8
volatile uint32_t targetRate = 0;       // steps/s
volatile uint32_t accelSteps = 0;       // steps/s^2, for the decel test

bool homedX = false, homedY = false;
bool magnetDown = false;

// --- Limit switch reading, debounced -----------------------------------
//
// These pins are held only by the ATmega's internal pull-up (~30-50k), which
// is a very high impedance, and the switch leads run the length of the frame
// alongside the electromagnet's supply. Switching an inductive load couples
// into lines like that easily, so a single digitalRead() can catch a spike
// rather than the switch. A false "triggered" aborts a move or breaks
// homing; a false "clear" makes homing sail past the switch.
//
// Timer2 already runs at 1 kHz, so it samples the pins there and only
// accepts a new state after LIM_DEBOUNCE_TICKS consecutive agreeing reads.
// Everything else reads the debounced value, so nothing anywhere blocks.
// 3 ms costs 0.14 mm of travel at seek speed - irrelevant for homing.
#define LIM_DEBOUNCE_TICKS 3

volatile bool limStableX = false, limStableY = false;
volatile uint8_t limCntX = 0, limCntY = 0;

inline bool limRawRead(uint8_t pin) {
  int v = digitalRead(pin);
  return cfg.limActiveLow ? (v == LOW) : (v == HIGH);
}

// Called from the Timer2 ISR every millisecond.
inline void limSample() {
  bool rx = limRawRead(cfg.pinLimX);
  if (rx == limStableX) limCntX = 0;
  else if (++limCntX >= LIM_DEBOUNCE_TICKS) { limStableX = rx; limCntX = 0; }

  bool ry = limRawRead(cfg.pinLimY);
  if (ry == limStableY) limCntY = 0;
  else if (++limCntY >= LIM_DEBOUNCE_TICKS) { limStableY = ry; limCntY = 0; }
}

inline bool limitActive(uint8_t pin) {
  return (pin == cfg.pinLimY) ? limStableY : limStableX;
}

inline void driversEnable(bool on) {
  digitalWrite(cfg.pinEnable, cfg.enableActiveLow ? (on ? LOW : HIGH)
                                                  : (on ? HIGH : LOW));
}

void setupTimers() {
  noInterrupts();
  // Timer1: step pulse generator, CTC, prescaler 8 -> 2 MHz
  TCCR1A = 0;
  TCCR1B = (1 << WGM12) | (1 << CS11);
  OCR1A = 2000;
  TIMSK1 = 0;                 // enabled only while moving

  // Timer2: ramp updater, CTC, prescaler 128 -> 125 kHz, OCR 124 -> 1 kHz
  TCCR2A = (1 << WGM21);
  TCCR2B = (1 << CS22) | (1 << CS20);
  OCR2A = 124;
  TIMSK2 = (1 << OCIE2A);
  interrupts();
}

inline void applyRate(uint32_t rate) {
  if (rate < MIN_STEP_RATE) rate = MIN_STEP_RATE;
  uint32_t ticks = TIMER1_HZ / rate;
  if (ticks > 65535UL) ticks = 65535UL;
  if (ticks < 40UL) ticks = 40UL;          // hard ceiling ~50k steps/s
  OCR1A = (uint16_t)ticks;
  // Timer1 is free-running in CTC. If the counter has already passed the
  // new (smaller) compare value - which happens on every acceleration
  // update - the match is missed and the timer stalls for a full 32 ms
  // wrap. Nudge the counter so the match still lands.
  if (TCNT1 >= (uint16_t)ticks) TCNT1 = (uint16_t)ticks - 1;
}

// Timer1: emit one interpolated step.
ISR(TIMER1_COMPA_vect) {
  if (!moving) return;

  // Pulse high now; the Bresenham work below provides the pulse width,
  // which is comfortably over the A4988's 1 us minimum.
  bool doX = false, doY = false;

  errX -= absDX;
  if (errX < 0) { errX += totalSteps; doX = true; }
  errY -= absDY;
  if (errY < 0) { errY += totalSteps; doY = true; }

  // A frozen axis still consumes its interpolation slot but emits no pulse
  // and does not advance its position counter.
  if (freezeX) doX = false;
  if (freezeY) doY = false;

  if (doX) digitalWrite(cfg.pinStepX, HIGH);
  if (doY) digitalWrite(cfg.pinStepY, HIGH);

  if (doX) posXsteps += dirSignX;
  if (doY) posYsteps += dirSignY;

  remainSteps--;

  if (doX) digitalWrite(cfg.pinStepX, LOW);
  if (doY) digitalWrite(cfg.pinStepY, LOW);

  if (remainSteps <= 0) {
    moving = false;
    TIMSK1 &= ~(1 << OCIE1A);
  }
}

// Timer2 at 1 kHz: trapezoidal ramp + limit supervision.
ISR(TIMER2_COMPA_vect) {
  limSample();          // must run even when idle, so SWITCH/STATUS are live
  if (!moving) return;

  if (!homingMode) {
    if (limitActive(cfg.pinLimX)) {
      limitTripped = true; limitAxis = 'X';
      moving = false; TIMSK1 &= ~(1 << OCIE1A);
      return;
    }
    if (limitActive(cfg.pinLimY)) {
      limitTripped = true; limitAxis = 'Y';
      moving = false; TIMSK1 &= ~(1 << OCIE1A);
      return;
    }
  }

  uint32_t v = velQ8 >> 8;
  if (v < 1) v = 1;

  // Distance needed to stop from here, in steps: v^2 / (2a)
  uint32_t decelSteps = (accelSteps > 0) ? ((v * v) / (2UL * accelSteps)) : 0;

  if ((uint32_t)remainSteps <= decelSteps) {
    if (velQ8 > accelPerMsQ8 + (((uint32_t)MIN_STEP_RATE) << 8))
      velQ8 -= accelPerMsQ8;
    else
      velQ8 = ((uint32_t)MIN_STEP_RATE) << 8;
  } else if ((velQ8 >> 8) < targetRate) {
    velQ8 += accelPerMsQ8;
    if ((velQ8 >> 8) > targetRate) velQ8 = targetRate << 8;
  }

  applyRate(velQ8 >> 8);
}

void startMove(long dxSteps, long dySteps, float speedMmS) {
  freezeX = freezeY = false;          // every normal move drives both axes
  absDX = labs(dxSteps);
  absDY = labs(dySteps);
  totalSteps = max(absDX, absDY);
  if (totalSteps == 0) return;

  dirSignX = (dxSteps >= 0) ? 1 : -1;
  dirSignY = (dySteps >= 0) ? 1 : -1;

  bool dx = (dxSteps >= 0);
  bool dy = (dySteps >= 0);
  if (cfg.invDirX) dx = !dx;
  if (cfg.invDirY) dy = !dy;
  digitalWrite(cfg.pinDirX, dx ? HIGH : LOW);
  digitalWrite(cfg.pinDirY, dy ? HIGH : LOW);
  delayMicroseconds(20);              // A4988 DIR setup time

  errX = errY = totalSteps / 2;
  remainSteps = totalSteps;

  // Convert mm/s and mm/s^2 to steps/s along the dominant axis.
  float spmm = (absDX >= absDY) ? cfg.stepsPerMmX : cfg.stepsPerMmY;
  float rate = speedMmS * spmm;
  if (rate < MIN_STEP_RATE) rate = MIN_STEP_RATE;
  if (rate > 20000.0f) rate = 20000.0f;
  targetRate = (uint32_t)rate;

  float acc = cfg.maxAccel * spmm;
  if (acc < 50.0f) acc = 50.0f;
  accelSteps = (uint32_t)acc;
  accelPerMsQ8 = (uint32_t)((acc * 256.0f) / 1000.0f);
  if (accelPerMsQ8 < 1) accelPerMsQ8 = 1;

  // Start from a low but non-zero speed so we do not crawl out of rest.
  uint32_t startRate = targetRate / 8;
  if (startRate < MIN_STEP_RATE) startRate = MIN_STEP_RATE;
  if (startRate > targetRate) startRate = targetRate;
  velQ8 = startRate << 8;

  limitTripped = false;
  stopRequested = false;
  driversEnable(true);
  applyRate(startRate);

  noInterrupts();
  moving = true;
  TCNT1 = 0;
  TIMSK1 |= (1 << OCIE1A);
  interrupts();
}

void abortMotion() {
  noInterrupts();
  moving = false;
  TIMSK1 &= ~(1 << OCIE1A);
  interrupts();
  digitalWrite(cfg.pinStepX, LOW);
  digitalWrite(cfg.pinStepY, LOW);
}

// ======================================================================
// Electromagnet - MOSFET switched, no servo
// ======================================================================
// The arm and its SG90 are gone: the coil is bolted to the carriage and a
// MOSFET on cfg.pinMag switches it. So "engage" is now a single digital
// write instead of a pose, and all the servo pulse-timing machinery that
// used to live here is deleted rather than left dormant.
//
// Coil energised == carrying a piece, and nothing else. It is off at boot,
// off between moves, off after STOP, and off on any fault.

// Wall-clock guard so a dropped connection, a crashed host or a bug can
// never leave the coil energised indefinitely. A drag is a few seconds;
// 30 s means something has gone wrong, and coils cook when they are left on.
#define MAG_MAX_ON_MS 30000UL
unsigned long magOnSinceMs = 0;

inline void magWrite(bool on) {
  bool level = on ? (cfg.magActiveHigh != 0) : (cfg.magActiveHigh == 0);
  digitalWrite(cfg.pinMag, level ? HIGH : LOW);
}

void magnetSet(bool grab) {
  magWrite(grab);
  magnetDown = grab;
  magOnSinceMs = grab ? millis() : 0;
  // Dwell so the field has actually built (or decayed) before the gantry
  // moves. Releasing without this drags the piece along on residual
  // magnetism; grabbing without it starts moving before the piece is held.
  unsigned long t0 = millis();
  while (millis() - t0 < cfg.magDwellMs) { /* settle */ }
}

// Called from the main loop and from the in-move pump.
void magSafety() {
  if (!magnetDown || magOnSinceMs == 0) return;
  if (millis() - magOnSinceMs > MAG_MAX_ON_MS) {
    magWrite(false);
    magnetDown = false;
    magOnSinceMs = 0;
    Serial.println(F("WARN MAGOFF coil was on over 30s, released to protect it"));
  }
}

// ======================================================================
// Serial plumbing
// ======================================================================
char line[64];
uint8_t lineLen = 0;

void okPos() {
  Serial.print(F("OK X="));
  Serial.print(posXsteps / cfg.stepsPerMmX, 2);
  Serial.print(F(" Y="));
  Serial.print(posYsteps / cfg.stepsPerMmY, 2);
  Serial.print(F(" HOMED="));
  Serial.print((homedX && homedY) ? 1 : 0);
  Serial.print(F(" MAG="));
  Serial.print(magnetDown ? F("ON") : F("OFF"));
  Serial.print(F(" LIMX="));
  Serial.print(limitActive(cfg.pinLimX) ? 1 : 0);
  Serial.print(F(" LIMY="));
  Serial.println(limitActive(cfg.pinLimY) ? 1 : 0);
}

// Poll serial during a move so STOP still works. Returns true if aborted.
// Only a complete "STOP" line aborts - matching on a bare 'S' would make
// STATUS, SET and SWITCH act as emergency stops.
bool pumpDuringMove() {
  static char mbuf[8];
  static uint8_t mlen = 0;
  magSafety();
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      mbuf[mlen] = 0;
      for (uint8_t i = 0; i < mlen; i++) mbuf[i] = toupper(mbuf[i]);
      if (!strcmp(mbuf, "STOP")) stopRequested = true;
      mlen = 0;
    } else if (mlen < sizeof(mbuf) - 1) {
      mbuf[mlen++] = ch;
    } else {
      mlen = 0;              // too long to be STOP, discard
    }
  }
  if (stopRequested) {
    abortMotion();
    return true;
  }
  return false;
}

// Wait for the current move. 0 = finished, 1 = STOP, 2 = limit hit.
uint8_t waitMove() {
  while (moving) {
    if (pumpDuringMove()) return 1;
  }
  if (limitTripped) return 2;
  return 0;
}

// ======================================================================
// Homing
// ======================================================================
// Drive one axis until its switch triggers, or until maxTravel is used up.
// Returns 0 ok, 1 timeout/overtravel, 2 stopped.
uint8_t seekSwitch(char axis, int8_t dir, float speed, float maxTravel) {
  uint8_t limPin = (axis == 'X') ? cfg.pinLimX : cfg.pinLimY;
  float spmm     = (axis == 'X') ? cfg.stepsPerMmX : cfg.stepsPerMmY;
  long  steps    = (long)(maxTravel * spmm) * dir;

  homingMode = true;
  if (axis == 'X') startMove(steps, 0, speed);
  else             startMove(0, steps, speed);

  while (moving) {
    if (limitActive(limPin)) { abortMotion(); homingMode = false; return 0; }
    if (pumpDuringMove())    { homingMode = false; return 2; }
  }
  homingMode = false;
  return 1;   // ran the whole distance without ever seeing the switch
}

// Retreat until the switch releases. Returns true if it released.
bool releaseSwitch(char axis, int8_t dir, float maxTravel) {
  uint8_t limPin = (axis == 'X') ? cfg.pinLimX : cfg.pinLimY;
  float spmm     = (axis == 'X') ? cfg.stepsPerMmX : cfg.stepsPerMmY;
  long  steps    = (long)(maxTravel * spmm) * (-dir);

  homingMode = true;
  if (axis == 'X') startMove(steps, 0, cfg.homeSlow);
  else             startMove(0, steps, cfg.homeSlow);

  while (moving) {
    if (!limitActive(limPin)) { abortMotion(); homingMode = false; return true; }
    if (pumpDuringMove())     { homingMode = false; return false; }
  }
  homingMode = false;
  return !limitActive(limPin);
}

// ignoreLimits is for homing back-off moves, which deliberately start with
// the switch held. Everything else must still respect the switches.
uint8_t moveRelBlocking(char axis, float mm, float speed, bool ignoreLimits) {
  float spmm = (axis == 'X') ? cfg.stepsPerMmX : cfg.stepsPerMmY;
  long steps = (long)(mm * spmm);
  homingMode = ignoreLimits;
  if (axis == 'X') startMove(steps, 0, speed);
  else             startMove(0, steps, speed);
  uint8_t r = waitMove();
  homingMode = false;
  return r;
}

// Seek BOTH switches at once. Each axis freezes as it arrives; the move ends
// as soon as both have. Returns 0 ok, 1 an axis never arrived (see failAxis),
// 2 stopped by the operator.
// How far each axis actually stepped during the last seek. A frozen axis
// stops advancing its counter, so this is real commanded travel - which is
// what separates "motor never moved" from "moved but the switch never
// closed". Those two faults produce an identical TIMEOUT otherwise.
float lastSeekMmX = 0, lastSeekMmY = 0;

void reportSeekTravel() {
  Serial.print(F("HOME: seek moved x="));
  Serial.print(lastSeekMmX, 1);
  Serial.print(F("mm y="));
  Serial.print(lastSeekMmY, 1);
  Serial.println(F("mm"));
  Serial.println(F("HOME: near 0mm  -> that axis never moved: stalled at seek"));
  Serial.println(F("HOME:            speed, driver disabled, or wrong dir."));
  Serial.println(F("HOME: full range -> it moved but the switch never closed."));
}

uint8_t seekBoth(float speed, float travelX, float travelY, char *failAxis) {
  long sx = (long)(travelX * cfg.stepsPerMmX) * cfg.homeDirX;
  long sy = (long)(travelY * cfg.stepsPerMmY) * cfg.homeDirY;
  long fromXsteps = posXsteps, fromYsteps = posYsteps;

  bool gotX = limitActive(cfg.pinLimX);
  bool gotY = limitActive(cfg.pinLimY);

  homingMode = true;
  startMove(sx, sy, speed);
  freezeX = gotX;                     // already there? never pulse it
  freezeY = gotY;

  while (moving) {
    if (!gotX && limitActive(cfg.pinLimX)) { gotX = true; freezeX = true; }
    if (!gotY && limitActive(cfg.pinLimY)) { gotY = true; freezeY = true; }
    if (gotX && gotY) { abortMotion(); break; }
    if (pumpDuringMove()) { homingMode = false; freezeX = freezeY = false; return 2; }
  }
  homingMode = false;
  freezeX = freezeY = false;
  lastSeekMmX = (posXsteps - fromXsteps) / cfg.stepsPerMmX;
  lastSeekMmY = (posYsteps - fromYsteps) / cfg.stepsPerMmY;

  if (gotX && gotY) return 0;
  *failAxis = gotX ? 'Y' : 'X';       // report the one that never arrived
  return 1;
}

// Move both axes together. ignoreLimits is for back-off moves, which
// deliberately START with a switch held and would otherwise abort instantly.
// Anything that travels a real distance must pass false, or it will happily
// drive through a limit switch into the frame.
uint8_t moveBothBlocking(float mmX, float mmY, float speed, bool ignoreLimits) {
  homingMode = ignoreLimits;
  startMove((long)(mmX * cfg.stepsPerMmX), (long)(mmY * cfg.stepsPerMmY), speed);
  uint8_t r = waitMove();
  homingMode = false;
  return r;
}


// Homing used to fail with a bare "ERR TIMEOUT_Y" and nothing else, which
// says an axis never arrived but not why. These print the machine's actual
// view at each step, so one HOME transcript is enough to tell a wrong
// direction from a dead switch from a mechanical stall.
void homeStage(const __FlashStringHelper *what) {
  Serial.print(F("HOME: "));
  Serial.print(what);
  Serial.print(F("  x="));  Serial.print(posXsteps / cfg.stepsPerMmX, 1);
  Serial.print(F(" y="));   Serial.print(posYsteps / cfg.stepsPerMmY, 1);
  Serial.print(F(" limx=")); Serial.print(limitActive(cfg.pinLimX) ? 1 : 0);
  Serial.print(F(" limy=")); Serial.println(limitActive(cfg.pinLimY) ? 1 : 0);
}

// NOTE: the diagnostics print BEFORE the ERR line, never after. The host
// stops reading a reply at the first OK/ERR token, so anything printed
// after it would be left in the buffer and surface as garbage prepended to
// the NEXT command's response.
void homeFail(const __FlashStringHelper *code, char axis) {
  Serial.print(F("HOME: failed. limx="));
  Serial.print(limitActive(cfg.pinLimX) ? 1 : 0);
  Serial.print(F(" limy="));
  Serial.print(limitActive(cfg.pinLimY) ? 1 : 0);
  Serial.print(F(" home.dirx=")); Serial.print(cfg.homeDirX);
  Serial.print(F(" home.diry=")); Serial.print(cfg.homeDirY);
  Serial.print(F(" inv.dirx=")); Serial.print(cfg.invDirX);
  Serial.print(F(" inv.diry=")); Serial.print(cfg.invDirY);
  Serial.print(F(" lim.low=")); Serial.println(cfg.limActiveLow);
  Serial.println(F("HOME: if that axis never moved, check inv.dir/home.dir."));
  Serial.println(F("HOME: if it moved AWAY from home, flip its inv.dir."));
  if (!cfg.limActiveLow) {
    // NC switches chained to GND: the pin is held LOW by the closed chain
    // and the pull-up drags it HIGH when a switch opens. An open circuit -
    // unplugged lead, loose crimp, broken daisy-chain link - does exactly
    // the same thing, so it is INDISTINGUISHABLE from a pressed switch.
    // That is the intended fail-safe, but it means a stuck-triggered
    // reading points at the wiring, not at lim.low.
    Serial.println(F("HOME: lim reading 1 that never clears = OPEN CIRCUIT."));
    Serial.println(F("HOME: with NC switches a broken/unplugged wire reads"));
    Serial.println(F("HOME: exactly like a held switch (by design). Check the"));
    Serial.println(F("HOME: plug, both switches and the link between them."));
  } else {
    Serial.println(F("HOME: lim reads 1 with nothing pressed -> check lim.low."));
  }
  Serial.print(F("ERR ")); Serial.print(code); Serial.println(axis);
}

// Back away from whichever switches are still held, one backoff-sized step
// at a time, until both are clear. Only the held axis moves, so this never
// disturbs an axis that is already positioned.
//
// Every retreat in homing goes through here. Doing it in one place matters:
// the backoff stage used to retry while the final retreat did not, so a
// switch needing more than one backoff to release would clear the first
// stage and then fail the last one with NORELEASE - which is exactly what
// happened on this machine with a 3 mm backoff.
//
// Returns increments used (1 = ideal), or -1 if they never released.
int8_t retreatUntilClear(uint8_t maxSteps) {
  for (uint8_t i = 0; i < maxSteps; i++) {
    if (!limitActive(cfg.pinLimX) && !limitActive(cfg.pinLimY)) return i;
    moveBothBlocking(limitActive(cfg.pinLimX) ? -cfg.homeDirX * cfg.backoffMm : 0.0f,
                     limitActive(cfg.pinLimY) ? -cfg.homeDirY * cfg.backoffMm : 0.0f,
                     cfg.homeSlow, true);
    if (!limitActive(cfg.pinLimX) && !limitActive(cfg.pinLimY)) return i + 1;
  }
  return -1;
}

void doHome() {
  bool wasHomed = homedX && homedY;
  long fromX = posXsteps, fromY = posYsteps;
  homedX = homedY = false;
  driversEnable(true);
  char fail = '?';

  // If we already know roughly where we are (re-homing between chess moves,
  // which now happens every turn), close most of the distance at full speed
  // first. Homing speed only has to cover the last few mm plus whatever the
  // belts have slipped, instead of the whole 450 mm at seek speed.
  homeStage(F("start"));

  if (wasHomed) {
    float approach = cfg.backoffMm * 4.0f;
    float dx = -(fromX / cfg.stepsPerMmX) + approach * (cfg.homeDirX < 0 ? 1 : -1);
    float dy = -(fromY / cfg.stepsPerMmY) + approach * (cfg.homeDirY < 0 ? 1 : -1);
    // Limits MUST stay live for this one - it is a full-speed move over a
    // real distance. If slip is bad enough to reach a switch early it stops
    // there, and the seek below simply starts from "already on the switch".
    homeStage(F("prepos"));
    moveBothBlocking(dx, dy, cfg.maxSpeed, false);
    limitTripped = false;
  }

  // Get off the switches if we are sitting on either of them.
  if (limitActive(cfg.pinLimX) || limitActive(cfg.pinLimY)) {
    homeStage(F("release"));
    if (retreatUntilClear(6) < 0) {
      homeFail(F("STUCK_"), limitActive(cfg.pinLimX) ? 'X' : 'Y');
      return;
    }
  }

  // Fast seek, both axes together.
  homeStage(F("seek-fast"));
  uint8_t r = seekBoth(cfg.homeSeek, cfg.maxX + 30.0f, cfg.maxY + 30.0f, &fail);
  if (r == 2) { Serial.println(F("ERR STOPPED")); return; }
  if (r == 1) {
    // A motor that stalls at seek speed never reaches its switch, which is
    // indistinguishable from a broken switch at this level. Retry once at
    // half speed before giving up: if the slow attempt succeeds, the switch
    // was fine and the seek speed is simply too high for this axis.
    reportSeekTravel();
    Serial.println(F("HOME: timed out - retrying seek at half speed"));
    if (retreatUntilClear(6) < 0) {
      homeFail(F("STUCK_"), limitActive(cfg.pinLimX) ? 'X' : 'Y');
      return;
    }
    r = seekBoth(cfg.homeSeek * 0.5f, cfg.maxX + 30.0f, cfg.maxY + 30.0f, &fail);
    if (r == 0) {
      Serial.println(F("HOME: half-speed seek worked. home.seek is too high"));
      Serial.println(F("HOME: for this machine - lower it with SET home.seek."));
    }
  }
  if (r == 2) { Serial.println(F("ERR STOPPED")); return; }
  if (r == 1) { reportSeekTravel(); homeFail(F("TIMEOUT_"), fail); return; }

  // Back both off, far enough to release the levers.
  homeStage(F("backoff"));
  if (retreatUntilClear(6) < 0) {
    homeFail(F("NORELEASE_"), limitActive(cfg.pinLimX) ? 'X' : 'Y');
    return;
  }

  // Slow re-approach together, for a repeatable zero.
  homeStage(F("seek-slow"));
  r = seekBoth(cfg.homeSlow, cfg.backoffMm * 6.0f, cfg.backoffMm * 6.0f, &fail);
  if (r == 2) { Serial.println(F("ERR STOPPED")); return; }
  if (r == 1) { reportSeekTravel(); homeFail(F("TIMEOUT_"), fail); return; }

  // Final retreat. THIS position becomes zero, so the switches are released
  // whenever the machine sits at 0,0 - which is what v1 got wrong.
  homeStage(F("retreat"));
  // Both axes are on their switches here. Move both by exactly one backoff -
  // that fixed distance from the trigger point is what defines zero - then
  // clear anything still held.
  moveBothBlocking(-cfg.homeDirX * cfg.backoffMm,
                   -cfg.homeDirY * cfg.backoffMm, cfg.homeSlow, true);
  int8_t extra = retreatUntilClear(6);
  if (extra < 0) {
    homeFail(F("NORELEASE_"), limitActive(cfg.pinLimX) ? 'X' : 'Y');
    return;
  }
  if (extra > 0) {
    // Zero is now "backoff + however many extra steps it took", which can
    // differ between runs - so say so rather than silently homing to a
    // position that moves around.
    Serial.print(F("HOME: warning - needed "));
    Serial.print(extra);
    Serial.println(F(" extra backoff step(s) to clear the switches."));
    Serial.println(F("HOME: zero is less repeatable. Raise home.backoff."));
  }

  posXsteps = 0; posYsteps = 0;
  homedX = homedY = true;
  limitTripped = false;
  Serial.println(F("OK HOMED"));
}

// ======================================================================
// Settings table
// ======================================================================
enum VType { T_U8, T_I8, T_U16, T_F32 };

struct Setting {
  const char *name;
  uint8_t type;
  void *ptr;
};

const char s01[] PROGMEM = "pin.stepx";  const char s02[] PROGMEM = "pin.dirx";
const char s03[] PROGMEM = "pin.stepy";  const char s04[] PROGMEM = "pin.diry";
const char s05[] PROGMEM = "pin.en";     const char s06[] PROGMEM = "pin.limx";
const char s07[] PROGMEM = "pin.limy";   const char s08[] PROGMEM = "pin.mag";
const char s09[] PROGMEM = "inv.dirx";   const char s10[] PROGMEM = "inv.diry";
const char s11[] PROGMEM = "lim.low";    const char s12[] PROGMEM = "en.low";
const char s13[] PROGMEM = "home.dirx";  const char s14[] PROGMEM = "home.diry";
const char s15[] PROGMEM = "mm.stepsx";  const char s16[] PROGMEM = "mm.stepsy";
const char s17[] PROGMEM = "max.speed";  const char s18[] PROGMEM = "max.accel";
const char s19[] PROGMEM = "home.seek";  const char s20[] PROGMEM = "home.slow";
const char s21[] PROGMEM = "home.backoff"; const char s22[] PROGMEM = "max.x";
const char s23[] PROGMEM = "max.y";      const char s24[] PROGMEM = "mag.high";
const char s25[] PROGMEM = "mag.dwell";

const char *const SETNAMES[] PROGMEM = {
  s01, s02, s03, s04, s05, s06, s07, s08, s09, s10, s11, s12, s13,
  s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25
};

const uint8_t SETTYPES[] PROGMEM = {
  T_U8, T_U8, T_U8, T_U8, T_U8, T_U8, T_U8, T_U8,
  T_U8, T_U8, T_U8, T_U8, T_I8, T_I8,
  T_F32, T_F32, T_F32, T_F32, T_F32, T_F32, T_F32, T_F32, T_F32,
  T_U16, T_U16, T_U16
};

#define N_SETTINGS 25

void *settingPtr(uint8_t i) {
  switch (i) {
    case 0:  return &cfg.pinStepX;   case 1:  return &cfg.pinDirX;
    case 2:  return &cfg.pinStepY;   case 3:  return &cfg.pinDirY;
    case 4:  return &cfg.pinEnable;  case 5:  return &cfg.pinLimX;
    case 6:  return &cfg.pinLimY;    case 7:  return &cfg.pinMag;
    case 8:  return &cfg.invDirX;    case 9:  return &cfg.invDirY;
    case 10: return &cfg.limActiveLow; case 11: return &cfg.enableActiveLow;
    case 12: return &cfg.homeDirX;   case 13: return &cfg.homeDirY;
    case 14: return &cfg.stepsPerMmX; case 15: return &cfg.stepsPerMmY;
    case 16: return &cfg.maxSpeed;   case 17: return &cfg.maxAccel;
    case 18: return &cfg.homeSeek;   case 19: return &cfg.homeSlow;
    case 20: return &cfg.backoffMm;  case 21: return &cfg.maxX;
    case 22: return &cfg.maxY;       case 23: return &cfg.magActiveHigh;
    case 24: return &cfg.magDwellMs;
  }
  return NULL;
}

void printSetting(uint8_t i) {
  char nm[16];
  strcpy_P(nm, (char *)pgm_read_word(&SETNAMES[i]));
  uint8_t ty = pgm_read_byte(&SETTYPES[i]);
  void *p = settingPtr(i);
  Serial.print(F("  "));
  Serial.print(nm);
  Serial.print(F(" = "));
  switch (ty) {
    case T_U8:  Serial.println(*(uint8_t *)p); break;
    case T_I8:  Serial.println(*(int8_t *)p); break;
    case T_U16: Serial.println(*(uint16_t *)p); break;
    case T_F32: Serial.println(*(float *)p, 4); break;
  }
}

void doCfg() {
  Serial.println(F("OK CFG"));
  for (uint8_t i = 0; i < N_SETTINGS; i++) printSetting(i);
  Serial.print(F("  (firmware "));
  Serial.print(F(FW_VERSION));
  Serial.println(F(", SET <key> <value> to change, saved to EEPROM)"));
}

void applyPinModes() {
  pinMode(cfg.pinStepX, OUTPUT);  digitalWrite(cfg.pinStepX, LOW);
  pinMode(cfg.pinDirX, OUTPUT);
  pinMode(cfg.pinStepY, OUTPUT);  digitalWrite(cfg.pinStepY, LOW);
  pinMode(cfg.pinDirY, OUTPUT);
  pinMode(cfg.pinEnable, OUTPUT);
  // Drive the coil to its OFF level explicitly - with mag.high=0, LOW
  // would mean ON, so a bare digitalWrite(LOW) here would energise the
  // magnet at boot and leave it on until the first MAG command.
  pinMode(cfg.pinMag, OUTPUT);    magWrite(false);
  // Always keep the internal pull-up on, regardless of trigger polarity.
  // limActiveLow only controls how the READING is interpreted (see
  // limitActive() below) - it must never also gate whether the pin has a
  // defined idle state at all. Tying the two together here was the bug:
  // with limActiveLow=0 (this board's NC-series wiring) this used to fall
  // through to plain INPUT, leaving the pin fully floating - no pull-up,
  // no pull-down - the instant any switch in its chain opened. A floating
  // input reads stray noise/capacitance, not a clean level, which is
  // exactly the "only one switch seems to trigger" symptom: each pin's
  // floating read happened to settle differently, not that one switch
  // physically worked and the other did not.
  pinMode(cfg.pinLimX, INPUT_PULLUP);
  pinMode(cfg.pinLimY, INPUT_PULLUP);
  // Prime the debounced state. Without this it reads "clear" for the first
  // few ms after boot or after a SET changes a limit pin, and the boot-time
  // warning below would run before Timer2 had sampled enough to be right.
  delayMicroseconds(50);              // let the pull-ups settle
  limStableX = limRawRead(cfg.pinLimX);
  limStableY = limRawRead(cfg.pinLimY);
  limCntX = limCntY = 0;
  driversEnable(true);
}

// A zero steps-per-mm would divide by zero in every position report, and a
// zero speed would hang a move forever. Clamp anything nonsensical.
void sanitiseConfig() {
  if (!(cfg.stepsPerMmX > 0.01f)) cfg.stepsPerMmX = 40.0f;
  if (!(cfg.stepsPerMmY > 0.01f)) cfg.stepsPerMmY = 40.0f;
  if (!(cfg.maxSpeed  > 0.1f))    cfg.maxSpeed  = 80.0f;
  if (!(cfg.maxAccel  > 1.0f))    cfg.maxAccel  = 1000.0f;
  if (!(cfg.homeSeek  > 0.1f))    cfg.homeSeek  = 45.0f;
  if (!(cfg.homeSlow  > 0.1f))    cfg.homeSlow  = 8.0f;
  if (!(cfg.backoffMm > 0.1f))    // 3.0 was not enough on the real machine: the Y lever stayed closed after
  // a 3 mm retreat and homing failed with NORELEASE_Y. Measured evidence
  // said it needs somewhere between 3 and 12 mm, so 8 gives real margin
  // while staying well inside the 5 cm frame gap at the home corner.
  cfg.backoffMm = 8.0f;
  if (!(cfg.maxX > 1.0f))         cfg.maxX = 560.0f;
  if (!(cfg.maxY > 1.0f))         cfg.maxY = 450.0f;
  if (cfg.homeDirX != 1 && cfg.homeDirX != -1) cfg.homeDirX = -1;
  if (cfg.homeDirY != 1 && cfg.homeDirY != -1) cfg.homeDirY = -1;
  if (cfg.magActiveHigh > 1) cfg.magActiveHigh = 1;
  if (cfg.magDwellMs > 3000) cfg.magDwellMs = 150;
}

bool doSet(char *key, char *val) {
  for (uint8_t i = 0; i < N_SETTINGS; i++) {
    char nm[16];
    strcpy_P(nm, (char *)pgm_read_word(&SETNAMES[i]));
    if (strcasecmp(key, nm) != 0) continue;
    uint8_t ty = pgm_read_byte(&SETTYPES[i]);
    void *p = settingPtr(i);
    switch (ty) {
      case T_U8:  *(uint8_t *)p  = (uint8_t)atoi(val); break;
      case T_I8:  *(int8_t *)p   = (int8_t)atoi(val); break;
      case T_U16: *(uint16_t *)p = (uint16_t)atol(val); break;
      case T_F32: *(float *)p    = atof(val); break;
    }
    sanitiseConfig();
    saveConfig();
    applyPinModes();
    Serial.print(F("OK SET"));
    Serial.println();
    printSetting(i);
    return true;
  }
  return false;
}

// ======================================================================
// Command handling
// ======================================================================
void doMoveXY(float tx, float ty) {
  if (!homedX || !homedY) { Serial.println(F("ERR NOTHOMED")); return; }
  if (tx < -0.01f || ty < -0.01f || tx > cfg.maxX + 0.01f || ty > cfg.maxY + 0.01f) {
    Serial.print(F("ERR RANGE limits 0.."));
    Serial.print(cfg.maxX, 0); Serial.print(F(" / 0.."));
    Serial.println(cfg.maxY, 0);
    return;                                  // note: does NOT clear homing
  }
  long targetX = (long)(tx * cfg.stepsPerMmX);
  long targetY = (long)(ty * cfg.stepsPerMmY);
  startMove(targetX - posXsteps, targetY - posYsteps, cfg.maxSpeed);

  uint8_t r = waitMove();
  if (r == 1) { Serial.println(F("ERR STOPPED")); homedX = homedY = false; return; }
  if (r == 2) {
    Serial.print(F("ERR LIMIT_"));
    Serial.println((char)limitAxis);
    homedX = homedY = false;   // position is genuinely unknown now
    return;
  }
  okPos();
}

void doSwitchWatch() {
  Serial.println(F("OK WATCH - press the switches. Send any character to stop."));
  int lastX = -1, lastY = -1;
  while (!Serial.available()) {
    int x = limitActive(cfg.pinLimX) ? 1 : 0;
    int y = limitActive(cfg.pinLimY) ? 1 : 0;
    if (x != lastX || y != lastY) {
      Serial.print(F("  LIMX="));
      Serial.print(x ? F("TRIGGERED") : F("open     "));
      Serial.print(F("   LIMY="));
      Serial.println(y ? F("TRIGGERED") : F("open"));
      lastX = x; lastY = y;
    }
    delay(20);
  }
  while (Serial.available()) Serial.read();
  Serial.println(F("OK"));
}

void doTest(char axis, long steps) {
  uint8_t sp = (axis == 'X') ? cfg.pinStepX : cfg.pinStepY;
  uint8_t dp = (axis == 'X') ? cfg.pinDirX : cfg.pinDirY;
  driversEnable(true);
  digitalWrite(dp, steps >= 0 ? HIGH : LOW);
  delayMicroseconds(20);
  long n = labs(steps);
  for (long i = 0; i < n; i++) {
    digitalWrite(sp, HIGH);
    delayMicroseconds(3);
    digitalWrite(sp, LOW);
    delayMicroseconds(400);
  }
  Serial.print(F("OK TEST "));
  Serial.print(axis);
  Serial.print(F(" "));
  Serial.println(steps);
}

void handleLine(char *s) {
  while (*s == ' ') s++;
  if (!*s) return;

  char *verb = strtok(s, " \t");
  if (!verb) return;
  for (char *p = verb; *p; p++) *p = toupper(*p);

  if (!strcmp(verb, "PING")) {
    Serial.println(F("OK PONG " FW_VERSION));

  } else if (!strcmp(verb, "STATUS")) {
    okPos();

  } else if (!strcmp(verb, "HOME")) {
    doHome();

  } else if (!strcmp(verb, "MOVEXY")) {
    char *a = strtok(NULL, " \t");
    char *b = strtok(NULL, " \t");
    if (!a || !b) { Serial.println(F("ERR SYNTAX MOVEXY <x> <y>")); return; }
    doMoveXY(atof(a), atof(b));

  } else if (!strcmp(verb, "JOG")) {
    char *a = strtok(NULL, " \t");
    char *b = strtok(NULL, " \t");
    if (!a || !b) { Serial.println(F("ERR SYNTAX JOG <X|Y> <mm>")); return; }
    char ax = toupper(a[0]);
    if (ax != 'X' && ax != 'Y') { Serial.println(F("ERR SYNTAX axis")); return; }
    uint8_t r = moveRelBlocking(ax, atof(b), cfg.maxSpeed, false);
    if (r == 1) { Serial.println(F("ERR STOPPED")); return; }
    if (r == 2) {
      Serial.print(F("ERR LIMIT_"));
      Serial.print((char)limitAxis);
      Serial.println(F(" (if the switch was already held, use TEST instead)"));
      return;
    }
    okPos();

  } else if (!strcmp(verb, "MAG")) {
    char *a = strtok(NULL, " \t");
    if (!a) { Serial.println(F("ERR SYNTAX MAG <ON|OFF>")); return; }
    magnetSet(toupper(a[0]) == 'O' && toupper(a[1]) == 'N');
    Serial.print(F("OK MAG "));
    Serial.println(magnetDown ? F("ON") : F("OFF"));

  } else if (!strcmp(verb, "STOP")) {
    abortMotion();
    stopRequested = true;
    // Release the coil on an emergency stop. The piece is simply left on
    // whatever square the carriage stopped over, which is recoverable;
    // leaving an energised coil sitting on a halted machine is not.
    magWrite(false);
    magnetDown = false;
    magOnSinceMs = 0;
    Serial.println(F("OK STOPPED"));

  } else if (!strcmp(verb, "TEST")) {
    char *a = strtok(NULL, " \t");
    char *b = strtok(NULL, " \t");
    if (!a || !b) { Serial.println(F("ERR SYNTAX TEST <X|Y> <steps>")); return; }
    doTest(toupper(a[0]), atol(b));

  } else if (!strcmp(verb, "SWITCH")) {
    doSwitchWatch();

  } else if (!strcmp(verb, "CFG")) {
    doCfg();

  } else if (!strcmp(verb, "SET")) {
    char *k = strtok(NULL, " \t");
    char *v = strtok(NULL, " \t");
    if (!k || !v) { Serial.println(F("ERR SYNTAX SET <key> <value>")); return; }
    if (!doSet(k, v)) Serial.println(F("ERR NOKEY - type CFG for the list"));

  } else if (!strcmp(verb, "DEFAULTS")) {
    loadDefaults();
    saveConfig();
    applyPinModes();
    Serial.println(F("OK DEFAULTS restored"));

  } else {
    Serial.println(F("ERR UNKNOWN - PING STATUS HOME MOVEXY JOG MAG STOP "
                     "TEST SWITCH CFG SET DEFAULTS"));
  }
}

// ======================================================================
void setup() {
  Serial.begin(115200);
  delay(100);

  if (!loadConfig()) {
    loadDefaults();
    saveConfig();
  }
  sanitiseConfig();
  applyPinModes();
  setupTimers();

  Serial.println();
  Serial.print(F("READY RoboChess gantry "));
  Serial.println(F(FW_VERSION));
  Serial.println(F("Type CFG to check pins, SWITCH to test limits, HOME to home."));

  // Flag a limit that is already reading triggered at power-up. Usually the
  // carriage is simply parked on a switch, which is harmless - but with NC
  // series wiring it is also exactly what a disconnected or broken limit
  // lead looks like, and that fault otherwise stays invisible until HOME
  // fails with STUCK several steps later.
  if (limitActive(cfg.pinLimX) || limitActive(cfg.pinLimY)) {
    Serial.print(F("WARN limit reads TRIGGERED at boot:"));
    if (limitActive(cfg.pinLimX)) Serial.print(F(" X"));
    if (limitActive(cfg.pinLimY)) Serial.print(F(" Y"));
    Serial.println();
    if (!cfg.limActiveLow) {
      Serial.println(F("WARN if the carriage is NOT on that switch, the wire"));
      Serial.println(F("WARN is open - NC switches read the same either way."));
    }
  }
}

void loop() {
  magSafety();

  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      line[lineLen] = 0;
      handleLine(line);
      lineLen = 0;
    } else if (lineLen < sizeof(line) - 1) {
      line[lineLen++] = ch;
    }
  }
}
