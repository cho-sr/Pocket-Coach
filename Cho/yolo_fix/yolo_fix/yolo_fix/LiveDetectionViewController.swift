import AVFoundation
import QuartzCore
import UIKit

final class LiveDetectionViewController: UIViewController {
    private let cameraService = CameraService()
    private let resultView = DetectionResultView()
    private let statusLabel = UILabel()
    private let statusContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let stateQueue = DispatchQueue(label: "app.yolo_fix.live.state")
    private let inferenceQueue = DispatchQueue(label: "app.yolo_fix.live.inference", qos: .userInitiated)

    private var pipeline: DetectorPipeline?
    private var inferenceBusy = false
    private var pendingFrame: (pixelBuffer: CVPixelBuffer, timestamp: CMTime)?
    private var fpsWindowStart = CACurrentMediaTime()
    private var fpsFrameCount = 0
    private var currentFPS = 0.0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = DetectionMode.live.title
        view.backgroundColor = .black

        setupPipeline()
        setupCamera()
        setupOverlay()
        setupStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCameraOrientation()
        cameraService.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraService.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraService.previewLayer.frame = view.bounds
        updateCameraOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.cameraService.previewLayer.frame = self.view.bounds
            self.updateCameraOrientation()
        })
    }

    private func setupPipeline() {
        do {
            pipeline = try DetectorPipeline(configuration: .highResolution1024x576)
            statusLabel.text = "Live: ready"
        } catch {
            statusLabel.text = "Model load failed: \(error)"
            print("Failed to create DetectorPipeline: \(error)")
        }
    }

    private func setupCamera() {
        cameraService.delegate = self
        cameraService.configureSession()
        cameraService.previewLayer.frame = view.bounds
        view.layer.insertSublayer(cameraService.previewLayer, at: 0)
    }

    private func setupOverlay() {
        resultView.previewLayer = cameraService.previewLayer
        resultView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultView)
        NSLayoutConstraint.activate([
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultView.topAnchor.constraint(equalTo: view.topAnchor),
            resultView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupStatus() {
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.layer.cornerRadius = 8
        statusContainer.clipsToBounds = true
        view.addSubview(statusContainer)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 2
        statusLabel.textColor = .white
        statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        statusContainer.contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            statusContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            statusContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            statusLabel.leadingAnchor.constraint(equalTo: statusContainer.contentView.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.contentView.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.contentView.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.contentView.bottomAnchor, constant: -10),
        ])
    }

    private func updateCameraOrientation() {
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        cameraService.updateOrientation(interfaceOrientation)
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard pipeline != nil else { return }

        if inferenceBusy {
            pendingFrame = (pixelBuffer, timestamp)
            return
        }

        runInference(pixelBuffer: pixelBuffer, timestamp: timestamp)
    }

    private func runInference(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let pipeline else { return }

        inferenceBusy = true
        inferenceQueue.async { [weak self] in
            guard let self else { return }

            do {
                let result = try pipeline.detect(pixelBuffer: pixelBuffer, timestamp: timestamp)
                self.stateQueue.async {
                    let fps = self.recordFrameAndReturnFPS()
                    self.inferenceBusy = false
                    let nextFrame = self.pendingFrame
                    self.pendingFrame = nil

                    DispatchQueue.main.async {
                        self.statusLabel.text = self.statusText(result: result, fps: fps)
                        self.resultView.update(image: nil, detections: result.detections)
                    }

                    if let nextFrame {
                        self.runInference(pixelBuffer: nextFrame.pixelBuffer, timestamp: nextFrame.timestamp)
                    }
                }
            } catch {
                self.stateQueue.async {
                    self.inferenceBusy = false
                    let nextFrame = self.pendingFrame
                    self.pendingFrame = nil

                    DispatchQueue.main.async {
                        self.statusLabel.text = "Live detection failed: \(error)"
                    }

                    if let nextFrame {
                        self.runInference(pixelBuffer: nextFrame.pixelBuffer, timestamp: nextFrame.timestamp)
                    }
                }
            }
        }
    }

    private func recordFrameAndReturnFPS() -> Double {
        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - fpsWindowStart

        if elapsed >= 1.0 {
            currentFPS = Double(fpsFrameCount) / elapsed
            fpsFrameCount = 0
            fpsWindowStart = now
        }

        return currentFPS
    }

    private func statusText(result: DetectionRunResult, fps: Double) -> String {
        let input = "\(result.inputShape[3])x\(result.inputShape[2])"
        return "Live: \(result.detections.count) detections | \(String(format: "%.1f", fps)) FPS | \(String(format: "%.1f", result.inferenceTimeMs)) ms | input \(input)"
    }
}

extension LiveDetectionViewController: CameraServiceDelegate {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        stateQueue.async { [weak self] in
            self?.handleFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    func cameraService(_ service: CameraService, didUpdateStatus status: String) {
        statusLabel.text = "Camera: \(status)"
    }
}
