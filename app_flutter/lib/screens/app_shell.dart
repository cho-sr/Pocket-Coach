import 'package:flutter/material.dart';

import '../detection/detector_bridge.dart';
import '../widgets/app_bottom_nav.dart';
import 'camera_screen.dart';
import 'device_status_screen.dart';
import 'home_screen.dart';
import 'recent_videos_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _bridge = const DetectorBridge();
  int _currentIndex = 0;
  bool _trackingBusy = false;
  DetectorStatus _detectorStatus = DetectorStatus.unavailable();

  Future<void> _startModelTracking() async {
    if (_trackingBusy) return;

    setState(() => _trackingBusy = true);
    final status = await _bridge.startLiveSession();
    if (!mounted) return;

    setState(() {
      _trackingBusy = false;
      _detectorStatus = status;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status.modelReady
              ? 'Model executed: ${status.shortLabel}'
              : status.shortLabel,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _setTab(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onStartTracking: _startModelTracking,
        onOpenDevices: () => _setTab(1),
        onOpenRecords: () => _setTab(2),
        onOpenCamera: () => _setTab(3),
        trackingBusy: _trackingBusy,
        detectorStatus: _detectorStatus,
      ),
      DeviceStatusScreen(onBack: () => _setTab(0)),
      RecentVideosScreen(onBack: () => _setTab(0)),
      CameraScreen(
        onStartTracking: _startModelTracking,
        trackingBusy: _trackingBusy,
        detectorStatus: _detectorStatus,
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
