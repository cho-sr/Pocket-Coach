import 'package:flutter/material.dart';

import '../detection/detector_bridge.dart';
import '../models/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/status_chip.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onStartTracking,
    required this.onOpenDevices,
    required this.onOpenRecords,
    required this.onOpenCamera,
    required this.trackingBusy,
    required this.detectorStatus,
  });

  final VoidCallback onStartTracking;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenRecords;
  final VoidCallback onOpenCamera;
  final bool trackingBusy;
  final DetectorStatus detectorStatus;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pocket Coach',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const StatusChip(
                  label: 'System Live',
                  color: AppColors.green,
                  showDot: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _HeroPanel(
              onStartTracking: onStartTracking,
              trackingBusy: trackingBusy,
              detectorStatus: detectorStatus,
            ),
            const SizedBox(height: 24),
            const _ReadinessPanel(),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Management'),
            const SizedBox(height: 14),
            _ManagementRow(
              title: 'Device Status',
              subtitle: 'Calibrate motors & sensors',
              icon: Icons.memory_rounded,
              onTap: onOpenDevices,
            ),
            const SizedBox(height: 12),
            _ManagementRow(
              title: 'Recent Records',
              subtitle: 'Review past tracking sessions',
              icon: Icons.videocam_outlined,
              onTap: onOpenRecords,
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onOpenCamera,
              child: const _MountNotice(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.onStartTracking,
    required this.trackingBusy,
    required this.detectorStatus,
  });

  final VoidCallback onStartTracking;
  final bool trackingBusy;
  final DetectorStatus detectorStatus;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 290,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/session_01.jpg',
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.34),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    label: detectorStatus.modelReady
                        ? detectorStatus.shortLabel
                        : 'AI Performance Tracking',
                    icon: Icons.monitor_heart_rounded,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Track your player\nautomatically',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: 30,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Real-time AI servo control for stable training footage.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: trackingBusy ? null : onStartTracking,
                      icon: trackingBusy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 28),
                      label: Text(
                        trackingBusy ? 'Starting Model' : 'Start Tracking',
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
          ],
        ),
      ),
    );
  }
}

class _ReadinessPanel extends StatefulWidget {
  const _ReadinessPanel();

  @override
  State<_ReadinessPanel> createState() => _ReadinessPanelState();
}

class _ReadinessPanelState extends State<_ReadinessPanel> {
  final _bridge = const DetectorBridge();
  DetectorStatus _detectorStatus = DetectorStatus.unavailable();

  @override
  void initState() {
    super.initState();
    _loadDetectorStatus();
  }

  Future<void> _loadDetectorStatus() async {
    final status = await _bridge.getDetectorStatus();
    if (mounted) {
      setState(() => _detectorStatus = status);
    }
  }

  String get _modelStatus {
    if (!_detectorStatus.nativeAvailable) return 'Native Off';
    if (!_detectorStatus.modelPresent) return 'Missing';
    return 'Ready';
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      readinessItems[0],
      readinessItems[1],
      readinessItems[2],
      ReadinessItem(
        title: readinessItems[3].title,
        status: _modelStatus,
        icon: readinessItems[3].icon,
        wide: readinessItems[3].wide,
      ),
    ];

    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Readiness',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Diagnostics and hardware check',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.monitor_heart_rounded, color: AppColors.accent),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < items.length; i++) ...[
            if (items[i].wide)
              _ReadinessTile(item: items[i])
            else if (i == 1)
              Row(
                children: [
                  Expanded(child: _ReadinessTile(item: items[i])),
                  const SizedBox(width: 12),
                  Expanded(child: _ReadinessTile(item: items[i + 1])),
                ],
              ),
            if (i == 0 || i == 2) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ReadinessTile extends StatelessWidget {
  const _ReadinessTile({required this.item});

  final ReadinessItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.black,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(item.icon, color: AppColors.accent, size: 22),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.status,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementRow extends StatelessWidget {
  const _ManagementRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AppSurface(
        color: AppColors.surfaceHigh,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _MountNotice extends StatelessWidget {
  const _MountNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.photo_camera_outlined,
                color: AppColors.text, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Ensure your phone is mounted securely on the servo tripod for stable AI tracking.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
