#include <MIDIUSB.h>
#include <Servo.h>

namespace {
  constexpr int kServoPin = 9;
  constexpr int kStatusLedPin = LED_BUILTIN;

  constexpr int kStartAngle = 90;

  // 0-based MIDI 채널 (0 = 실제 MIDI 채널 1)
  constexpr uint8_t kMidiChannel = 0;
  constexpr uint8_t kCommandCC = 20;

  // 서보 펄스 폭 (MG996R 호환)
  constexpr int kServoMinPulseUs = 544;
  constexpr int kServoMaxPulseUs = 2400;

  // [수정 2] 기구물 충돌 방지를 위한 안전 각도 제한 (실기 테스트 후 수정 가능)
  constexpr int kMinSafeAngle = 10;
  constexpr int kMaxSafeAngle = 170;

  // LED 깜빡임 유지 시간 (ms)
  constexpr uint32_t kLedBlinkDurationMs = 50;
} 

Servo panServo;
int currentAngle = kStartAngle;

// 논블로킹 LED 제어를 위한 상태 변수
uint32_t ledTurnOnTime = 0;
bool isLedOn = false;

void setStatusLed(bool enabled) {
  digitalWrite(kStatusLedPin, enabled ? HIGH : LOW);
  isLedOn = enabled;
}

void writeServoAngle() {
  // 0~180이 아닌 기계적 안전 범위로 클램핑
  currentAngle = constrain(currentAngle, kMinSafeAngle, kMaxSafeAngle);
  panServo.write(currentAngle); 
}

void handleControlChange(uint8_t channel, uint8_t control, uint8_t value) {
  if (channel != kMidiChannel) {
    return;
  }

  if (control == kCommandCC) {
    // 64를 빼서 iOS가 보낸 실제 각도(-15 ~ +15)를 복원
    int delta = (int)value - 64; 
    
    // 현재 각도에 누적 및 구동
    currentAngle += delta;
    writeServoAngle();
    
    // 논블로킹 LED 제어 (delay 삭제)
    setStatusLed(true);
    ledTurnOnTime = millis();
  }
}

void pollMidi() {
  while (true) {
    midiEventPacket_t packet = MidiUSB.read();
    if (packet.header == 0) {
      break;
    }

    const uint8_t status = packet.byte1 & 0xF0;
    // + 1 제거 (0-based 인덱스 유지)
    const uint8_t channel = packet.byte1 & 0x0F; 

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
}

void loop() {
  pollMidi();

  // millis 오버플로우에도 안전한 경과시간 비교 방식
  if (isLedOn && (uint32_t)(millis() - ledTurnOnTime) >= kLedBlinkDurationMs) {
    setStatusLed(false);
  }
}

/*
 [하드웨어 경고] 
 MG996R 서보모터는 동작 시 엄청난 전류(최대 1~2A)를 소모합니다.
 절대 아두이노 Leonardo의 5V 핀에 연결하지 마세요. 보드가 타버릴 수 있습니다.
 반드시 외부 전원(배터리 5~6V)을 사용하고, 아두이노의 GND와 외부 전원의 GND를 묶어주세요(Common GND).
*/