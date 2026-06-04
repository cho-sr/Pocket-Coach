import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../detection/detector_bridge.dart';
import '../models/mock_data.dart';
import '../widgets/app_bottom_nav.dart';
import 'camera_screen.dart';
import 'home_screen.dart';
import 'recent_videos_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  final bool _trackingBusy = false;
  final DetectorStatus _detectorStatus = DetectorStatus.unavailable();
  final List<TrackingSession> _recordedSessions = [];

  void _setTab(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _addRecording(XFile file, Duration duration) async {
    final recordedAt = DateTime.now();
    final directory = await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory('${directory.path}/recordings');
    if (!await recordingsDirectory.exists()) {
      await recordingsDirectory.create(recursive: true);
    }

    final fileName = 'recording_${recordedAt.millisecondsSinceEpoch}.mp4';
    final savedPath = '${recordingsDirectory.path}/$fileName';
    await File(file.path).copy(savedPath);

    if (!mounted) return;

    setState(() {
      _recordedSessions.insert(
        0,
        TrackingSession(
          title: 'Match Recording ${_recordedSessions.length + 1}',
          recordedAt: recordedAt,
          duration: _formatDuration(duration),
          asset: 'assets/images/soccer_hero.png',
          videoPath: savedPath,
        ),
      );
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onStartTracking: () => _setTab(1),
        onOpenRecords: () => _setTab(2),
        onOpenCamera: () => _setTab(1),
        trackingBusy: _trackingBusy,
        detectorStatus: _detectorStatus,
      ),
      CameraScreen(
        onRecordingComplete: _addRecording,
        trackingBusy: _trackingBusy,
      ),
      RecentVideosScreen(
        onBack: () => _setTab(0),
        sessions: _recordedSessions,
      ),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onChanged: _setTab,
      ),
    );
  }
}
