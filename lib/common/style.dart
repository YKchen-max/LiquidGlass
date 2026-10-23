import 'package:PiliPlus/common/design_tokens.dart';
import 'package:material_ui/material_ui.dart'
    show BorderRadius, Radius, BoxConstraints, ButtonStyle, VisualDensity;

abstract final class Style {
  static const cardSpace = 8.0;
  static const safeSpace = 12.0;
  static const mdRadius = BorderRadius.all(imgRadius);
  static const imgRadius = Radius.circular(10);
  static const aspectRatio = 16 / 10;
  static const aspectRatio16x9 = 16 / 9;
  static const imgMaxRatio = 2.6;
  // #28b long-tail skin: sheet-family radius aligned to liquid family
  // (LiquidSheetShell/LiquidActionSheet = 28 = fork M3 BottomSheet default).
  // Theme-root bottomSheetTheme.shape refs this const: one place, whole app.
  static const bottomSheetRadius = DesignTokens.brSheet;
  static const dialogFixedConstraints = BoxConstraints.tightFor(width: 420);
  static const topBarHeight = 52.0;
  static const buttonStyle = ButtonStyle(
    visualDensity: VisualDensity(horizontal: -2, vertical: -1.25),
    tapTargetSize: .shrinkWrap,
  );
  static const placeHolder = '\uFFFC';
}

