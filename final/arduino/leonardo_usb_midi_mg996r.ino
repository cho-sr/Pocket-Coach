#include <MIDIUSB.h>
#include <Servo.h>

namespace {
constexpr int kServoPin = 9;
constexpr int kStatusLedPin = LED_BUILTIN;

constexpr int kStartAngle = 90;
constexpr int kMinAngle = 45;
constexpr int kMaxAngle = 135;

constexpr uint8_t kMidiChannel = 1;
constexpr uint8_t kCommandCC = 20;
constexpr uint8_t kStrengthCC = 21;

constexpr uint8_t kStopValue = 0;
constexpr uint8_t kLeftValue = 1;
constexpr uint8_t kRightValue = 2;

constexpr uint32_t kCommandTimeoutMs = 700;
constexpr int kMinStepDegrees = 1;
constexpr int kMaxStepDegrees = 5;
constexpr bool kInvertDirection = false;

constexpr int kServoMinPulseUs = 544;
constexpr int kServoMaxPulseUs = 2400;
}  // namespace

Servo panServo;

int currentAngle = kStartAngle;
uint8_t latestStrength = 24;
uint32_t lastValidCommandMs = 0;

void setStatusLed(bool enabled) {
  digitalWrite(kStatusLedPin, enabled ? HIGH : LOW);
}

void writeServoAngle() {
  currentAngle = constrain(currentAngle, kMinAngle, kMaxAngle);
  panServo.write(currentAngle);
}

int strengthToStepDegrees(uint8_t strength) {
  return map(strength, 0, 127, kMinStepDegrees, kMaxStepDegrees);
}

uint8_t effectiveDirectionValue(uint8_t directionValue) {
  if (!kInvertDirection) {
    return directionValue;
  }

  if (directionValue == kLeftValue) {
    return kRightValue;
  }
  if (directionValue == kRightValue) {
    return kLeftValue;
  }
  return directionValue;
}

void handleDirectionCommand(uint8_t directionValue) {
  lastValidCommandMs = millis();

  switch (effectiveDirectionValue(directionValue)) {
    case kLeftValue:
      currentAngle -= strengthToStepDegrees(latestStrength);
      writeServoAngle();
      setStatusLed(true);
      break;

    case kRightValue:
      currentAngle += strengthToStepDegrees(latestStrength);
      writeServoAngle();
      setStatusLed(true);
      break;

    case kStopValue:
    default:
      setStatusLed(false);
      break;
  }
}

void handleControlChange(uint8_t channel, uint8_t control, uint8_t value) {
  if (channel != kMidiChannel) {
    return;
  }

  if (control == kStrengthCC) {
    latestStrength = value;
    return;
  }

  if (control == kCommandCC) {
    handleDirectionCommand(value);
  }
}

void pollMidi() {
  while (true) {
    midiEventPacket_t packet = MidiUSB.read();
    if (packet.header == 0) {
      break;
    }

    const uint8_t status = packet.byte1 & 0xF0;
    const uint8_t channel = (packet.byte1 & 0x0F) + 1;

    if (status == 0xB0) {
      handleControlChange(channel, packet.byte2, packet.byte3);
    }
  }
}

void setup() {
  pinMode(kStatusLedPin, OUTPUT);
  setStatusLed(false);

  panServo.attach(kServoPin, kServoMinPulseUs, kServoMaxPulseUs);
  writeServoAngle();
  lastValidCommandMs = millis();
}

void loop() {
  pollMidi();

  if (millis() - lastValidCommandMs > kCommandTimeoutMs) {
    setStatusLed(false);
  }
}

/*
 Wiring for MG996R with external power:
 - servo signal -> Leonardo pin 9
 - servo GND -> external 5V-6V supply GND
 - Leonardo GND -> same external supply GND
 - servo V+ -> external regulated 5V-6V supply

 Do not power MG996R from Leonardo 5V.
 This sketch moves only one step per LEFT or RIGHT command and holds position otherwise.
 */
