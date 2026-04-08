import Combine
import Foundation

@MainActor
final class MotorControlViewModel: ObservableObject {
    private static let servoAngleRange = 0...180

    @Published private(set) var currentAngle: Int
    @Published private(set) var midiStatusText: String = "MIDI: 검색 중..."
    @Published private(set) var midiDestinationLines: [String] = ["감지된 MIDI 목적지 없음"]
    @Published private(set) var lastActionText: String = "대기 중"
    @Published private(set) var lastErrorText: String?

    let tuning: MotorControlTuning
    private var midiOutput: USBMIDIServoOutput?

    init(tuning: MotorControlTuning? = nil) {
        let resolvedTuning = tuning ?? MotorControlTuning()
        self.tuning = resolvedTuning
        self.currentAngle = resolvedTuning.startAngle
        setupMIDIOutput()
    }

    var canMoveLeft: Bool {
        currentAngle - tuning.stepDegrees >= Self.servoAngleRange.lowerBound
    }

    var canMoveRight: Bool {
        currentAngle + tuning.stepDegrees <= Self.servoAngleRange.upperBound
    }

    func refreshConnection() {
        guard let midiOutput else {
            setupMIDIOutput()
            return
        }

        _ = midiOutput.connect(preferredNameFragment: tuning.preferredMIDIDeviceName)
        midiStatusText = midiOutput.statusText(preferredNameFragment: tuning.preferredMIDIDeviceName)
        midiDestinationLines = midiOutput.destinationDebugLines()
    }

    func moveLeft() {
        move(.left)
    }

    func moveRight() {
        move(.right)
    }

    private func setupMIDIOutput() {
        do {
            let midiOutput = try USBMIDIServoOutput(tuning: tuning)
            self.midiOutput = midiOutput
            _ = midiOutput.connect(preferredNameFragment: tuning.preferredMIDIDeviceName)
            midiStatusText = midiOutput.statusText(preferredNameFragment: tuning.preferredMIDIDeviceName)
            midiDestinationLines = midiOutput.destinationDebugLines()
            lastErrorText = nil
        } catch {
            midiStatusText = "MIDI: 초기화 실패"
            midiDestinationLines = ["MIDI 초기화 실패"]
            lastErrorText = error.localizedDescription
        }
    }

    private func move(_ direction: MotionDirection) {
        guard let nextAngle = nextAngle(for: direction) else {
            lastActionText = direction == .left ? "최소 각도 도달" : "최대 각도 도달"
            lastErrorText = nil
            refreshConnection()
            return
        }

        if midiOutput == nil {
            setupMIDIOutput()
        }
        if midiOutput?.connectedDestinationName == nil {
            refreshConnection()
        }

        guard let midiOutput else {
            lastActionText = "MIDI 사용 불가"
            return
        }

        do {
            try midiOutput.sendManualStep(direction)
            currentAngle = nextAngle
            midiStatusText = midiOutput.statusText(preferredNameFragment: tuning.preferredMIDIDeviceName)
            midiDestinationLines = midiOutput.destinationDebugLines()
            lastActionText = "\(direction.displayName) -> \(currentAngle)°"
            lastErrorText = nil
        } catch {
            _ = midiOutput.connect(preferredNameFragment: tuning.preferredMIDIDeviceName)
            midiStatusText = midiOutput.statusText(preferredNameFragment: tuning.preferredMIDIDeviceName)
            midiDestinationLines = midiOutput.destinationDebugLines()
            lastActionText = "명령 전송 실패"
            lastErrorText = error.localizedDescription
        }
    }

    private func nextAngle(for direction: MotionDirection) -> Int? {
        switch direction {
        case .stop:
            return currentAngle
        case .left:
            guard canMoveLeft else {
                return nil
            }
            return max(Self.servoAngleRange.lowerBound, currentAngle - tuning.stepDegrees)
        case .right:
            guard canMoveRight else {
                return nil
            }
            return min(Self.servoAngleRange.upperBound, currentAngle + tuning.stepDegrees)
        }
    }
}
