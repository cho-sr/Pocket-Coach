#include <SoftwareSerial.h>
#include <Servo.h>

// Set RX, TX pins (connect HC-06 TX to pin 2, RX to pin 3)
SoftwareSerial BTSerial(2, 3); 
Servo myServo;

int currentAngle = 90; // Initial center position

void setup() {
  Serial.begin(9600);     // For PC serial monitor (debugging)
  BTSerial.begin(9600);   // Default baud rate of HC-06
  
  myServo.attach(9);      // Servo motor on pin 9
  myServo.write(currentAngle);
  
  Serial.println("System Ready. Waiting for BT connection...");
}

void loop() {
  // If data is received via Bluetooth
  if (BTSerial.available()) {
    char cmd = BTSerial.read();
    Serial.print("Received Command: "); 
    Serial.println(cmd);

    // Control motor based on command
    if (cmd == 'L') {
      currentAngle += 10;
      if (currentAngle > 180) currentAngle = 180; // Limit to servo max angle
      myServo.write(currentAngle);
    } 
    else if (cmd == 'R') {
      currentAngle -= 10;
      if (currentAngle < 0) currentAngle = 0;     // Limit to servo min angle
      myServo.write(currentAngle);
    }
    else if (cmd == 'C') {
      currentAngle = 90;
      myServo.write(currentAngle);
    }
  }
}
