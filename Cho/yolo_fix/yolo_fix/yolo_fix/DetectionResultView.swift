import AVFoundation
import UIKit

final class DetectionResultView: UIView {
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    private var image: UIImage?
    private var detections: [Detection] = []
    private var statusText: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: UIImage?, detections: [Detection], statusText: String? = nil) {
        self.image = image
        self.detections = detections
        self.statusText = statusText
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        if let image {
            image.draw(in: aspectFitRect(imageSize: image.size, container: bounds))
        }

        for detection in detections {
            let drawRect = convertedRect(from: detection.rect)
            let color = colorForClass(id: detection.classID)

            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(3.0)
            context.stroke(drawRect)
            context.restoreGState()

            drawLabel(
                "\(detection.className) \(Int(detection.confidence * 100))%",
                at: drawRect,
                color: color
            )
        }

        if let statusText {
            drawStatus(statusText)
        }
    }

    private func convertedRect(from normalizedRect: CGRect) -> CGRect {
        if let previewLayer {
            return previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
        }

        guard let image else {
            return CGRect(
                x: normalizedRect.minX * bounds.width,
                y: normalizedRect.minY * bounds.height,
                width: normalizedRect.width * bounds.width,
                height: normalizedRect.height * bounds.height
            )
        }

        let imageRect = aspectFitRect(imageSize: image.size, container: bounds)
        return CGRect(
            x: imageRect.minX + (normalizedRect.minX * imageRect.width),
            y: imageRect.minY + (normalizedRect.minY * imageRect.height),
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
    }

    private func aspectFitRect(imageSize: CGSize, container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }

        let scale = Swift.min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: container.midX - (width * 0.5),
            y: container.midY - (height * 0.5),
            width: width,
            height: height
        )
    }

    private func drawLabel(_ text: String, at rect: CGRect, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.white,
            .backgroundColor: color,
        ]
        let textRect = CGRect(
            x: rect.minX,
            y: Swift.max(0.0, rect.minY - 20.0),
            width: Swift.min(bounds.width - rect.minX, 220.0),
            height: 18.0
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func drawStatus(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor.white,
            .backgroundColor: UIColor.black.withAlphaComponent(0.55),
        ]
        text.draw(
            in: CGRect(x: 12, y: 12, width: Swift.min(bounds.width - 24, 520), height: 24),
            withAttributes: attributes
        )
    }

    private func colorForClass(id: Int) -> UIColor {
        let palette: [UIColor] = [
            .systemGreen,
            .systemCyan,
            .systemOrange,
            .systemPink,
            .systemYellow,
            .systemTeal,
            .systemRed,
        ]
        return palette[abs(id) % palette.count]
    }
}
