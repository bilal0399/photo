import 'package:flutter/widgets.dart';

/// Screen-size tiers used across the app for adaptive layouts.
enum FormFactor { mobile, tablet, desktop }

class Breakpoints {
  Breakpoints._();
  static const double tablet = 600;
  static const double desktop = 1024;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  FormFactor get formFactor {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) return FormFactor.desktop;
    if (w >= Breakpoints.tablet) return FormFactor.tablet;
    return FormFactor.mobile;
  }

  bool get isMobile => formFactor == FormFactor.mobile;
  bool get isTablet => formFactor == FormFactor.tablet;
  bool get isDesktop => formFactor == FormFactor.desktop;
  bool get isWide => formFactor != FormFactor.mobile;

  /// Number of columns for card grids at the current width.
  int get gridColumns {
    switch (formFactor) {
      case FormFactor.desktop:
        return 3;
      case FormFactor.tablet:
        return 2;
      case FormFactor.mobile:
        return 1;
    }
  }
}
