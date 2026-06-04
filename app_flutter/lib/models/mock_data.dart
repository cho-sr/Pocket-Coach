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

class DeviceConnection {
  const DeviceConnection({
    required this.name,
    required this.detail,
    required this.icon,
    required this.status,
  });

  final String name;
  final String detail;
  final IconData icon;
  final String status;
}

class TelemetryLine {
  const TelemetryLine({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class TrackingSession {
  const TrackingSession({
    required this.title,
    required this.date,
    required this.duration,
    required this.asset,
    required this.avgFps,
    required this.lost,
    required this.stability,
  });

  final String title;
  final String date;
  final String duration;
  final String asset;
  final String avgFps;
  final String lost;
  final String stability;
}

const readinessItems = [
  ReadinessItem(
    title: 'Camera Feed',
    status: 'Online',
    icon: Icons.phone_iphone_rounded,
    wide: true,
  ),
  ReadinessItem(
    title: 'Arduino',
    status: 'Online',
    icon: Icons.bolt_rounded,
  ),
  ReadinessItem(
    title: 'Servo Sys',
    status: 'Online',
    icon: Icons.speed_rounded,
  ),
  ReadinessItem(
    title: 'AI Model Engine',
    status: 'Online',
    icon: Icons.monitor_heart_rounded,
    wide: true,
  ),
];

const deviceConnections = [
  DeviceConnection(
    name: 'Smartphone Camera',
    detail: 'Ultra Wide - 4K 60FPS',
    icon: Icons.photo_camera_outlined,
    status: 'Connected',
  ),
  DeviceConnection(
    name: 'Arduino Uno',
    detail: 'USB OTG Hub Active',
    icon: Icons.usb_rounded,
    status: 'Connected',
  ),
  DeviceConnection(
    name: 'Servo Motor',
    detail: 'Dual Axis Ready',
    icon: Icons.flash_on_rounded,
    status: 'Connected',
  ),
  DeviceConnection(
    name: 'AI Model',
    detail: 'YOLOv8-Soccer-Tracking',
    icon: Icons.memory_rounded,
    status: 'Connected',
  ),
  DeviceConnection(
    name: 'NPU Acceleration',
    detail: 'Neural Engine Enabled',
    icon: Icons.developer_board_rounded,
    status: 'Connected',
  ),
];

const telemetryLines = [
  TelemetryLine(
    label: 'Pan Center',
    value: '0 deg',
    icon: Icons.adjust_rounded,
  ),
  TelemetryLine(
    label: 'Servo Response',
    value: 'Normal',
    icon: Icons.monitor_heart_rounded,
  ),
  TelemetryLine(
    label: 'Tracking Mode',
    value: 'Target Lock',
    icon: Icons.track_changes_rounded,
  ),
];

const trackingSessions = [
  TrackingSession(
    title: 'Match Tracking 01',
    date: 'Oct 24, 2023 - 14:20',
    duration: '15:45',
    asset: 'assets/images/session_01.jpg',
    avgFps: '28.7',
    lost: '2',
    stability: '92%',
  ),
  TrackingSession(
    title: 'Training Session A',
    date: 'Oct 22, 2023 - 09:15',
    duration: '22:10',
    asset: 'assets/images/live_preview.jpg',
    avgFps: '29.1',
    lost: '0',
    stability: '98%',
  ),
  TrackingSession(
    title: 'Corner Kick Focus',
    date: 'Oct 20, 2023 - 16:45',
    duration: '08:32',
    asset: 'assets/images/session_02.jpg',
    avgFps: '27.4',
    lost: '5',
    stability: '85%',
  ),
];
