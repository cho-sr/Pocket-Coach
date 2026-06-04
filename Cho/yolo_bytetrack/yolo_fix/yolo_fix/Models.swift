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

struct LetterboxInfo {
    let inputSize: CGSize
    let originalSize: CGSize
    let scaledSize: CGSize
    let scale: CGFloat
    let padX: CGFloat
    let padY: CGFloat

    func normalizedOriginalRect(fromModelPixelRect modelRect: CGRect) -> CGRect {
        guard scale > 0, originalSize.width > 0, originalSize.height > 0 else {
            return .zero
        }

        let originalX1 = ((modelRect.minX - padX) / scale).clamped(to: 0.0...originalSize.width)
        let originalY1 = ((modelRect.minY - padY) / scale).clamped(to: 0.0...originalSize.height)
        let originalX2 = ((modelRect.maxX - padX) / scale).clamped(to: 0.0...originalSize.width)
        let originalY2 = ((modelRect.maxY - padY) / scale).clamped(to: 0.0...originalSize.height)

        let normalizedX1 = (originalX1 / originalSize.width).clamped(to: 0.0...1.0)
        let normalizedY1 = (originalY1 / originalSize.height).clamped(to: 0.0...1.0)
        let normalizedX2 = (originalX2 / originalSize.width).clamped(to: 0.0...1.0)
        let normalizedY2 = (originalY2 / originalSize.height).clamped(to: 0.0...1.0)

        return CGRect(
            x: Swift.min(normalizedX1, normalizedX2),
            y: Swift.min(normalizedY1, normalizedY2),
            width: abs(normalizedX2 - normalizedX1),
            height: abs(normalizedY2 - normalizedY1)
        ).clampedToUnit()
    }
}

struct FramePacket {
    let tensorData: [Float]
    let inputShape: [Int]
    let originalImageSize: CGSize
    let timestampSeconds: Double
    let letterbox: LetterboxInfo
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
