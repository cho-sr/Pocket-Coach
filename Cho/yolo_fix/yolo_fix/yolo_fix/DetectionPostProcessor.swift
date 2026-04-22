import CoreGraphics
import Foundation

final class DetectionPostProcessor {
    private let confidenceThreshold: Float
    private let nmsIoUThreshold: CGFloat
    private let classNames: [String]
    private let rawModelClassCount: Int?
    private let sourceClassMap: [Int: Int]

    init(
        confidenceThreshold: Float = 0.35,
        nmsIoUThreshold: CGFloat = 0.45,
        classNames: [String] = ["person", "ball"],
        rawModelClassCount: Int? = nil,
        sourceClassMap: [Int: Int] = [:]
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.nmsIoUThreshold = nmsIoUThreshold
        self.classNames = classNames
        self.rawModelClassCount = rawModelClassCount
        self.sourceClassMap = sourceClassMap
    }

    func parse(rawOutput: [Float], letterbox: LetterboxInfo) -> [Detection] {
        guard rawOutput.count >= 6 else { return [] }

        if let rawModelClassCount {
            let channelCount = 4 + rawModelClassCount
            if rawOutput.count % channelCount == 0 && rawOutput.count >= channelCount {
                return parseUltralyticsChannelMajorOutput(
                    rawOutput: rawOutput,
                    letterbox: letterbox,
                    rawModelClassCount: rawModelClassCount
                )
            }
        }

        return parseFlatOutput(rawOutput: rawOutput, letterbox: letterbox)
    }

    func parse(rawOutput: [Float], inputWidth: CGFloat = 1.0, inputHeight: CGFloat = 1.0) -> [Detection] {
        let safeInputWidth = Swift.max(inputWidth, 1.0)
        let safeInputHeight = Swift.max(inputHeight, 1.0)
        let identityLetterbox = LetterboxInfo(
            inputSize: CGSize(width: safeInputWidth, height: safeInputHeight),
            originalSize: CGSize(width: safeInputWidth, height: safeInputHeight),
            scaledSize: CGSize(width: safeInputWidth, height: safeInputHeight),
            scale: 1.0,
            padX: 0.0,
            padY: 0.0
        )
        return parse(rawOutput: rawOutput, letterbox: identityLetterbox)
    }

    private func parseFlatOutput(rawOutput: [Float], letterbox: LetterboxInfo) -> [Detection] {
        var detections: [Detection] = []

        for start in stride(from: 0, to: rawOutput.count, by: 6) {
            guard start + 5 < rawOutput.count else { break }

            let score = rawOutput[start + 4]
            if score < confidenceThreshold { continue }

            let sourceClassID = Int(rawOutput[start + 5])
            guard let resolvedClass = resolvedClass(sourceClassID: sourceClassID) else {
                continue
            }

            let rawX1 = CGFloat(rawOutput[start])
            let rawY1 = CGFloat(rawOutput[start + 1])
            let rawX2 = CGFloat(rawOutput[start + 2])
            let rawY2 = CGFloat(rawOutput[start + 3])
            let usesAbsoluteInputPixels = Swift.max(
                Swift.max(abs(rawX1), abs(rawY1)),
                Swift.max(abs(rawX2), abs(rawY2))
            ) > 2.0

            let x1 = usesAbsoluteInputPixels ? rawX1 : rawX1 * letterbox.inputSize.width
            let y1 = usesAbsoluteInputPixels ? rawY1 : rawY1 * letterbox.inputSize.height
            let x2 = usesAbsoluteInputPixels ? rawX2 : rawX2 * letterbox.inputSize.width
            let y2 = usesAbsoluteInputPixels ? rawY2 : rawY2 * letterbox.inputSize.height
            let rect = letterbox.normalizedOriginalRect(
                fromModelPixelRect: CGRect(
                    x: Swift.min(x1, x2),
                    y: Swift.min(y1, y2),
                    width: abs(x2 - x1),
                    height: abs(y2 - y1)
                )
            )

            guard rect.width > 0.001, rect.height > 0.001 else { continue }
            detections.append(
                Detection(
                    rect: rect,
                    confidence: score,
                    classID: resolvedClass.localID,
                    className: resolvedClass.name
                )
            )
        }

        return applyNMS(to: detections)
    }

    private func parseUltralyticsChannelMajorOutput(
        rawOutput: [Float],
        letterbox: LetterboxInfo,
        rawModelClassCount: Int
    ) -> [Detection] {
        let channelCount = 4 + rawModelClassCount
        let anchorCount = rawOutput.count / channelCount
        let classMap = resolvedSourceClassMap(rawModelClassCount: rawModelClassCount)
        var detections: [Detection] = []

        guard anchorCount > 0, !classMap.isEmpty else { return [] }

        for anchorIndex in 0..<anchorCount {
            var bestScore: Float = 0.0
            var bestLocalClassID: Int?

            for (sourceClassID, localClassID) in classMap {
                let scoreIndex = (4 + sourceClassID) * anchorCount + anchorIndex
                guard scoreIndex < rawOutput.count else { continue }

                let score = rawOutput[scoreIndex]
                if score > bestScore {
                    bestScore = score
                    bestLocalClassID = localClassID
                }
            }

            guard
                let localClassID = bestLocalClassID,
                bestScore >= confidenceThreshold,
                localClassID >= 0,
                localClassID < classNames.count
            else {
                continue
            }

            let centerX = CGFloat(rawOutput[anchorIndex])
            let centerY = CGFloat(rawOutput[anchorCount + anchorIndex])
            let width = CGFloat(rawOutput[(2 * anchorCount) + anchorIndex])
            let height = CGFloat(rawOutput[(3 * anchorCount) + anchorIndex])
            let rect = normalizedRect(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height,
                letterbox: letterbox
            )

            guard rect.width > 0.001, rect.height > 0.001 else { continue }
            detections.append(
                Detection(
                    rect: rect,
                    confidence: bestScore,
                    classID: localClassID,
                    className: classNames[localClassID]
                )
            )
        }

        return applyNMS(to: detections)
    }

    private func normalizedRect(
        centerX: CGFloat,
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        letterbox: LetterboxInfo
    ) -> CGRect {
        let usesAbsoluteInputPixels = Swift.max(
            abs(centerX),
            abs(centerY),
            abs(width),
            abs(height)
        ) > 2.0

        let modelCenterX = usesAbsoluteInputPixels ? centerX : centerX * letterbox.inputSize.width
        let modelCenterY = usesAbsoluteInputPixels ? centerY : centerY * letterbox.inputSize.height
        let modelWidth = usesAbsoluteInputPixels ? width : width * letterbox.inputSize.width
        let modelHeight = usesAbsoluteInputPixels ? height : height * letterbox.inputSize.height

        return letterbox.normalizedOriginalRect(
            fromModelPixelRect: CGRect(
                x: modelCenterX - (modelWidth * 0.5),
                y: modelCenterY - (modelHeight * 0.5),
                width: modelWidth,
                height: modelHeight
            )
        )
    }

    private func resolvedSourceClassMap(rawModelClassCount: Int) -> [Int: Int] {
        if !sourceClassMap.isEmpty {
            return sourceClassMap
        }

        guard rawModelClassCount == classNames.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: classNames.indices.map { ($0, $0) })
    }

    private func resolvedClass(sourceClassID: Int) -> (localID: Int, name: String)? {
        let localClassID = sourceClassMap[sourceClassID] ?? sourceClassID
        if localClassID >= 0 && localClassID < classNames.count {
            return (localClassID, classNames[localClassID])
        }
        if classNames.count == 2 && classNames[0] == "person" && classNames[1] == "ball" && sourceClassID == 32 {
            return (1, classNames[1])
        }
        if sourceClassMap.isEmpty {
            return (sourceClassID, "cls_\(sourceClassID)")
        }
        return nil
    }

    private func applyNMS(to detections: [Detection]) -> [Detection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [Detection] = []

        for candidate in sorted {
            let shouldSuppress = kept.contains { keptDetection in
                keptDetection.classID == candidate.classID &&
                iou(lhs: keptDetection.rect, rhs: candidate.rect) > nmsIoUThreshold
            }

            if !shouldSuppress {
                kept.append(candidate)
            }
        }

        return kept
    }

    private func iou(lhs: CGRect, rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        if intersection.isNull || intersection.isEmpty { return 0.0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0.0 }
        return intersectionArea / unionArea
    }
}
