import 'package:flutter/material.dart';

import '../detection/detector_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_feed.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/status_chip.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({
    super.key,
    required this.onStartTracking,
    required this.trackingBusy,
    required this.detectorStatus,
  });

  final VoidCallback onStartTracking;
  final bool trackingBusy;
  final DetectorStatus detectorStatus;

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
                    'Camera',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const StatusChip(
                  label: 'Preview',
                  icon: Icons.photo_camera_outlined,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: CameraFeed(),
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
                    const Positioned.fill(child: DetectionOverlay()),
                    const Positioned(
                      left: 14,
                      top: 14,
                      child: StatusChip(
                        label: 'Camera Feed Online',
                        color: AppColors.green,
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
                onPressed: trackingBusy ? null : onStartTracking,
                icon: trackingBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  trackingBusy
                      ? 'Starting Model'
                      : detectorStatus.modelReady
                          ? 'Run Model Again'
                          : 'Start Tracking',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
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
