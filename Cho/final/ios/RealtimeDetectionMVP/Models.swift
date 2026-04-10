import CoreGraphics
import Foundation

struct Detection {
    let rect: CGRect
    let confidence: Float
    let classID: Int
    let className: String
}

struct TrackResult {
    let trackID: Int
    let detection: Detection
    let isPredictionOnly: Bool
}

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

struct TrackingTuning {
    var deadzoneWidthRatio: CGFloat = 0.22
    var consecutiveFramesToCommit: Int = 3
    var sendInterval: TimeInterval = 0.15
    var stepStrength: UInt8 = 24
    var lostTargetStopFrames: Int = 6
    var invertDirection: Bool = false
    var midiChannel: UInt8 = 1
    var commandCC: UInt8 = 20
    var strengthCC: UInt8 = 21
    var preferredMIDIDeviceName: String = "Leonardo"
}

struct ServoCommand {
    let direction: MotionDirection
    let strength: UInt8
}

struct FramePacket {
    let tensorData: [Float]
    let inputShape: [Int]
    let originalImageSize: CGSize
    let timestampSeconds: Double
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func clampedToUnit() -> CGRect {
        let x = Swift.min(Swift.max(origin.x, 0.0), 1.0)
        let y = Swift.min(Swift.max(origin.y, 0.0), 1.0)
        let maxWidth = 1.0 - x
        let maxHeight = 1.0 - y
        let width = Swift.min(Swift.max(size.width, 0.0), maxWidth)
        let height = Swift.min(Swift.max(size.height, 0.0), maxHeight)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
