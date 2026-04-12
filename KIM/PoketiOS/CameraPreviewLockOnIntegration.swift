import UIKit
import AVFoundation
import SwiftUI
import CoreML

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = self.layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}

final class TrackingViewController: UIViewController {
    private let trackerManager: CameraTrackerManager
    private let previewView = CameraPreviewView()
    private let targetOverlay = CAShapeLayer()
    private let targetLabelBackground = CALayer()
    private let targetLabelText = CATextLayer()

    init(yoloModel: MLModel, osnetModel: MLModel) throws {
        self.trackerManager = try CameraTrackerManager(yoloModel: yoloModel, osnetModel: osnetModel)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        previewView.frame = view.bounds
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewView)

        // 카메라 프리뷰를 화면 가득 채우고(Aspect Fill), 추적 세션을 연결한다.
        previewView.previewLayer.session = trackerManager.captureSession
        previewView.previewLayer.videoGravity = .resizeAspectFill

        trackerManager.delegate = self

        // 실시간 타겟 박스(빨간 테두리) 오버레이 설정.
        targetOverlay.strokeColor = UIColor.red.cgColor
        targetOverlay.fillColor = UIColor.clear.cgColor
        targetOverlay.lineWidth = 2.0
        targetOverlay.isHidden = true
        previewView.layer.addSublayer(targetOverlay)

        // 선택된 타겟의 Confidence만 표시하는 라벨 레이어(ID는 표시하지 않음).
        targetLabelBackground.backgroundColor = UIColor.red.withAlphaComponent(0.88).cgColor
        targetLabelBackground.cornerRadius = 6
        targetLabelBackground.masksToBounds = true
        targetLabelBackground.isHidden = true
        previewView.layer.addSublayer(targetLabelBackground)

        targetLabelText.contentsScale = UIScreen.main.scale
        targetLabelText.alignmentMode = .left
        targetLabelText.foregroundColor = UIColor.white.cgColor
        targetLabelText.fontSize = 12
        targetLabelText.isWrapped = false
        targetLabelText.truncationMode = .end
        targetLabelBackground.addSublayer(targetLabelText)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePreviewTap(_:)))
        previewView.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        trackerManager.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        trackerManager.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.frame = view.bounds
        previewView.previewLayer.frame = previewView.bounds
        targetOverlay.frame = previewView.bounds
    }

    @objc private func handlePreviewTap(_ recognizer: UITapGestureRecognizer) {
        let layerPoint = recognizer.location(in: previewView)

        // videoGravity(.resizeAspectFill 포함)와 방향/크롭을 고려해
        // 뷰 좌표를 카메라 정규화 좌표(0~1)로 변환한다.
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)

        // 정규화 좌표를 640x640 모델 좌표계로 변환한다.
        let x640 = min(max(devicePoint.x, 0), 1) * 640.0
        let y640 = min(max(devicePoint.y, 0), 1) * 640.0
        trackerManager.lockOnTarget(at: CGPoint(x: x640, y: y640))
    }

    // 모델 좌표계(640x640) 박스를 현재 프리뷰 레이어 좌표계로 변환한다.
    private func overlayRectInView(from rect640: CGRect) -> CGRect {
        let normalized = CGRect(
            x: rect640.origin.x / 640.0,
            y: rect640.origin.y / 640.0,
            width: rect640.size.width / 640.0,
            height: rect640.size.height / 640.0
        )

        return previewView.previewLayer.layerRectConverted(fromMetadataOutputRect: normalized)
    }
}

extension TrackingViewController: CameraTrackerManagerDelegate {
    func trackerManager(_ manager: CameraTrackerManager, didUpdateTarget target: DetectionBox, deltaAngle: Int) {
        let rectInView = overlayRectInView(from: target.rect640)
        let path = UIBezierPath(rect: rectInView)

        // 프레임마다 암시적 애니메이션을 제거해 지연 없이 즉시 위치를 갱신한다.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        targetOverlay.path = path.cgPath
        targetOverlay.isHidden = false

        let confidencePercent = Int((target.confidence * 100).rounded())
        let labelText = "Target (\(confidencePercent)%)"
        targetLabelText.string = labelText

        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let textSize = (labelText as NSString).size(withAttributes: [.font: font])
        let paddingX: CGFloat = 8
        let paddingY: CGFloat = 4
        let labelWidth = textSize.width + (paddingX * 2)
        let labelHeight = textSize.height + (paddingY * 2)

        var labelX = rectInView.minX
        var labelY = rectInView.minY - labelHeight - 6
        if labelY < 4 { labelY = rectInView.minY + 4 }
        if labelX + labelWidth > previewView.bounds.width - 4 {
            labelX = previewView.bounds.width - labelWidth - 4
        }
        if labelX < 4 { labelX = 4 }

        targetLabelBackground.frame = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        targetLabelText.frame = CGRect(x: paddingX, y: paddingY, width: textSize.width, height: textSize.height)
        targetLabelBackground.isHidden = false
        CATransaction.commit()
    }

    func trackerManagerDidLoseTarget(_ manager: CameraTrackerManager) {
        targetOverlay.isHidden = true
        targetOverlay.path = nil
        targetLabelBackground.isHidden = true
        targetLabelText.string = nil
    }
}

struct TrackingCameraView: UIViewControllerRepresentable {
    let yoloModel: MLModel
    let osnetModel: MLModel

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            return try TrackingViewController(yoloModel: yoloModel, osnetModel: osnetModel)
        } catch {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .black

            let label = UILabel()
            label.text = "카메라 초기화 실패: \(error.localizedDescription)"
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.frame = fallback.view.bounds.insetBy(dx: 24, dy: 24)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            fallback.view.addSubview(label)

            return fallback
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
