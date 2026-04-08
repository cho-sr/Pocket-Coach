import CoreMIDI
import Foundation

enum MotionDirection: UInt8 {
    case stop = 0
    case left = 1
    case right = 2

    var displayName: String {
        switch self {
        case .stop:
            return "STOP"
        case .left:
            return "LEFT"
        case .right:
            return "RIGHT"
        }
    }
}

struct MotorControlTuning {
    let startAngle: Int = 90
    let stepDegrees: Int = 15
    let midiChannel: UInt8 = 1
    let commandCC: UInt8 = 20
    let preferredMIDIDeviceName: String = "Leonardo"
}

struct MIDIDestinationDescriptor {
    let endpoint: MIDIEndpointRef
    let name: String
    let searchText: String
    let isOffline: Bool
    let debugSummary: String
}

enum MIDIServoError: Error, LocalizedError {
    case clientCreationFailed(OSStatus)
    case outputPortCreationFailed(OSStatus)
    case noDestinationConnected
    case packetListCreationFailed
    case sendFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .clientCreationFailed(let status):
            return "MIDI 클라이언트 생성 실패 (\(status))"
        case .outputPortCreationFailed(let status):
            return "MIDI 출력 포트 생성 실패 (\(status))"
        case .noDestinationConnected:
            return "연결된 MIDI 목적지가 없습니다."
        case .packetListCreationFailed:
            return "MIDI 패킷 생성에 실패했습니다."
        case .sendFailed(let status):
            return "MIDI 전송 실패 (\(status))"
        }
    }
}
