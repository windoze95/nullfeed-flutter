import 'package:flutter/material.dart';

enum DeviceType { phone, tablet }

class AdaptiveLayout extends StatelessWidget {
  final Widget Function(BuildContext context, DeviceType deviceType) builder;

  const AdaptiveLayout({super.key, required this.builder});

  static DeviceType getDeviceType(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortestSide = size.shortestSide;

    // iPad or tablet (including very large screens)
    if (shortestSide >= 600) return DeviceType.tablet;
    // iPhone or phone
    return DeviceType.phone;
  }

  static bool isTablet(BuildContext context) =>
      getDeviceType(context) == DeviceType.tablet;

  static bool isPhone(BuildContext context) =>
      getDeviceType(context) == DeviceType.phone;

  /// Content padding per device type
  static double contentPadding(BuildContext context) {
    return switch (getDeviceType(context)) {
      DeviceType.tablet => 24.0,
      DeviceType.phone => 16.0,
    };
  }

  static int gridCrossAxisCount(BuildContext context) {
    return switch (getDeviceType(context)) {
      DeviceType.tablet => 3,
      DeviceType.phone => 2,
    };
  }

  /// Adaptive value helper — pick per device type
  static T value<T>(BuildContext context, {required T phone, T? tablet}) {
    return switch (getDeviceType(context)) {
      DeviceType.tablet => tablet ?? phone,
      DeviceType.phone => phone,
    };
  }

  @override
  Widget build(BuildContext context) {
    return builder(context, getDeviceType(context));
  }
}
