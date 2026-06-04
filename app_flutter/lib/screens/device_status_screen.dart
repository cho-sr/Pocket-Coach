import 'package:flutter/material.dart';

import '../detection/detector_bridge.dart';
import '../models/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class DeviceStatusScreen extends StatelessWidget {
  const DeviceStatusScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    const bridge = DetectorBridge();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(title: 'Device Status', onBack: onBack),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Connection Status',
              trailing: Icon(Icons.monitor_heart_rounded,
                  color: AppColors.accent, size: 20),
            ),
            const SizedBox(height: 12),
            for (final device in deviceConnections) ...[
              _ConnectionCard(device: device),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 16),
            const SectionHeader(title: 'Mechanical Calibration'),
            const SizedBox(height: 12),
            const _TelemetryPanel(),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton(
                onPressed: bridge.runCalibration,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Run Calibration'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: OutlinedButton(
                onPressed: bridge.servoTest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.text),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Servo Test'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'Perform calibration before every match to keep target centering accurate.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.dim,
                      fontSize: 12,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 34,
        ),
        const SizedBox(width: 4),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.device});

  final DeviceConnection device;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
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
              width: 44,
              height: 44,
              child: Icon(device.icon, color: AppColors.accent),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  device.detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                device.status.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.text,
                      fontSize: 10,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryPanel extends StatelessWidget {
  const _TelemetryPanel();

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      color: AppColors.surfaceSoft,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Real-time Telemetry',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'OPTIMAL',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.accent,
                          fontSize: 10,
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < telemetryLines.length; i++) ...[
            _TelemetryRow(line: telemetryLines[i]),
            if (i != telemetryLines.length - 1)
              const Divider(color: AppColors.border, height: 22),
          ],
        ],
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({required this.line});

  final TelemetryLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(line.icon, size: 19, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            line.label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.muted,
                ),
          ),
        ),
        Text(
          line.value.toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
