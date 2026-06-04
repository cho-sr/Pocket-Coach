#include <Servo.h>

const int SERVO_PIN = 9;
const int MIN_ANGLE = 35;
const int MAX_ANGLE = 145;
const int CENTER_ANGLE = 90;
const unsigned long COMMAND_TIMEOUT_MS = 1200;

Servo trackingServo;
String inputBuffer = "";
int currentAngle = CENTER_ANGLE;
unsigned long lastCommandAt = 0;

void setup() {
  Serial.begin(9600);
  trackingServo.attach(SERVO_PIN, 500, 2500);
  selfTestServo();
  lastCommandAt = millis();
}

void loop() {
  while (Serial.available() > 0) {
    char ch = (char)Serial.read();
    if (ch == '\n' || ch == '\r') {
      if (inputBuffer.length() > 0) {
        handleCommand(inputBuffer);
        inputBuffer = "";
        lastCommandAt = millis();
      }
    } else {
      inputBuffer += ch;
      if (inputBuffer.length() > 24) {
        inputBuffer = "";
      }
    }
  }

  if (millis() - lastCommandAt > COMMAND_TIMEOUT_MS) {
    trackingServo.write(currentAngle);
  }
}

void selfTestServo() {
  trackingServo.write(CENTER_ANGLE);
  delay(500);
  trackingServo.write(MIN_ANGLE);
  delay(700);
  trackingServo.write(MAX_ANGLE);
  delay(700);
  trackingServo.write(CENTER_ANGLE);
  currentAngle = CENTER_ANGLE;
  delay(500);
}

void handleCommand(String command) {
  command.trim();
  if (command.startsWith("PAN:")) {
    int requestedAngle = command.substring(4).toInt();
    moveToAngle(requestedAngle);
  }
}

void moveToAngle(int requestedAngle) {
  currentAngle = constrain(requestedAngle, MIN_ANGLE, MAX_ANGLE);
  trackingServo.write(currentAngle);
}
