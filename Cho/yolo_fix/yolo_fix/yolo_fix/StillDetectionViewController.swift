import AVFoundation
import UIKit

final class StillDetectionViewController: UIViewController {
    private let mode: DetectionMode
    private let cameraService = CameraService()
    private let resultView = DetectionResultView()
    private let statusLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let imageSelector = UISegmentedControl(items: ["test_1", "test_2", "test_3"])
    private let controlsContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let controlsStack = UIStackView()
    private let frameQueue = DispatchQueue(label: "app.yolo_fix.still.frame")
    private let inferenceQueue = DispatchQueue(label: "app.yolo_fix.still.inference", qos: .userInitiated)
    private let displayRotationAngle = CGFloat.pi

    private var pipeline: DetectorPipeline?
    private var latestPixelBuffer: CVPixelBuffer?
    private var latestTimestamp: CMTime = .invalid

    init(mode: DetectionMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        view.backgroundColor = .black

        setupPipeline()
        setupResultView()
        setupControls()

        if mode == .detect {
            setupCamera()
        } else {
            imageSelector.selectedSegmentIndex = 0
            loadSelectedTestImage(runDetection: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCameraOrientation()
        if mode == .detect {
            cameraService.start()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if mode == .detect {
            cameraService.stop()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraService.previewLayer.frame = view.bounds
        applyDisplayCompensation()
        updateCameraOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.cameraService.previewLayer.frame = self.view.bounds
            self.applyDisplayCompensation()
            self.updateCameraOrientation()
        })
    }

    private func setupPipeline() {
        do {
            pipeline = try DetectorPipeline(configuration: .highResolution1024x576)
            statusLabel.text = "\(mode.title): ready"
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
        resultView.previewLayer = cameraService.previewLayer
        applyDisplayCompensation()
    }

    private func setupResultView() {
        resultView.transform = CGAffineTransform(rotationAngle: displayRotationAngle)
        resultView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultView)
        NSLayoutConstraint.activate([
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultView.topAnchor.constraint(equalTo: view.topAnchor),
            resultView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupControls() {
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.layer.cornerRadius = 8
        controlsContainer.clipsToBounds = true
        view.addSubview(controlsContainer)

        statusLabel.numberOfLines = 2
        statusLabel.textColor = .white
        statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)

        primaryButton.setTitle(mode == .detect ? "Detect Current Frame" : "Run Test Image", for: .normal)
        primaryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        primaryButton.tintColor = .white
        primaryButton.backgroundColor = .systemBlue
        primaryButton.layer.cornerRadius = 8
        primaryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        primaryButton.addTarget(self, action: #selector(handlePrimaryButton), for: .touchUpInside)

        imageSelector.isHidden = mode != .testImage
        imageSelector.selectedSegmentTintColor = .systemBlue
        imageSelector.addTarget(self, action: #selector(handleImageSelectionChanged), for: .valueChanged)

        controlsStack.axis = .vertical
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.addArrangedSubview(statusLabel)
        controlsStack.addArrangedSubview(imageSelector)
        controlsStack.addArrangedSubview(primaryButton)
        controlsContainer.contentView.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controlsContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            controlsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            controlsStack.leadingAnchor.constraint(equalTo: controlsContainer.contentView.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: controlsContainer.contentView.trailingAnchor, constant: -12),
            controlsStack.topAnchor.constraint(equalTo: controlsContainer.contentView.topAnchor, constant: 12),
            controlsStack.bottomAnchor.constraint(equalTo: controlsContainer.contentView.bottomAnchor, constant: -12),
        ])
    }

    private func updateCameraOrientation() {
        guard mode == .detect, let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        cameraService.updateOrientation(interfaceOrientation)
    }

    private func applyDisplayCompensation() {
        guard mode == .detect else {
            resultView.transform = .identity
            return
        }

        cameraService.previewLayer.setAffineTransform(CGAffineTransform(rotationAngle: displayRotationAngle))
        resultView.transform = CGAffineTransform(rotationAngle: displayRotationAngle)
    }

    @objc
    private func handlePrimaryButton() {
        switch mode {
        case .detect:
            runCurrentFrameDetection()
        case .testImage:
            loadSelectedTestImage(runDetection: true)
        case .live:
            break
        }
    }

    @objc
    private func handleImageSelectionChanged() {
        loadSelectedTestImage(runDetection: false)
    }

    private func runCurrentFrameDetection() {
        guard let pipeline else {
            statusLabel.text = "Model is not ready"
            return
        }

        statusLabel.text = "Detecting latest camera frame..."
        frameQueue.async { [weak self] in
            guard let self else { return }
            guard let pixelBuffer = self.latestPixelBuffer else {
                DispatchQueue.main.async {
                    self.statusLabel.text = "No camera frame yet"
                }
                return
            }

            let timestamp = self.latestTimestamp
            self.inferenceQueue.async {
                do {
                    let result = try pipeline.detect(pixelBuffer: pixelBuffer, timestamp: timestamp)
                    DispatchQueue.main.async {
                        self.statusLabel.text = self.statusText(prefix: "Detect", result: result)
                        self.resultView.update(image: nil, detections: result.detections)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.statusLabel.text = "Detection failed: \(error)"
                    }
                }
            }
        }
    }

    private func loadSelectedTestImage(runDetection: Bool) {
        let index = max(imageSelector.selectedSegmentIndex, 0)
        let name = "test_\(index + 1)"

        guard let image = loadTestImage(named: name) else {
            statusLabel.text = "\(name).jpg missing"
            resultView.update(image: nil, detections: [])
            return
        }

        resultView.update(image: image, detections: [])
        statusLabel.text = runDetection ? "Detecting \(name).jpg..." : "\(name).jpg ready"

        guard runDetection else { return }
        guard let pipeline else {
            statusLabel.text = "Model is not ready"
            return
        }

        inferenceQueue.async { [weak self] in
            guard let self else { return }

            do {
                let result = try pipeline.detect(image: image)
                DispatchQueue.main.async {
                    self.statusLabel.text = self.statusText(prefix: name, result: result)
                    self.resultView.update(image: image, detections: result.detections)
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.text = "Detection failed: \(error)"
                }
            }
        }
    }

    private func loadTestImage(named name: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }

        if
            let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "test_images"),
            let image = UIImage(contentsOfFile: url.path)
        {
            return image
        }

        if
            let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
            let image = UIImage(contentsOfFile: url.path)
        {
            return image
        }

        return nil
    }

    private func statusText(prefix: String, result: DetectionRunResult) -> String {
        let input = "\(result.inputShape[3])x\(result.inputShape[2])"
        return "\(prefix): \(result.detections.count) detections | \(String(format: "%.1f", result.inferenceTimeMs)) ms | input \(input)"
    }
}

extension StillDetectionViewController: CameraServiceDelegate {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        frameQueue.async { [weak self] in
            self?.latestPixelBuffer = pixelBuffer
            self?.latestTimestamp = timestamp
        }
    }

    func cameraService(_ service: CameraService, didUpdateStatus status: String) {
        guard mode == .detect else { return }
        statusLabel.text = "Camera: \(status)"
    }
}
