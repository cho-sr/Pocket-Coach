import 'package:flutter/material.dart';

class ReadinessItem {
  const ReadinessItem({
    required this.title,
    required this.status,
    required this.icon,
    this.wide = false,
  });

  final String title;
  final String status;
  final IconData icon;
  final bool wide;
}

class TrackingSession {
  const TrackingSession({
    required this.title,
    required this.recordedAt,
    required this.duration,
    required this.asset,
    this.videoPath,
  });

  final String title;
  final DateTime recordedAt;
  final String duration;
  final String asset;
  final String? videoPath;
}

const readinessItems = [
  ReadinessItem(
    title: 'Camera Feed',
    status: 'Online',
    icon: Icons.phone_iphone_rounded,
    wide: true,
  ),
];
