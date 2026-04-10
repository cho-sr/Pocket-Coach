import AVFoundation
import UIKit

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func cameraService(_ service: CameraService, didUpdateStatus status: String)
}

extension CameraServiceDelegate {
    func cameraService(_ service: CameraService, didUpdateStatus status: String) {}
}

final class CameraService: NSObject {
    private enum SetupState {
        case idle
        case requestingAuthorization
        case configured
        case unauthorized
        case failed
    }

    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()

    weak var delegate: CameraServiceDelegate?

    private let sessionQueue = DispatchQueue(label: "app.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "app.camera.output", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var setupState: SetupState = .idle
    private var shouldStartWhenReady = false

    override init() {
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        registerForSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureSession() {
        sessionQueue.async {
            self.configureSessionIfNeeded()
        }
    }

    func updateOrientation(_ orientation: UIInterfaceOrientation) {
        guard let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: orientation) else {
            return
        }

        sessionQueue.async {
            self.applyVideoOrientation(videoOrientation)
        }
    }

    func start() {
        sessionQueue.async {
            self.shouldStartWhenReady = true

            switch self.setupState {
            case .idle:
                self.configureSessionIfNeeded()
            case .configured:
                self.startRunningIfPossible()
            case .requestingAuthorization, .unauthorized, .failed:
                break
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.shouldStartWhenReady = false
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            self.publishStatus("Camera stopped")
        }
    }

    private func configureSessionIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            guard setupState != .configured else {
                if shouldStartWhenReady {
                    startRunningIfPossible()
                }
                return
            }
            performSessionConfiguration()

        case .notDetermined:
            guard setupState != .requestingAuthorization else { return }
            setupState = .requestingAuthorization
            publishStatus("Requesting camera permission")

            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.sessionQueue.async {
                    if granted {
                        self.performSessionConfiguration()
                    } else {
                        self.setupState = .unauthorized
                        self.publishStatus("Camera permission denied")
                    }
                }
            }

        case .denied, .restricted:
            setupState = .unauthorized
            publishStatus("Camera permission unavailable")

        @unknown default:
            setupState = .failed
            publishStatus("Unknown camera authorization state")
        }
    }

    private func performSessionConfiguration() {
        session.beginConfiguration()

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else {
            session.commitConfiguration()
            setupState = .failed
            publishStatus("Back camera unavailable")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                setupState = .failed
                publishStatus("Unable to add camera input")
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            setupState = .failed
            publishStatus("Failed to create camera input: \(error.localizedDescription)")
            return
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            setupState = .failed
            publishStatus("Unable to add video output")
            return
        }

        session.addOutput(videoOutput)
        applyVideoOrientation(.portrait)
        session.commitConfiguration()

        setupState = .configured
        publishStatus("Camera configured")

        if shouldStartWhenReady {
            startRunningIfPossible()
        }
    }

    private func startRunningIfPossible() {
        guard setupState == .configured else { return }
        guard !session.isRunning else { return }
        guard !session.isInterrupted else {
            publishStatus("Camera interrupted")
            return
        }

        session.startRunning()
        publishStatus("Camera running")
    }

    private func applyVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        if let previewConnection = previewLayer.connection, previewConnection.isVideoOrientationSupported {
            previewConnection.videoOrientation = orientation
        }

        if let outputConnection = videoOutput.connection(with: .video), outputConnection.isVideoOrientationSupported {
            outputConnection.videoOrientation = orientation
        }
    }

    private func registerForSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    @objc
    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let status = "Camera runtime error: \(error?.localizedDescription ?? "unknown")"

        sessionQueue.async {
            self.publishStatus(status)
            if self.shouldStartWhenReady, self.setupState == .configured, !self.session.isRunning {
                self.startRunningIfPossible()
            }
        }
    }

    @objc
    private func handleSessionInterrupted(_ notification: Notification) {
        let reasonKey = AVCaptureSessionInterruptionReasonKey as String
        let reasonValue = notification.userInfo?[reasonKey] as? NSNumber
        let status = "Camera interrupted\(reasonValue.map { " (\($0.intValue))" } ?? "")"

        sessionQueue.async {
            self.publishStatus(status)
        }
    }

    @objc
    private func handleSessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async {
            self.publishStatus("Camera interruption ended")
            if self.shouldStartWhenReady {
                self.startRunningIfPossible()
            }
        }
    }

    private func publishStatus(_ status: String) {
        print(status)
        DispatchQueue.main.async {
            self.delegate?.cameraService(self, didUpdateStatus: status)
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.cameraService(self, didOutput: pixelBuffer, timestamp: timestamp)
    }
}

private extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeRight
        case .landscapeRight:
            self = .landscapeLeft
        default:
            return nil
        }
    }
}
