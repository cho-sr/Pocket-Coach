import 'package:flutter/material.dart';

import '../models/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class RecentVideosScreen extends StatefulWidget {
  const RecentVideosScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<RecentVideosScreen> createState() => _RecentVideosScreenState();
}

class _RecentVideosScreenState extends State<RecentVideosScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(title: 'Recent Videos', onBack: widget.onBack),
            const SizedBox(height: 28),
            Text('Recent Videos',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Review your latest tracking sessions and metrics.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.muted,
                  ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _SegmentedControl(
                  selected: _segment,
                  onChanged: (value) => setState(() => _segment = value),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: const Text('Filter'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: 'Latest Records',
              trailing: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    '${trackingSessions.length} Sessions',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.accent,
                          fontSize: 10,
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final session in trackingSessions) ...[
              _RecordCard(session: session),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceHigh,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.monitor_heart_rounded,
                        color: AppColors.muted.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'End of recorded tracking sessions.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
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

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SizedBox(
        width: 200,
        height: 38,
        child: Row(
          children: [
            _SegmentButton(
              label: 'All',
              selected: selected == 0,
              onTap: () => onChanged(0),
            ),
            _SegmentButton(
              label: 'Recent',
              selected: selected == 1,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? AppColors.black : AppColors.muted,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.session});

  final TrackingSession session;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      color: AppColors.surfaceHigh,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 100,
              height: 92,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(session.asset, fit: BoxFit.cover),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.play_arrow_rounded,
                            color: AppColors.black),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.76),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        child: Text(
                          session.duration,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: 10,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.muted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        session.date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: AppColors.border, height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        icon: Icons.flash_on_rounded,
                        label: 'AVG FPS',
                        value: session.avgFps,
                        color: AppColors.accent,
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        icon: Icons.track_changes_rounded,
                        label: 'LOST',
                        value: session.lost,
                        color: AppColors.red,
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        icon: Icons.monitor_heart_rounded,
                        label: 'STABILITY',
                        value: session.stability,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.muted,
                      fontSize: 9,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
