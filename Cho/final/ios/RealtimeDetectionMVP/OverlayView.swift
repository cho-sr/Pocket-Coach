import AVFoundation
import UIKit

final class OverlayView: UIView {
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    private var tracks: [TrackResult] = []
    private var selectedTrackID: Int?
    private var selectionGhostRect: CGRect?
    private var deadzoneRange: ClosedRange<CGFloat>?
    private var midiStatusText: String = "MIDI: searching..."
    private var commandText: String = "Command: idle"
    private var selectionStatusText: String = "Tap a player to select"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        tracks: [TrackResult],
        selectedTrackID: Int?,
        selectionGhostRect: CGRect?,
        deadzoneRange: ClosedRange<CGFloat>,
        midiStatusText: String,
        commandText: String,
        selectionStatusText: String
    ) {
        self.tracks = tracks
        self.selectedTrackID = selectedTrackID
        self.selectionGhostRect = selectionGhostRect
        self.deadzoneRange = deadzoneRange
        self.midiStatusText = midiStatusText
        self.commandText = commandText
        self.selectionStatusText = selectionStatusText

        DispatchQueue.main.async {
            self.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        drawDeadzone(in: context)
        for track in tracks {
            let isSelected = track.trackID == selectedTrackID
            let color = isSelected ? UIColor.systemCyan : colorForTrack(id: track.trackID)
            let drawRect = convertedRect(from: track.detection.rect)

            context.saveGState()
            if track.isPredictionOnly {
                context.setLineDash(phase: 0, lengths: [8, 4])
            }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(isSelected ? 4.0 : 2.0)
            context.stroke(drawRect)
            context.restoreGState()

            let label = track.isPredictionOnly
                ? "\(track.detection.className) #\(track.trackID) P"
                : "\(track.detection.className) #\(track.trackID) \(Int(track.detection.confidence * 100))%"

            let labelText = isSelected ? "TARGET \(label)" : label

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.white,
                .backgroundColor: color,
            ]

            let textRect = CGRect(
                x: drawRect.minX,
                y: max(CGFloat.zero, drawRect.minY - 20),
                width: min(bounds.width - drawRect.minX, 220),
                height: 18
            )
            labelText.draw(in: textRect, withAttributes: attributes)
        }

        if
            let selectedTrackID,
            !tracks.contains(where: { $0.trackID == selectedTrackID }),
            let selectionGhostRect
        {
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [10, 5])
            context.setStrokeColor(UIColor.systemRed.cgColor)
            context.setLineWidth(3.0)
            context.stroke(convertedRect(from: selectionGhostRect))
            context.restoreGState()
        }

        drawStatusPanel(in: context)
    }

    private func convertedRect(from normalizedRect: CGRect) -> CGRect {
        if let previewLayer {
            return previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
        }

        return CGRect(
            x: normalizedRect.minX * bounds.width,
            y: normalizedRect.minY * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        )
    }

    private func colorForTrack(id: Int) -> UIColor {
        let palette: [UIColor] = [
            .systemGreen,
            .systemOrange,
            .systemPink,
            .systemBlue,
            .systemYellow,
            .systemTeal,
            .systemRed,
        ]
        return palette[id % palette.count]
    }

    private func drawDeadzone(in context: CGContext) {
        guard let deadzoneRange else { return }

        let bandRect = convertedRect(
            from: CGRect(
                x: deadzoneRange.lowerBound,
                y: 0,
                width: deadzoneRange.upperBound - deadzoneRange.lowerBound,
                height: 1
            )
        )

        context.saveGState()
        context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.12).cgColor)
        context.fill(bandRect)
        context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1.5)
        context.stroke(bandRect)
        context.restoreGState()
    }

    private func drawStatusPanel(in context: CGContext) {
        let lines = [midiStatusText, commandText, selectionStatusText]
        let lineHeight: CGFloat = 18
        let panelPadding: CGFloat = 10
        let panelWidth = min(bounds.width - 24, 340)
        let panelHeight = (CGFloat(lines.count) * lineHeight) + (panelPadding * 2)
        let panelRect = CGRect(x: 12, y: 12, width: panelWidth, height: panelHeight)

        let panelPath = UIBezierPath(roundedRect: panelRect, cornerRadius: 12)
        context.saveGState()
        context.setFillColor(UIColor.black.withAlphaComponent(0.56).cgColor)
        context.addPath(panelPath.cgPath)
        context.fillPath()
        context.restoreGState()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor.white,
        ]

        for (index, line) in lines.enumerated() {
            let textRect = CGRect(
                x: panelRect.minX + panelPadding,
                y: panelRect.minY + panelPadding + (CGFloat(index) * lineHeight),
                width: panelRect.width - (panelPadding * 2),
                height: lineHeight
            )
            line.draw(in: textRect, withAttributes: attributes)
        }
    }
}
