import AVFoundation
import CoreMIDI
import UIKit

final class DetectionViewController: UIViewController {
    private let tuning = TrackingTuning()
    private let modelInputSize = 640
    private let cameraService = CameraService()
    private lazy var preprocessor = FramePreprocessor(inputWidth: modelInputSize, inputHeight: modelInputSize)
    private let postProcessor = DetectionPostProcessor(confidenceThreshold: 0.40, classNames: ["person"], rawModelClassCount: 80, sourceClassMap: [0: 0])
    private let tracker = SimpleTracker()
    private let overlayView = OverlayView()
    private let targetSelection = TargetSelectionController()
    private lazy var deadzoneController = DeadzoneCommandController(tuning: tuning)
    private let inferenceQueue = DispatchQueue(label: "app.detector.inference", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "app.detector.state")

    private var detector: ExecuTorchRunner?
    private var frameIndex: Int = 0
    private var detectionInterval: Int = 1
    private var inferenceBusy: Bool = false
    private var latestTracks: [TrackResult] = []
    private var midiOutput: USBMIDIServoOutput?
    private var midiStatusText: String = "MIDI: searching..."
    private var commandText: String = "Command: idle"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        cameraService.delegate = self
        cameraService.configureSession()

        cameraService.previewLayer.frame = view.bounds
        view.layer.addSublayer(cameraService.previewLayer)

        overlayView.frame = view.bounds
        overlayView.previewLayer = cameraService.previewLayer
        view.addSubview(overlayView)
        setupTapHandling()

        do {
            detector = try ExecuTorchRunner(modelName: "detector")
        } catch {
            commandText = "Model load failed"
            print("Failed to load ExecuTorch model: \(error)")
        }

        stateQueue.async { [weak self] in
            self?.setupMIDIOutput()
            self?.publishOverlay(resolvedSelection: nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCameraOrientation()
        cameraService.start()
        stateQueue.async { [weak self] in
            self?.refreshMIDIDestination()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraService.stop()
        stateQueue.async { [weak self] in
            self?.stopMotorIfNeeded(reason: "View hidden")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraService.previewLayer.frame = view.bounds
        overlayView.frame = view.bounds
        updateCameraOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.cameraService.previewLayer.frame = self.view.bounds
            self.overlayView.frame = self.view.bounds
            self.updateCameraOrientation()
        })
    }

    private func updateCameraOrientation() {
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        cameraService.updateOrientation(interfaceOrientation)
    }

    private func setupTapHandling() {
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapRecognizer)
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: view)
        let normalizedPoint = normalizedPoint(fromViewPoint: location)

        stateQueue.async { [weak self] in
            guard let self else { return }

            _ = self.targetSelection.select(at: normalizedPoint, visibleTracks: self.latestTracks)
            if let stopCommand = self.deadzoneController.forceStop() {
                self.sendServoCommand(stopCommand)
            }

            let resolvedSelection = self.targetSelection.resolveSelectedTrack(from: self.latestTracks)
            self.publishOverlay(resolvedSelection: resolvedSelection)
        }
    }

    private func normalizedPoint(fromViewPoint point: CGPoint) -> CGPoint {
        let tapRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        let normalizedRect = cameraService.previewLayer.metadataOutputRectConverted(fromLayerRect: tapRect)
        return CGPoint(x: normalizedRect.midX, y: normalizedRect.midY)
    }

    private func setupMIDIOutput() {
        do {
            midiOutput = try USBMIDIServoOutput(tuning: tuning)
            refreshMIDIDestination()
        } catch {
            midiStatusText = "MIDI: init failed"
            print("Failed to create MIDI output: \(error)")
        }
    }

    private func refreshMIDIDestination() {
        guard let midiOutput else {
            midiStatusText = "MIDI: unavailable"
            return
        }

        _ = midiOutput.connect(preferredNameFragment: tuning.preferredMIDIDeviceName)
        midiStatusText = midiOutput.statusText(preferredNameFragment: tuning.preferredMIDIDeviceName)
    }

    private func stopMotorIfNeeded(reason: String) {
        if let stopCommand = deadzoneController.forceStop() {
            sendServoCommand(stopCommand)
        }
        commandText = "Command: \(reason)"
        publishOverlay(resolvedSelection: nil)
    }

    private func processTracks(_ tracks: [TrackResult], now: TimeInterval) {
        latestTracks = tracks
        let resolvedSelection = targetSelection.resolveSelectedTrack(from: tracks)
        let confirmedSelection = resolvedSelection.flatMap { track in
            track.isPredictionOnly ? nil : track
        }

        if targetSelection.hasSelection && targetSelection.lostFrames >= tuning.lostTargetStopFrames {
            if let stopCommand = deadzoneController.forceStop(now: now) {
                sendServoCommand(stopCommand)
            }
            targetSelection.clearSelection()
            publishOverlay(resolvedSelection: nil)
            return
        }

        if let command = deadzoneController.update(selectedTrack: confirmedSelection, now: now) {
            sendServoCommand(command)
        }

        publishOverlay(resolvedSelection: resolvedSelection)
    }

    private func sendServoCommand(_ command: ServoCommand) {
        guard let midiOutput else {
            midiStatusText = "MIDI: unavailable"
            commandText = "Command blocked: \(command.direction.displayName)"
            return
        }

        if midiOutput.connectedDestinationName == nil {
            refreshMIDIDestination()
        }

        do {
            try midiOutput.send(direction: command.direction, strength: command.strength)
            midiStatusText = midiOutput.statusText(preferredNameFragment: tuning.preferredMIDIDeviceName)
            if command.direction == .stop {
                commandText = "Command: STOP"
            } else {
                commandText = "Command: \(command.direction.displayName) @ \(command.strength)"
            }
        } catch {
            refreshMIDIDestination()
            commandText = "Command error: \(command.direction.displayName)"
            print("Failed to send MIDI command: \(error)")
        }
    }

    private func publishOverlay(resolvedSelection: TrackResult?) {
        let selectionStatusText: String
        if let selectedTrackID = targetSelection.selectedTrackID {
            if targetSelection.lostFrames > 0 {
                selectionStatusText = "Target #\(selectedTrackID) lost \(targetSelection.lostFrames)/\(tuning.lostTargetStopFrames)"
            } else {
                selectionStatusText = "Target #\(selectedTrackID) locked"
            }
        } else {
            selectionStatusText = "Tap a player to select"
        }

        let selectionGhostRect: CGRect?
        if resolvedSelection == nil, targetSelection.hasSelection {
            selectionGhostRect = targetSelection.lastConfirmedRect
        } else {
            selectionGhostRect = nil
        }

        DispatchQueue.main.async {
            self.overlayView.update(
                tracks: self.latestTracks,
                selectedTrackID: self.targetSelection.selectedTrackID,
                selectionGhostRect: selectionGhostRect,
                deadzoneRange: self.deadzoneController.deadzoneRange(),
                midiStatusText: self.midiStatusText,
                commandText: self.commandText,
                selectionStatusText: selectionStatusText
            )
        }
    }
}

extension DetectionViewController: CameraServiceDelegate {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        stateQueue.async { [weak self] in
            self?.handleFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        frameIndex += 1
        let now = CMTimeGetSeconds(timestamp).isFinite ? CMTimeGetSeconds(timestamp) : CFAbsoluteTimeGetCurrent()

        let shouldRunDetection = frameIndex % detectionInterval == 0

        // If this is not a detection frame, or the previous inference is still running,
        // keep IDs alive by advancing the tracker only.
        guard shouldRunDetection, !inferenceBusy, let detector else {
            let predictedTracks = tracker.predictOnly()
            processTracks(predictedTracks, now: now)
            return
        }

        inferenceBusy = true

        // CVPixelBuffer is a Core Foundation object, so closure capture retains it.
        inferenceQueue.async { [weak self] in
            guard let self else { return }

            guard let framePacket = self.preprocessor.prepare(pixelBuffer: pixelBuffer, timestamp: timestamp) else {
                self.stateQueue.async {
                    self.inferenceBusy = false
                }
                return
            }

            do {
                let rawOutput = try detector.predict(
                    input: framePacket.tensorData,
                    shape: framePacket.inputShape
                )
                let detections = self.postProcessor.parse(
                    rawOutput: rawOutput,
                    inputWidth: CGFloat(framePacket.inputShape[3]),
                    inputHeight: CGFloat(framePacket.inputShape[2])
                )

                self.stateQueue.async {
                    let tracks = self.tracker.update(detections: detections)
                    self.inferenceBusy = false
                    self.processTracks(tracks, now: now)
                }
            } catch {
                self.stateQueue.async {
                    self.inferenceBusy = false
                    print("ExecuTorch inference failed: \(error)")
                }
            }
        }
    }
}
