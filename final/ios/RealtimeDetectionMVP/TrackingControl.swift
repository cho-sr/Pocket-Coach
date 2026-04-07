import CoreGraphics
import Foundation

final class TargetSelectionController {
    private(set) var selectedTrackID: Int?
    private(set) var lastConfirmedRect: CGRect?
    private(set) var lostFrames: Int = 0

    var hasSelection: Bool {
        selectedTrackID != nil
    }

    @discardableResult
    func select(at normalizedPoint: CGPoint, visibleTracks: [TrackResult]) -> TrackResult? {
        let candidates = visibleTracks.filter { track in
            !track.isPredictionOnly &&
            track.detection.className == "person" &&
            track.detection.rect.contains(normalizedPoint)
        }

        guard !candidates.isEmpty else {
            clearSelection()
            return nil
        }

        let selected = candidates.min { lhs, rhs in
            distanceSquared(from: lhs.detection.rect.center, to: normalizedPoint) <
            distanceSquared(from: rhs.detection.rect.center, to: normalizedPoint)
        }

        selectedTrackID = selected?.trackID
        lastConfirmedRect = selected?.detection.rect
        lostFrames = 0
        return selected
    }

    func resolveSelectedTrack(from tracks: [TrackResult]) -> TrackResult? {
        guard let selectedTrackID else {
            return nil
        }

        guard let track = tracks.first(where: { $0.trackID == selectedTrackID }) else {
            lostFrames += 1
            return nil
        }

        if track.isPredictionOnly {
            lostFrames += 1
            return track
        }

        lastConfirmedRect = track.detection.rect
        lostFrames = 0
        return track
    }

    func clearSelection() {
        selectedTrackID = nil
        lastConfirmedRect = nil
        lostFrames = 0
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx) + (dy * dy)
    }
}

final class DeadzoneCommandController {
    private let tuning: TrackingTuning
    private var committedDirection: MotionDirection = .stop
    private var candidateDirection: MotionDirection = .stop
    private var candidateFrameCount: Int = 0
    private var lastSendTime: TimeInterval = 0

    init(tuning: TrackingTuning = TrackingTuning()) {
        self.tuning = tuning
    }

    func deadzoneRange() -> ClosedRange<CGFloat> {
        let halfWidth = tuning.deadzoneWidthRatio / 2.0
        return (0.5 - halfWidth)...(0.5 + halfWidth)
    }

    func forceStop(now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> ServoCommand? {
        resetPendingDirection()

        guard committedDirection != .stop else {
            return nil
        }

        committedDirection = .stop
        lastSendTime = now
        return ServoCommand(direction: .stop, strength: 0)
    }

    func update(selectedTrack: TrackResult?, now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> ServoCommand? {
        guard let selectedTrack, !selectedTrack.isPredictionOnly else {
            resetPendingDirection()
            return nil
        }

        let desiredDirection = direction(forTargetCenterX: selectedTrack.detection.rect.center.x)

        if desiredDirection == .stop {
            return forceStop(now: now)
        }

        if desiredDirection != committedDirection {
            if candidateDirection == desiredDirection {
                candidateFrameCount += 1
            } else {
                candidateDirection = desiredDirection
                candidateFrameCount = 1
            }

            guard candidateFrameCount >= tuning.consecutiveFramesToCommit else {
                return nil
            }

            guard shouldSend(now: now) else {
                return nil
            }

            committedDirection = desiredDirection
            lastSendTime = now
            resetPendingDirection()
            return ServoCommand(direction: desiredDirection, strength: tuning.stepStrength)
        }

        resetPendingDirection()

        guard shouldSend(now: now) else {
            return nil
        }

        lastSendTime = now
        return ServoCommand(direction: committedDirection, strength: tuning.stepStrength)
    }

    private func direction(forTargetCenterX x: CGFloat) -> MotionDirection {
        let range = deadzoneRange()
        let visualDirection: MotionDirection

        if x < range.lowerBound {
            visualDirection = .left
        } else if x > range.upperBound {
            visualDirection = .right
        } else {
            visualDirection = .stop
        }

        guard tuning.invertDirection else {
            return visualDirection
        }

        switch visualDirection {
        case .left:
            return .right
        case .right:
            return .left
        case .stop:
            return .stop
        }
    }

    private func shouldSend(now: TimeInterval) -> Bool {
        now - lastSendTime >= tuning.sendInterval
    }

    private func resetPendingDirection() {
        candidateDirection = .stop
        candidateFrameCount = 0
    }
}
