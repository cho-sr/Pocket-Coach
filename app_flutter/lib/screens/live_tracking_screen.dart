import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../detection/detector_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_feed.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/status_chip.dart';

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final _bridge = const DetectorBridge();
  bool _recording = true;
  bool _locked = true;
  DetectorStatus _detectorStatus = DetectorStatus.unavailable();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startNativeSession();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _startNativeSession() async {
    final status = await _bridge.startLiveSession();
    if (mounted) {
      setState(() => _detectorStatus = status);
    }
  }

  Future<void> _endSession() async {
    await _bridge.stopLiveSession();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleLock() async {
    await _bridge.lockTarget();
    setState(() => _locked = !_locked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          const Positioned.fill(
            child: CameraFeed(),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.26),
              ),
            ),
          ),
          const Positioned.fill(child: DetectionOverlay()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 480;
                return Stack(
                  children: [
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 8,
                      child: _LiveTopBar(
                        detectorStatus: _detectorStatus,
                        onBack: _endSession,
                      ),
                    ),
                    Positioned(
                      right: 16,
                      top: compact ? 86 : constraints.maxHeight * 0.36,
                      child: Transform.scale(
                        scale: compact ? 0.82 : 1.0,
                        alignment: Alignment.topRight,
                        child: _AnglePanel(locked: _locked),
                      ),
                    ),
                    Positioned(
                      left: compact ? 132 : 24,
                      right: compact ? 132 : 24,
                      bottom: 12,
                      child: _SessionControls(
                        compact: compact,
                        recording: _recording,
                        locked: _locked,
                        detectorStatus: _detectorStatus,
                        onToggleRecording: () {
                          setState(() => _recording = !_recording);
                        },
                        onLockTarget: _toggleLock,
                        onEndSession: _endSession,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveTopBar extends StatelessWidget {
  const _LiveTopBar({
    required this.detectorStatus,
    required this.onBack,
  });

  final DetectorStatus detectorStatus;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LiveHeader(onBack: onBack),
        const SizedBox(width: 14),
        const StatusChip(
          label: 'REC 04:12',
          color: AppColors.red,
          showDot: true,
        ),
        const Spacer(),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: StatusChip(
              label: detectorStatus.shortLabel,
              icon: Icons.monitor_heart_rounded,
              color: detectorStatus.modelReady
                  ? AppColors.accent
                  : AppColors.warning,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: StatusChip(
              label: detectorStatus.modelReady ? 'NPU ON' : 'NPU WAIT',
              icon: Icons.flash_on_rounded,
              color: AppColors.warning,
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 34,
          tooltip: 'Back',
        ),
        const SizedBox(width: 4),
        Text(
          'Live Tracking',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }
}

class _AnglePanel extends StatelessWidget {
  const _AnglePanel({required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppSurface(
          color: AppColors.surfaceSoft.withValues(alpha: 0.78),
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const Icon(Icons.near_me_outlined,
                  color: AppColors.accent, size: 34),
              const SizedBox(height: 8),
              Text(
                'ANGLE',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
              Text(
                '+12 deg',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        StatusChip(
          label: locked ? 'LOCKED' : 'SCAN',
          color: locked ? AppColors.green : AppColors.warning,
          showDot: true,
        ),
      ],
    );
  }
}

class _SessionControls extends StatelessWidget {
  const _SessionControls({
    required this.compact,
    required this.recording,
    required this.locked,
    required this.detectorStatus,
    required this.onToggleRecording,
    required this.onLockTarget,
    required this.onEndSession,
  });

  final bool compact;
  final bool recording;
  final bool locked;
  final DetectorStatus detectorStatus;
  final VoidCallback onToggleRecording;
  final VoidCallback onLockTarget;
  final VoidCallback onEndSession;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      color: Colors.black.withValues(alpha: 0.86),
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
          : const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _PanelButton(
                  icon: Icons.track_changes_rounded,
                  label: locked ? 'Lock Target' : 'Find Target',
                  onTap: onLockTarget,
                  height: compact ? 46 : 64,
                ),
              ),
              const SizedBox(width: 12),
              _EndButton(onTap: onEndSession, size: compact ? 56 : 72),
              const SizedBox(width: 12),
              Expanded(
                child: _PanelButton(
                  icon: recording
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  label: recording ? 'Recording' : 'Paused',
                  onTap: onToggleRecording,
                  iconColor: AppColors.red,
                  height: compact ? 46 : 64,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 11),
            Text(
              'END SESSION',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.muted,
                    fontSize: 10,
                  ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: _InlineStatus(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Camera Connected',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InlineStatus(
                    icon: Icons.monitor_heart_rounded,
                    label: detectorStatus.modelReady
                        ? 'Model: Warm'
                        : 'Model: Waiting',
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.onTap, required this.size});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withValues(alpha: 0.45),
              blurRadius: 24,
            ),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.stop_rounded,
            size: size * 0.48,
            color: AppColors.black,
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.height,
    this.iconColor = AppColors.text,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double height;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: iconColor),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.icon,
    required this.label,
    this.color = AppColors.text,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  fontSize: 12,
                ),
          ),
        ),
      ],
    );
  }
}
