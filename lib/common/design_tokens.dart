import 'package:material_ui/material_ui.dart' show Color, Radius, BorderRadius;

/// 设计 token —— 方案 A「深海灵蓝」。
///
/// 目标：
/// * 与上游 PiliPlus 的既有视觉拉开距离（不沿用其默认绿 / B 站粉）；
/// * 玻璃感只靠「半透明底 + 1px 高光描边 + 微渐变 + 噪点」，
///   **不依赖实时高斯模糊**，避免安卓中低端机掉帧；
/// * 深色优先，浅色提供对应映射。
///
/// 所有数值集中在这里，改一处即可全站生效。
abstract final class DesignTokens {
  // ── 主色 ────────────────────────────────────────────────
  /// 主色（蓝）
  static const primary = Color(0xFF4D8DFF);

  /// 强调色（青）
  static const accent = Color(0xFF5EE6D4);

  // ── 深色三层表面 ────────────────────────────────────────
  /// 最底层背景
  static const bg = Color(0xFF0B1018);

  /// 普通表面（卡片、列表）
  static const surface = Color(0xFF141C28);

  /// 抬升表面（悬浮层、选中态）
  static const surfaceHigh = Color(0xFF1D2938);

  // ── 玻璃层 ──────────────────────────────────────────────
  /// 玻璃填充（深色：6% 白；浅色：60% 白）
  static Color glassFill(bool isDark) =>
      isDark ? const Color(0x0FFFFFFF) : const Color(0x99FFFFFF);

  /// 玻璃描边（1px 高光）
  static Color glassStroke(bool isDark) =>
      isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000);

  /// 玻璃顶部微渐变（自上而下衰减），用于 stack 里的 DecoratedBox
  static Color glassHighlightTop(bool isDark) =>
      isDark ? const Color(0x1AFFFFFF) : const Color(0x33FFFFFF);

  static const glassHighlightBottom = Color(0x00FFFFFF);

  // ── 圆角（大 / 中 / 小）────────────────────────────────
  static const Radius radiusLarge = Radius.circular(24);
  static const Radius radiusMedium = Radius.circular(16);
  static const Radius radiusSmall = Radius.circular(10);

  static const BorderRadius brLarge = BorderRadius.all(radiusLarge);
  static const BorderRadius brMedium = BorderRadius.all(radiusMedium);
  static const BorderRadius brSmall = BorderRadius.all(radiusSmall);

  /// 底部弹层：沿用「上圆角」习惯，但收一档到 24
  static const BorderRadius brSheet = BorderRadius.vertical(top: radiusLarge);

  // ── 间距 ────────────────────────────────────────────────
  static const spaceXs = 4.0;
  static const spaceS = 8.0;
  static const spaceM = 12.0;
  static const spaceL = 16.0;
  static const spaceXl = 24.0;
}
