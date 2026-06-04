import ExecuTorch
import Flutter
import Foundation
import QuartzCore

enum NativeDetectorError: Error {
  case modelNotFound
  case invalidOutput
}

final class NativeDetectorBridge: NSObject {
  private let queue = DispatchQueue(label: "app.pocketcoach.detector", qos: .userInitiated)
  private var runner: NativeExecuTorchRunner?

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = NativeDetectorBridge()
    let channel = FlutterMethodChannel(
      name: "pocket_coach/detector",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      bridge.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startLiveSession":
      warmup(result: result)
    case "stopLiveSession":
      result(["ok": true, "status": "stopped"])
    case "lockTarget":
      result(["ok": true, "status": "lock_toggled"])
    case "runCalibration":
      result(["ok": true, "status": "calibration_stub"])
    case "servoTest":
      result(["ok": true, "status": "servo_test_stub"])
    case "getDetectorStatus":
      result(statusPayload())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func warmup(result: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }

      do {
        let runner = try self.getRunner()
        let inputShape = [1, 3, 576, 1024]
        let inputCount = inputShape.reduce(1, *)
        let input = [Float](repeating: 0.0, count: inputCount)
        let start = CACurrentMediaTime()
        let output = try runner.predict(input: input, shape: inputShape)
        let inferenceMs = (CACurrentMediaTime() - start) * 1000.0

        var payload = self.statusPayload()
        payload["ok"] = true
        payload["status"] = "model_warm"
        payload["inputShape"] = inputShape
        payload["inputCount"] = inputCount
        payload["outputCount"] = output.count
        payload["inferenceMs"] = inferenceMs

        DispatchQueue.main.async {
          result(payload)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "detector_warmup_failed",
              message: "\(error)",
              details: self.statusPayload()
            )
          )
        }
      }
    }
  }

  private func getRunner() throws -> NativeExecuTorchRunner {
    if let runner {
      return runner
    }

    let runner = try NativeExecuTorchRunner(modelName: "detector", fileExtension: "pte")
    self.runner = runner
    return runner
  }

  private func statusPayload() -> [String: Any] {
    let modelPath = Bundle.main.path(forResource: "detector", ofType: "pte")
    let metadataPath = Bundle.main.path(forResource: "metadata", ofType: "yaml")
    let modelSizeBytes = modelPath.flatMap { path in
      try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
    }

    return [
      "modelPresent": modelPath != nil,
      "metadataPresent": metadataPath != nil,
      "modelPath": modelPath ?? NSNull(),
      "metadataPath": metadataPath ?? NSNull(),
      "modelSizeBytes": modelSizeBytes?.intValue ?? 0,
      "backend": "executorch_coreml",
      "inputShape": [1, 3, 576, 1024],
    ]
  }
}

final class NativeExecuTorchRunner {
  private let module: Module

  init(modelName: String, fileExtension: String) throws {
    guard let modelPath = Bundle.main.path(forResource: modelName, ofType: fileExtension) else {
      throw NativeDetectorError.modelNotFound
    }

    module = Module(filePath: modelPath)
    try module.load("forward")
  }

  func predict(input: [Float], shape: [Int]) throws -> [Float] {
    let inputTensor = Tensor<Float>(input, shape: shape)
    let outputs = try module.forward(inputTensor)

    guard let outputTensor: Tensor<Float> = outputs.first?.tensor() else {
      throw NativeDetectorError.invalidOutput
    }

    return outputTensor.scalars()
  }
}
