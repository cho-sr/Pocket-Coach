import Foundation
import AVFoundation
import Vision
import CoreML
import CoreImage

struct DetectionBox {
    let rect640: CGRect
    let confidence: Float
}

protocol CameraTrackerManagerDelegate: AnyObject {
    func trackerManager(_ manager: CameraTrackerManager, didUpdateTarget target: DetectionBox, deltaAngle: Int)
    func trackerManagerDidLoseTarget(_ manager: CameraTrackerManager)
}

final class CameraTrackerManager: NSObject {
    weak var delegate: CameraTrackerManagerDelegate?

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "poket.camera.processing", qos: .userInitiated)
    private let ciContext = CIContext()

    private let yoloRequest: VNCoreMLRequest
    private let osnetRequest: VNCoreMLRequest
    private let midiManager: CoreMIDIManager

    private var targetBox: DetectionBox?
    private var targetEmbedding: [Float]?
    private var pendingLockPoint640: CGPoint?
    private var lastOrientedFrameSize: CGSize?

    private let fastPathMaxDistance: CGFloat = 90.0
    private let fastPathMinIoU: CGFloat = 0.10
    private let slowPathMinCosine: Float = 0.75

    init(yoloModel: MLModel, osnetModel: MLModel, midiManager: CoreMIDIManager = CoreMIDIManager()) throws {
        self.midiManager = midiManager

        let yoloVNModel = try VNCoreMLModel(for: yoloModel)
        let osnetVNModel = try VNCoreMLModel(for: osnetModel)

        self.yoloRequest = VNCoreMLRequest(model: yoloVNModel)
        self.osnetRequest = VNCoreMLRequest(model: osnetVNModel)

        super.init()

        yoloRequest.imageCropAndScaleOption = .scaleFill
        osnetRequest.imageCropAndScaleOption = .scaleFill

        try configureCaptureSession()
    }

    func start() {
        processingQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stop() {
        processingQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    // Expects a point in the model input space: 640x640.
    func lockOnTarget(at point640: CGPoint) {
        processingQueue.async {
            let clampedX = min(max(point640.x, 0), 640)
            let clampedY = min(max(point640.y, 0), 640)
            self.pendingLockPoint640 = CGPoint(x: clampedX, y: clampedY)
        }
    }

    // Maps a tap point in preview coordinates to the 640x640 model space,
    // while accounting for AVLayerVideoGravity crop/letterbox behavior.
    @discardableResult
    func lockOnTarget(
        fromViewPoint point: CGPoint,
        inPreviewBounds previewBounds: CGRect,
        videoGravity: AVLayerVideoGravity
    ) -> Bool {
        var didQueueLock = false
        processingQueue.sync {
            guard let sourceSize = self.lastOrientedFrameSize,
                  let mapped = self.mapPreviewPointToModel640(
                      point,
                      previewBounds: previewBounds,
                      sourceImageSize: sourceSize,
                      videoGravity: videoGravity
                  ) else {
                didQueueLock = false
                return
            }

            self.pendingLockPoint640 = mapped
            didQueueLock = true
        }
        return didQueueLock
    }

    private func configureCaptureSession() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "CameraTrackerManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Back camera not available"])
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            throw NSError(domain: "CameraTrackerManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        captureSession.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoOutput) else {
            throw NSError(domain: "CameraTrackerManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        captureSession.commitConfiguration()
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let resized640 = resize(pixelBuffer: pixelBuffer, width: 640, height: 640) else {
            return
        }

        let detections = detectPersons(in: resized640)
        guard !detections.isEmpty else {
            targetBox = nil
            targetEmbedding = nil
            DispatchQueue.main.async {
                self.delegate?.trackerManagerDidLoseTarget(self)
            }
            return
        }

        if let lockPoint = pendingLockPoint640 {
            guard let lockedTarget = lockOnCandidate(at: lockPoint, candidates: detections) else {
                DispatchQueue.main.async {
                    self.delegate?.trackerManagerDidLoseTarget(self)
                }
                return
            }

            pendingLockPoint640 = nil
            targetBox = lockedTarget

            if let emb = extractEmbedding(from: lockedTarget, frame640: resized640) {
                targetEmbedding = emb
            }

            let cx = min(max(lockedTarget.rect640.midX, 0), 640)
            let delta = deltaAngleFromCenterX(cx)
            if delta != 0 {
                midiManager.sendDeltaAngle(delta)
            }

            DispatchQueue.main.async {
                self.delegate?.trackerManager(self, didUpdateTarget: lockedTarget, deltaAngle: delta)
            }
            return
        }

        guard targetBox != nil else {
            DispatchQueue.main.async {
                self.delegate?.trackerManagerDidLoseTarget(self)
            }
            return
        }

        let selected: DetectionBox?
        if let previous = targetBox, let fastMatch = fastPathMatch(previous: previous, candidates: detections) {
            selected = fastMatch
        } else {
            selected = slowPathReidentify(candidates: detections, frame640: resized640)
        }

        guard let currentTarget = selected else {
            targetBox = nil
            DispatchQueue.main.async {
                self.delegate?.trackerManagerDidLoseTarget(self)
            }
            return
        }

        targetBox = currentTarget

        if let newEmbedding = extractEmbedding(from: currentTarget, frame640: resized640) {
            if let old = targetEmbedding {
                targetEmbedding = blendedEmbedding(old: old, new: newEmbedding, alpha: 0.2)
            } else {
                targetEmbedding = newEmbedding
            }
        }

        let cx = min(max(currentTarget.rect640.midX, 0), 640)
        let delta = deltaAngleFromCenterX(cx)
        if delta != 0 {
            midiManager.sendDeltaAngle(delta)
        }

        DispatchQueue.main.async {
            self.delegate?.trackerManager(self, didUpdateTarget: currentTarget, deltaAngle: delta)
        }
    }

    private func detectPersons(in pixelBuffer: CVPixelBuffer) -> [DetectionBox] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([yoloRequest])
        } catch {
            return []
        }

        guard let observations = yoloRequest.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        var boxes: [DetectionBox] = []
        boxes.reserveCapacity(observations.count)

        for obs in observations {
            guard let top = obs.labels.first else { continue }
            if top.identifier.lowercased() != "person" { continue }

            let rect = denormalizeTo640(obs.boundingBox)
            boxes.append(DetectionBox(rect640: rect, confidence: top.confidence))
        }

        return boxes
    }

    private func fastPathMatch(previous: DetectionBox, candidates: [DetectionBox]) -> DetectionBox? {
        var best: DetectionBox?
        var bestScore: CGFloat = -.greatestFiniteMagnitude

        for candidate in candidates {
            let iouScore = iou(previous.rect640, candidate.rect640)
            let distance = centerDistance(previous.rect640, candidate.rect640)
            let distanceScore = max(0, 1.0 - (distance / 200.0))
            let total = (iouScore * 0.65) + (distanceScore * 0.35)

            if total > bestScore {
                bestScore = total
                best = candidate
            }
        }

        guard let matched = best else { return nil }

        let matchedIoU = iou(previous.rect640, matched.rect640)
        let matchedDistance = centerDistance(previous.rect640, matched.rect640)

        if matchedIoU >= fastPathMinIoU || matchedDistance <= fastPathMaxDistance {
            return matched
        }

        return nil
    }

    private func slowPathReidentify(candidates: [DetectionBox], frame640: CVPixelBuffer) -> DetectionBox? {
        guard let referenceEmbedding = targetEmbedding else {
            return nil
        }

        var best: DetectionBox?
        var bestScore: Float = -1.0

        for candidate in candidates {
            guard let emb = extractEmbedding(from: candidate, frame640: frame640) else { continue }
            let score = cosineSimilarity(referenceEmbedding, emb)
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }

        guard bestScore >= slowPathMinCosine else {
            return nil
        }

        return best
    }

    private func lockOnCandidate(at point640: CGPoint, candidates: [DetectionBox]) -> DetectionBox? {
        let containing = candidates.filter { $0.rect640.contains(point640) }
        guard !containing.isEmpty else { return nil }

        return containing.min {
            centerDistance($0.rect640, CGRect(x: point640.x, y: point640.y, width: 0, height: 0))
            < centerDistance($1.rect640, CGRect(x: point640.x, y: point640.y, width: 0, height: 0))
        }
    }

    private func extractEmbedding(from detection: DetectionBox, frame640: CVPixelBuffer) -> [Float]? {
        guard let crop = cropAndResize(pixelBuffer: frame640, rect: detection.rect640, outWidth: 128, outHeight: 256) else {
            return nil
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: crop, options: [:])
        do {
            try handler.perform([osnetRequest])
        } catch {
            return nil
        }

        guard let results = osnetRequest.results else {
            return nil
        }

        for item in results {
            if let feat = item as? VNCoreMLFeatureValueObservation,
               let array = feat.featureValue.multiArrayValue {
                return multiArrayToFloat(array)
            }
        }

        return nil
    }

    private func resize(pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(width) / ciImage.extent.width
        let sy = CGFloat(height) / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let output = out else {
            return nil
        }

        ciContext.render(scaled, to: output)
        return output
    }

    private func cropAndResize(pixelBuffer: CVPixelBuffer, rect: CGRect, outWidth: Int, outHeight: Int) -> CVPixelBuffer? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let bounded = rect.intersection(CGRect(x: 0, y: 0, width: 640, height: 640))
        guard !bounded.isNull, bounded.width > 1, bounded.height > 1 else {
            return nil
        }

        let cropped = image.cropped(to: bounded)
        let sx = CGFloat(outWidth) / bounded.width
        let sy = CGFloat(outHeight) / bounded.height
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outWidth,
            kCVPixelBufferHeightKey as String: outHeight
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault, outWidth, outHeight, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let output = out else {
            return nil
        }

        ciContext.render(scaled, to: output)
        return output
    }

    private func denormalizeTo640(_ normalized: CGRect) -> CGRect {
        let x = normalized.minX * 640.0
        let y = (1.0 - normalized.maxY) * 640.0
        let w = normalized.width * 640.0
        let h = normalized.height * 640.0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func centerDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return sqrt((dx * dx) + (dy * dy))
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return -1 }

        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0

        for i in 0..<count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }

        let denom = (sqrt(na) * sqrt(nb))
        if denom < 1e-8 { return -1 }
        return dot / denom
    }

    private func blendedEmbedding(old: [Float], new: [Float], alpha: Float) -> [Float] {
        let n = min(old.count, new.count)
        guard n > 0 else { return new }
        var result = Array(repeating: Float(0), count: n)
        for i in 0..<n {
            result[i] = old[i] * (1 - alpha) + new[i] * alpha
        }
        return result
    }

    private func multiArrayToFloat(_ array: MLMultiArray) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(array.count)

        for i in 0..<array.count {
            let value = array[i]
            result.append(Float(truncating: value))
        }

        return result
    }

    private func deltaAngleFromCenterX(_ cx: CGFloat) -> Int {
        switch cx {
        case 0...120:
            return -15
        case 121...220:
            return -10
        case 221...280:
            return -5
        case 281...360:
            return 0
        case 361...420:
            return 5
        case 421...520:
            return 10
        default:
            return 15
        }
    }

    private func mapPreviewPointToModel640(
        _ point: CGPoint,
        previewBounds: CGRect,
        sourceImageSize: CGSize,
        videoGravity: AVLayerVideoGravity
    ) -> CGPoint? {
        guard previewBounds.width > 0,
              previewBounds.height > 0,
              sourceImageSize.width > 0,
              sourceImageSize.height > 0 else {
            return nil
        }

        let videoRect = previewVideoRect(
            sourceImageSize: sourceImageSize,
            previewBounds: previewBounds,
            videoGravity: videoGravity
        )

        // For .resizeAspect (letterbox), reject taps outside visible video content.
        if videoGravity == .resizeAspect && !videoRect.contains(point) {
            return nil
        }

        let nx = (point.x - videoRect.minX) / videoRect.width
        let ny = (point.y - videoRect.minY) / videoRect.height

        let clampedNX = min(max(nx, 0), 1)
        let clampedNY = min(max(ny, 0), 1)

        let sourceX = clampedNX * sourceImageSize.width
        let sourceY = clampedNY * sourceImageSize.height

        // The detector path uses resize(pixelBuffer, 640, 640) i.e. scaleFill.
        let modelX = (sourceX / sourceImageSize.width) * 640.0
        let modelY = (sourceY / sourceImageSize.height) * 640.0

        return CGPoint(x: modelX, y: modelY)
    }

    private func previewVideoRect(
        sourceImageSize: CGSize,
        previewBounds: CGRect,
        videoGravity: AVLayerVideoGravity
    ) -> CGRect {
        switch videoGravity {
        case .resize:
            return previewBounds

        case .resizeAspect:
            let scale = min(previewBounds.width / sourceImageSize.width,
                            previewBounds.height / sourceImageSize.height)
            let w = sourceImageSize.width * scale
            let h = sourceImageSize.height * scale
            let x = previewBounds.midX - (w * 0.5)
            let y = previewBounds.midY - (h * 0.5)
            return CGRect(x: x, y: y, width: w, height: h)

        default: // .resizeAspectFill
            let scale = max(previewBounds.width / sourceImageSize.width,
                            previewBounds.height / sourceImageSize.height)
            let w = sourceImageSize.width * scale
            let h = sourceImageSize.height * scale
            let x = previewBounds.midX - (w * 0.5)
            let y = previewBounds.midY - (h * 0.5)
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    private func orientedFrameSize(rawWidth: Int, rawHeight: Int) -> CGSize {
        let orientation = videoOutput.connection(with: .video)?.videoOrientation ?? .portrait
        switch orientation {
        case .portrait, .portraitUpsideDown:
            return CGSize(width: rawHeight, height: rawWidth)
        default:
            return CGSize(width: rawWidth, height: rawHeight)
        }
    }
}

extension CameraTrackerManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let rawWidth = CVPixelBufferGetWidth(pixelBuffer)
        let rawHeight = CVPixelBufferGetHeight(pixelBuffer)
        lastOrientedFrameSize = orientedFrameSize(rawWidth: rawWidth, rawHeight: rawHeight)

        processFrame(pixelBuffer)
    }
}
