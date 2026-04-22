import AVFoundation
import CoreImage
import Foundation
import UIKit

final class FramePreprocessor {
    private let inputWidth: Int
    private let inputHeight: Int
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let paddingColor = CIColor(red: 114.0 / 255.0, green: 114.0 / 255.0, blue: 114.0 / 255.0)

    init(inputWidth: Int = 640, inputHeight: Int = 640) {
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
    }

    func prepare(pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> FramePacket? {
        let sourceWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let timestampSeconds = CMTimeGetSeconds(timestamp).isFinite ? CMTimeGetSeconds(timestamp) : CFAbsoluteTimeGetCurrent()

        return prepare(
            sourceImage: sourceImage,
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
            timestampSeconds: timestampSeconds
        )
    }

    func prepare(image: UIImage, timestampSeconds: TimeInterval = CFAbsoluteTimeGetCurrent()) -> FramePacket? {
        guard let sourceImage = CIImage(image: image) else {
            return nil
        }

        let sourceSize = CGSize(width: sourceImage.extent.width, height: sourceImage.extent.height)
        return prepare(
            sourceImage: sourceImage,
            sourceSize: sourceSize,
            timestampSeconds: timestampSeconds
        )
    }

    private func prepare(sourceImage: CIImage, sourceSize: CGSize, timestampSeconds: TimeInterval) -> FramePacket? {
        guard
            sourceSize.width > 0,
            sourceSize.height > 0,
            let letterboxedBuffer = makeResizeBuffer(width: inputWidth, height: inputHeight)
        else {
            return nil
        }

        let inputSize = CGSize(width: inputWidth, height: inputHeight)
        let scale = Swift.min(inputSize.width / sourceSize.width, inputSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let padX = (inputSize.width - scaledSize.width) * 0.5
        let padY = (inputSize.height - scaledSize.height) * 0.5
        let inputRect = CGRect(origin: .zero, size: inputSize)

        let background = CIImage(color: paddingColor).cropped(to: inputRect)
        let transformedImage = sourceImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))
        let composedImage = transformedImage.composited(over: background)

        ciContext.render(
            composedImage,
            to: letterboxedBuffer,
            bounds: inputRect,
            colorSpace: colorSpace
        )

        CVPixelBufferLockBaseAddress(letterboxedBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(letterboxedBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(letterboxedBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(letterboxedBuffer)
        let raw = baseAddress.assumingMemoryBound(to: UInt8.self)
        let planeSize = inputWidth * inputHeight
        var tensorData = [Float](repeating: 0.0, count: planeSize * 3)

        for y in 0..<inputHeight {
            let row = raw.advanced(by: y * bytesPerRow)
            for x in 0..<inputWidth {
                let pixel = row.advanced(by: x * 4)
                let b = Float(pixel[0]) / 255.0
                let g = Float(pixel[1]) / 255.0
                let r = Float(pixel[2]) / 255.0
                let index = y * inputWidth + x

                tensorData[index] = r
                tensorData[planeSize + index] = g
                tensorData[(2 * planeSize) + index] = b
            }
        }

        let letterbox = LetterboxInfo(
            inputSize: inputSize,
            originalSize: sourceSize,
            scaledSize: scaledSize,
            scale: scale,
            padX: padX,
            padY: padY
        )

        return FramePacket(
            tensorData: tensorData,
            inputShape: [1, 3, inputHeight, inputWidth],
            originalImageSize: sourceSize,
            timestampSeconds: timestampSeconds,
            letterbox: letterbox
        )
    }

    private func makeResizeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        return pixelBuffer
    }
}
