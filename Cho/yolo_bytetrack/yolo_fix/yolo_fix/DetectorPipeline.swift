import AVFoundation
import Foundation
import QuartzCore
import UIKit

struct DetectorPipelineConfiguration {
    var modelName: String = "detector"
    var modelExtension: String = "pte"
    var inputWidth: Int = 640
    var inputHeight: Int = 640
    var confidenceThreshold: Float = 0.40
    var nmsIoUThreshold: CGFloat = 0.45
    var classNames: [String] = ["person"]
    var rawModelClassCount: Int? = 80
    var sourceClassMap: [Int: Int] = [0: 0]

    static let current640 = DetectorPipelineConfiguration()

    static let highResolution1024x576 = DetectorPipelineConfiguration(
        inputWidth: 1024,
        inputHeight: 576
    )

    static let tracking1024x576 = DetectorPipelineConfiguration(
        inputWidth: 1024,
        inputHeight: 576,
        confidenceThreshold: 0.10,
        classNames: ["person", "ball"],
        rawModelClassCount: 80,
        sourceClassMap: [0: 0, 32: 1]
    )
}

struct DetectionRunResult {
    let detections: [Detection]
    let originalImageSize: CGSize
    let inputShape: [Int]
    let letterbox: LetterboxInfo
    let inferenceTimeMs: Double
    let timestampSeconds: Double
}

final class DetectorPipeline {
    private let runner: ExecuTorchRunner
    private let preprocessor: FramePreprocessor
    private let postProcessor: DetectionPostProcessor

    init(configuration: DetectorPipelineConfiguration = .current640) throws {
        self.runner = try ExecuTorchRunner(modelName: configuration.modelName, fileExtension: configuration.modelExtension)
        self.preprocessor = FramePreprocessor(inputWidth: configuration.inputWidth, inputHeight: configuration.inputHeight)
        self.postProcessor = DetectionPostProcessor(
            confidenceThreshold: configuration.confidenceThreshold,
            nmsIoUThreshold: configuration.nmsIoUThreshold,
            classNames: configuration.classNames,
            rawModelClassCount: configuration.rawModelClassCount,
            sourceClassMap: configuration.sourceClassMap
        )
    }

    func detect(pixelBuffer: CVPixelBuffer, timestamp: CMTime) throws -> DetectionRunResult {
        guard let framePacket = preprocessor.prepare(pixelBuffer: pixelBuffer, timestamp: timestamp) else {
            throw DetectorPipelineError.preprocessingFailed
        }

        return try run(framePacket: framePacket)
    }

    func detect(image: UIImage) throws -> DetectionRunResult {
        guard let framePacket = preprocessor.prepare(image: image) else {
            throw DetectorPipelineError.preprocessingFailed
        }

        return try run(framePacket: framePacket)
    }

    private func run(framePacket: FramePacket) throws -> DetectionRunResult {
        let startTime = CACurrentMediaTime()
        let rawOutput = try runner.predict(
            input: framePacket.tensorData,
            shape: framePacket.inputShape
        )
        let detections = postProcessor.parse(
            rawOutput: rawOutput,
            letterbox: framePacket.letterbox
        )
        let inferenceTimeMs = (CACurrentMediaTime() - startTime) * 1000.0

        return DetectionRunResult(
            detections: detections,
            originalImageSize: framePacket.originalImageSize,
            inputShape: framePacket.inputShape,
            letterbox: framePacket.letterbox,
            inferenceTimeMs: inferenceTimeMs,
            timestampSeconds: framePacket.timestampSeconds
        )
    }
}

enum DetectorPipelineError: Error {
    case preprocessingFailed
}
