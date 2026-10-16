import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppConstants.mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= AppConstants.mobileBreakpoint &&
        width < AppConstants.tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= AppConstants.tabletBreakpoint) {
      return desktop;
    } else if (width >= AppConstants.mobileBreakpoint && tablet != null) {
      return tablet!;
    } else {
      return mobile;
    }
  }
}
