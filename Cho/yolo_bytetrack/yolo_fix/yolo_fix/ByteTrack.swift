import CoreGraphics
import Foundation

struct ByteTrackConfiguration {
    var trackActivationThreshold: Float = 0.40
    var lowConfidenceThreshold: Float = 0.10
    var newTrackThreshold: Float = 0.45
    var firstAssociationIoUThreshold: CGFloat = 0.30
    var secondAssociationIoUThreshold: CGFloat = 0.20
    var maxLostFrames: Int = 30
    var predictionOnlyFrames: Int = 3
    var minimumBoxArea: CGFloat = 0.0001

    static let sportsTracking = ByteTrackConfiguration()
}

final class ByteTrack {
    private enum TrackState {
        case tracked
        case lost
        case removed
    }

    private final class Track {
        let id: Int
        private(set) var detection: Detection
        private(set) var predictedRect: CGRect
        private(set) var state: TrackState = .tracked
        private(set) var lastDetectionFrameIndex: Int

        private var lastDetectionTimestampSeconds: Double
        private var lastPredictionTimestampSeconds: Double
        private var velocity = CGRect.zero

        init(id: Int, detection: Detection, frameIndex: Int, timestampSeconds: Double) {
            self.id = id
            self.detection = detection
            self.predictedRect = detection.rect
            self.lastDetectionFrameIndex = frameIndex
            self.lastDetectionTimestampSeconds = timestampSeconds
            self.lastPredictionTimestampSeconds = timestampSeconds
        }

        func predict(to timestampSeconds: Double) {
            guard timestampSeconds.isFinite, lastPredictionTimestampSeconds.isFinite else { return }

            let dt = min(max(timestampSeconds - lastPredictionTimestampSeconds, 0.0), 1.0)
            guard dt > 0 else { return }
            let deltaTime = CGFloat(dt)

            predictedRect = CGRect(
                x: predictedRect.origin.x + (velocity.origin.x * deltaTime),
                y: predictedRect.origin.y + (velocity.origin.y * deltaTime),
                width: predictedRect.width + (velocity.width * deltaTime),
                height: predictedRect.height + (velocity.height * deltaTime)
            ).clampedToUnit()
            lastPredictionTimestampSeconds = timestampSeconds
        }

        func update(with detection: Detection, frameIndex: Int, timestampSeconds: Double) {
            let previousRect = self.detection.rect
            let dt = timestampSeconds.isFinite && lastDetectionTimestampSeconds.isFinite
                ? min(max(timestampSeconds - lastDetectionTimestampSeconds, 0.001), 1.0)
                : 1.0
            let deltaTime = CGFloat(dt)

            let measuredVelocity = CGRect(
                x: (detection.rect.origin.x - previousRect.origin.x) / deltaTime,
                y: (detection.rect.origin.y - previousRect.origin.y) / deltaTime,
                width: (detection.rect.width - previousRect.width) / deltaTime,
                height: (detection.rect.height - previousRect.height) / deltaTime
            )
            velocity = velocity.blended(with: measuredVelocity, newValueWeight: 0.35)
            self.detection = detection
            predictedRect = detection.rect
            state = .tracked
            lastDetectionFrameIndex = frameIndex
            lastDetectionTimestampSeconds = timestampSeconds
            lastPredictionTimestampSeconds = timestampSeconds
        }

        func markLost() {
            state = .lost
        }

        func markRemoved() {
            state = .removed
        }

        func trackResult(currentFrameIndex: Int) -> TrackResult {
            let predictionOnly = lastDetectionFrameIndex < currentFrameIndex
            let outputDetection = Detection(
                rect: predictionOnly ? predictedRect : detection.rect,
                confidence: detection.confidence,
                classID: detection.classID,
                className: detection.className
            )
            return TrackResult(
                trackID: id,
                detection: outputDetection,
                isPredictionOnly: predictionOnly
            )
        }
    }

    private struct AssociationResult {
        let matches: [(track: Track, detection: Detection)]
        let unmatchedTracks: [Track]
        let unmatchedDetections: [Detection]
    }

    private let configuration: ByteTrackConfiguration
    private var tracks: [Track] = []
    private var nextTrackID = 1
    private var frameIndex = 0

    init(configuration: ByteTrackConfiguration = .sportsTracking) {
        self.configuration = configuration
    }

    func reset() {
        tracks.removeAll()
        nextTrackID = 1
        frameIndex = 0
    }

    func update(detections: [Detection], timestampSeconds: Double) -> [TrackResult] {
        frameIndex += 1
        let timestamp = timestampSeconds.isFinite ? timestampSeconds : CFAbsoluteTimeGetCurrent()

        let candidates = detections.filter { detection in
            detection.confidence >= configuration.lowConfidenceThreshold &&
                detection.rect.width * detection.rect.height >= configuration.minimumBoxArea
        }
        let highConfidenceDetections = candidates.filter {
            $0.confidence >= configuration.trackActivationThreshold
        }
        let lowConfidenceDetections = candidates.filter {
            $0.confidence < configuration.trackActivationThreshold
        }

        tracks
            .filter { $0.state != .removed }
            .forEach { $0.predict(to: timestamp) }

        let firstPool = tracks.filter { $0.state == .tracked || $0.state == .lost }
        let firstAssociation = associate(
            tracks: firstPool,
            detections: highConfidenceDetections,
            minimumIoU: configuration.firstAssociationIoUThreshold
        )

        for match in firstAssociation.matches {
            match.track.update(
                with: match.detection,
                frameIndex: frameIndex,
                timestampSeconds: timestamp
            )
        }

        let secondAssociationTracks = firstAssociation.unmatchedTracks.filter { $0.state == .tracked }
        let secondAssociation = associate(
            tracks: secondAssociationTracks,
            detections: lowConfidenceDetections,
            minimumIoU: configuration.secondAssociationIoUThreshold
        )

        for match in secondAssociation.matches {
            match.track.update(
                with: match.detection,
                frameIndex: frameIndex,
                timestampSeconds: timestamp
            )
        }

        for track in secondAssociation.unmatchedTracks {
            track.markLost()
        }

        for detection in firstAssociation.unmatchedDetections
            where detection.confidence >= configuration.newTrackThreshold {
            tracks.append(
                Track(
                    id: nextTrackID,
                    detection: detection,
                    frameIndex: frameIndex,
                    timestampSeconds: timestamp
                )
            )
            nextTrackID += 1
        }

        for track in tracks where track.state == .lost {
            let lostFrames = frameIndex - track.lastDetectionFrameIndex
            if lostFrames > configuration.maxLostFrames {
                track.markRemoved()
            }
        }

        tracks.removeAll { $0.state == .removed }

        return tracks.compactMap { track in
            switch track.state {
            case .tracked:
                return track.trackResult(currentFrameIndex: frameIndex)
            case .lost:
                let lostFrames = frameIndex - track.lastDetectionFrameIndex
                guard lostFrames <= configuration.predictionOnlyFrames else { return nil }
                return track.trackResult(currentFrameIndex: frameIndex)
            case .removed:
                return nil
            }
        }
        .sorted { lhs, rhs in
            lhs.trackID < rhs.trackID
        }
    }

    private func associate(
        tracks: [Track],
        detections: [Detection],
        minimumIoU: CGFloat
    ) -> AssociationResult {
        guard !tracks.isEmpty, !detections.isEmpty else {
            return AssociationResult(
                matches: [],
                unmatchedTracks: tracks,
                unmatchedDetections: detections
            )
        }

        let assignments = linearAssignment(rowCount: tracks.count, columnCount: detections.count) { row, column in
            let track = tracks[row]
            let detection = detections[column]
            guard track.detection.classID == detection.classID else { return 1.0 }
            return 1.0 - Double(iou(lhs: track.predictedRect, rhs: detection.rect))
        }

        var matches: [(track: Track, detection: Detection)] = []
        var matchedTrackIndices = Set<Int>()
        var matchedDetectionIndices = Set<Int>()

        for assignment in assignments {
            let track = tracks[assignment.row]
            let detection = detections[assignment.column]
            guard track.detection.classID == detection.classID else { continue }

            let overlap = iou(lhs: track.predictedRect, rhs: detection.rect)
            guard overlap >= minimumIoU else { continue }

            matches.append((track: track, detection: detection))
            matchedTrackIndices.insert(assignment.row)
            matchedDetectionIndices.insert(assignment.column)
        }

        let unmatchedTracks = tracks.enumerated().compactMap { index, track in
            matchedTrackIndices.contains(index) ? nil : track
        }
        let unmatchedDetections = detections.enumerated().compactMap { index, detection in
            matchedDetectionIndices.contains(index) ? nil : detection
        }

        return AssociationResult(
            matches: matches,
            unmatchedTracks: unmatchedTracks,
            unmatchedDetections: unmatchedDetections
        )
    }

    private func linearAssignment(
        rowCount: Int,
        columnCount: Int,
        cost: (Int, Int) -> Double
    ) -> [(row: Int, column: Int)] {
        let size = max(rowCount, columnCount)
        guard size > 0 else { return [] }

        var u = [Double](repeating: 0.0, count: size + 1)
        var v = [Double](repeating: 0.0, count: size + 1)
        var p = [Int](repeating: 0, count: size + 1)
        var way = [Int](repeating: 0, count: size + 1)

        for i in 1...size {
            p[0] = i
            var j0 = 0
            var minimumValues = [Double](repeating: .infinity, count: size + 1)
            var used = [Bool](repeating: false, count: size + 1)

            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Double.infinity
                var j1 = 0

                for j in 1...size where !used[j] {
                    let currentCost = squareCost(
                        row: i0 - 1,
                        column: j - 1,
                        rowCount: rowCount,
                        columnCount: columnCount,
                        cost: cost
                    )
                    let adjustedCost = currentCost - u[i0] - v[j]

                    if adjustedCost < minimumValues[j] {
                        minimumValues[j] = adjustedCost
                        way[j] = j0
                    }
                    if minimumValues[j] < delta {
                        delta = minimumValues[j]
                        j1 = j
                    }
                }

                for j in 0...size {
                    if used[j] {
                        u[p[j]] += delta
                        v[j] -= delta
                    } else {
                        minimumValues[j] -= delta
                    }
                }

                j0 = j1
            } while p[j0] != 0

            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }

        var assignments: [(row: Int, column: Int)] = []
        for j in 1...size {
            let i = p[j]
            if i > 0, i <= rowCount, j <= columnCount {
                assignments.append((row: i - 1, column: j - 1))
            }
        }
        return assignments
    }

    private func squareCost(
        row: Int,
        column: Int,
        rowCount: Int,
        columnCount: Int,
        cost: (Int, Int) -> Double
    ) -> Double {
        guard row < rowCount, column < columnCount else { return 1.0 }
        return cost(row, column).clamped(to: 0.0...1.0)
    }

    private func iou(lhs: CGRect, rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        if intersection.isNull || intersection.isEmpty { return 0.0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersectionArea
        guard unionArea > 0 else { return 0.0 }
        return intersectionArea / unionArea
    }
}

private extension CGRect {
    func blended(with other: CGRect, newValueWeight: CGFloat) -> CGRect {
        let oldValueWeight = 1.0 - newValueWeight
        return CGRect(
            x: (origin.x * oldValueWeight) + (other.origin.x * newValueWeight),
            y: (origin.y * oldValueWeight) + (other.origin.y * newValueWeight),
            width: (width * oldValueWeight) + (other.width * newValueWeight),
            height: (height * oldValueWeight) + (other.height * newValueWeight)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
