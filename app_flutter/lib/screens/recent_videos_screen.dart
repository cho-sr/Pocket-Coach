import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class RecentVideosScreen extends StatefulWidget {
  const RecentVideosScreen({
    super.key,
    required this.onBack,
    required this.sessions,
  });

  final VoidCallback onBack;
  final List<TrackingSession> sessions;

  @override
  State<RecentVideosScreen> createState() => _RecentVideosScreenState();
}

class _RecentVideosScreenState extends State<RecentVideosScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final sessions = _segment == 0
        ? widget.sessions
        : widget.sessions
            .where(
              (session) =>
                  DateTime.now().difference(session.recordedAt).inDays <= 7,
            )
            .toList();

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
              'Review your latest camera recordings.',
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
                    '${sessions.length} Sessions',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.accent,
                          fontSize: 10,
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty) ...[
              Text(
                'No saved videos.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.dim,
                      fontSize: 12,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            for (final session in sessions) ...[
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
                    sessions.isEmpty
                        ? 'No saved videos.'
                        : 'End of recorded sessions.',
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

String _formatRecordedAt(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} - $hour:$minute';
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
    return InkWell(
      onTap: session.videoPath == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoPlaybackScreen(session: session),
                ),
              );
            },
      borderRadius: BorderRadius.circular(8),
      child: AppSurface(
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
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
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
                          _formatRecordedAt(session.recordedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const StatusPill(label: 'Saved Recording'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({super.key, required this.session});

  final TrackingSession session;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    final path = widget.session.videoPath;
    if (path == null || !File(path).existsSync()) {
      setState(() => _error = 'Video file not found');
      return;
    }

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _error = 'Unable to play this video');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(widget.session.title),
        backgroundColor: AppColors.black,
      ),
      body: Center(
        child: _error != null
            ? Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
              )
            : controller == null || !controller.value.isInitialized
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(controller),
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: AppColors.accent,
                            bufferedColor: AppColors.muted,
                          ),
                        ),
                        Center(
                          child: IconButton.filled(
                            onPressed: () {
                              setState(() {
                                controller.value.isPlaying
                                    ? controller.pause()
                                    : controller.play();
                              });
                            },
                            icon: Icon(
                              controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.muted,
                  fontSize: 10,
                ),
          ),
        ),
      ),
    );
  }
}
