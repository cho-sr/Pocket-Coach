import 'package:flutter/material.dart';

abstract final class AppColors {
  static const black = Color(0xFF050506);
  static const surface = Color(0xFF17171D);
  static const surfaceHigh = Color(0xFF202028);
  static const surfaceSoft = Color(0xFF101014);
  static const border = Color(0xFF2E3038);
  static const text = Color(0xFFF8F8FA);
  static const muted = Color(0xFFA9AAB3);
  static const dim = Color(0xFF686A75);
  static const accent = Color(0xFF3777F2);
  static const accentSoft = Color(0xFF17274E);
  static const red = Color(0xFFFF4657);
  static const green = Color(0xFF36D188);
  static const warning = Color(0xFFFFC857);
}

ThemeData buildPocketCoachTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.black,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.green,
      error: AppColors.red,
      surface: AppColors.surface,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    ).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
