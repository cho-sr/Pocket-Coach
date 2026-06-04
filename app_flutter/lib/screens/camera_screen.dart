import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/camera_feed.dart';
import '../widgets/status_chip.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.onRecordingComplete,
    required this.trackingBusy,
  });

  final void Function(XFile file, Duration duration) onRecordingComplete;
  final bool trackingBusy;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _recording = false;
  bool _recordingBusy = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (_recordingBusy ||
        controller == null ||
        !controller.value.isInitialized) {
      if (mounted && controller == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera is still starting'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _recordingBusy = true);
    try {
      if (_recording) {
        final file = await controller.stopVideoRecording();
        final duration = _recordingStartedAt == null
            ? Duration.zero
            : DateTime.now().difference(_recordingStartedAt!);
        _recordingTimer?.cancel();
        _recordingStartedAt = null;
        widget.onRecordingComplete(file, duration);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording saved to Records'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        await controller.startVideoRecording();
        _recordingStartedAt = DateTime.now();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && _recording) {
            setState(() {});
          }
        });
      }

      if (mounted) {
        setState(() => _recording = !_recording);
      }
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.description == null
                  ? 'Recording failed'
                  : 'Recording failed: ${error.description}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _recordingBusy = false);
      }
    }
  }

  String get _recordingLabel {
    if (!_recording || _recordingStartedAt == null) return 'Ready';
    final elapsed = DateTime.now().difference(_recordingStartedAt!);
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'REC $minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _recording ? 'Recording' : 'Camera',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusChip(
                  label: _recordingLabel,
                  icon: _recording ? null : Icons.photo_camera_outlined,
                  color: _recording ? AppColors.red : AppColors.accent,
                  showDot: _recording,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CameraFeed(
                        onControllerReady: (controller) {
                          _controller = controller;
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: StatusChip(
                        label: _recording
                            ? 'Recording Video'
                            : 'Camera Feed Online',
                        color: _recording ? AppColors.red : AppColors.green,
                        showDot: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton.icon(
                onPressed: widget.trackingBusy || _recordingBusy
                    ? null
                    : _toggleRecording,
                icon: widget.trackingBusy || _recordingBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        _recording
                            ? Icons.stop_rounded
                            : Icons.radio_button_checked_rounded,
                      ),
                label: Text(
                  widget.trackingBusy
                      ? 'Starting Model'
                      : _recordingBusy
                          ? 'Saving'
                          : _recording
                              ? 'Stop Recording'
                              : 'Start Tracking',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _recording ? AppColors.red : AppColors.accent,
                  foregroundColor: AppColors.black,
                  disabledBackgroundColor: AppColors.accentSoft,
                  disabledForegroundColor: AppColors.text,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
