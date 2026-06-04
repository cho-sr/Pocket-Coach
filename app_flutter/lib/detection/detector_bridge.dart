import 'package:flutter/services.dart';

class DetectorStatus {
  const DetectorStatus({
    required this.ok,
    required this.nativeAvailable,
    required this.status,
    this.modelPresent = false,
    this.metadataPresent = false,
    this.backend,
    this.inferenceMs,
    this.outputCount,
    this.modelSizeBytes,
    this.error,
  });

  final bool ok;
  final bool nativeAvailable;
  final String status;
  final bool modelPresent;
  final bool metadataPresent;
  final String? backend;
  final double? inferenceMs;
  final int? outputCount;
  final int? modelSizeBytes;
  final String? error;

  bool get modelReady => nativeAvailable && modelPresent;

  String get shortLabel {
    if (!nativeAvailable) return 'Native: OFF';
    if (!modelPresent) return 'Model: Missing';
    if (inferenceMs != null) return '${inferenceMs!.toStringAsFixed(1)} ms';
    return 'Model: Ready';
  }

  factory DetectorStatus.fromMap(Map<Object?, Object?> map) {
    return DetectorStatus(
      ok: map['ok'] == true,
      nativeAvailable: true,
      status: (map['status'] as String?) ?? 'ready',
      modelPresent: map['modelPresent'] == true,
      metadataPresent: map['metadataPresent'] == true,
      backend: map['backend'] as String?,
      inferenceMs: (map['inferenceMs'] as num?)?.toDouble(),
      outputCount: (map['outputCount'] as num?)?.toInt(),
      modelSizeBytes: (map['modelSizeBytes'] as num?)?.toInt(),
    );
  }

  factory DetectorStatus.unavailable([String? error]) {
    return DetectorStatus(
      ok: false,
      nativeAvailable: false,
      status: 'native_unavailable',
      error: error,
    );
  }
}

class DetectorBridge {
  const DetectorBridge();

  static const MethodChannel _channel = MethodChannel('pocket_coach/detector');

  Future<DetectorStatus> startLiveSession() => _invoke('startLiveSession');
  Future<DetectorStatus> stopLiveSession() => _invoke('stopLiveSession');
  Future<DetectorStatus> lockTarget() => _invoke('lockTarget');
  Future<DetectorStatus> getDetectorStatus() => _invoke('getDetectorStatus');

  Future<DetectorStatus> _invoke(String method) async {
    try {
      final payload = await _channel.invokeMethod<Object?>(method);
      if (payload is Map<Object?, Object?>) {
        return DetectorStatus.fromMap(payload);
      }
      return const DetectorStatus(
        ok: true,
        nativeAvailable: true,
        status: 'ok',
      );
    } on MissingPluginException {
      return DetectorStatus.unavailable('Missing native detector plugin');
    } on PlatformException catch (error) {
      return DetectorStatus.unavailable(error.message ?? error.code);
    }
  }
}
