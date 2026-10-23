// SPDX-License-Identifier: GPL-3.0-or-later
//
// #28a U6 长尾包装层：详情页主题级准收官 —— AppBar 皮肤包装件。
//
// 定位（docs/UI重构方案.md §2 #28「不动结构、只做 appbar/卡片/弹层主题注入换肤
// （import＋包装两行式）」＋ 真折射移植计划 §0.1.66 案 4「主树保持现状」）：
//   * 本件是**纯主题注入**的包装件：包住任意 appbar 子件（SimpleAppBar /
//     AppBar / 任意 PreferredSizeWidget），给子树换上「液态」主题 token；
//   * **零结构改动**：不增删子件、不动语义（Semantics 原样透传）、不动返回键 /
//     leading / actions（子件自带什么就是什么，本件一个手势都不加）；
//   * **布局零影响**：build 只套 InheritedWidget（Theme），不产生任何 RenderBox
//     ⇒ SimpleScaffold 的 appBar 槽位量到的高度仍 = 子件自身高度。
//
// 玻璃纪律（docs/UI重构方案.md §0.3）：**solid 档，不加真玻璃** ✗✓ ——
// 详情页常驻真玻璃已 = 播放器顶栏（liquid_header_skin）＋底栏（R1 玻璃条）
// 2 处 = 一屏预算已满；本件因此只注入「背景 = colorScheme.surface 系」的
// solid 档主题 token（appBarTheme.backgroundColor = surface），零背景采样。
//
// 动效纪律：本件**零新增动画**（无 AnimationController、无隐式动画）⇒
// GlassAccessibility.motionDuration 口径不适用（无时长可映射）。
//
// import 纪律（S16 教训，u25 绊线组⑤扫本目录）：只引 material_ui（fork）＋
// kit 稳定入口＋本目录，**不引 flutter/material**（其 Theme 在本 app 无人安装，
// 会静默落 ThemeData.fallback() ⇒ 深色模式黑字糊黑卡）。
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

/// AppBar 皮肤包装件（solid 档主题注入）。
///
/// ## preferredSize 透传
/// 子件是 [PreferredSizeWidget] ⇒ [preferredSize] 逐字透传（真 Scaffold 的
/// appBar 槽位读它布局，包装前后布局不变）；子件不是（如 `SimpleAppBar`——
/// 它是 `SimpleScaffold` appBar 槽位里的普通子件，槽位按实测高度布局、根本不读
/// preferredSize）⇒ 落到 [fallbackPreferredSize]（默认 kToolbarHeight），
/// 对既有布局**零影响**。
///
/// ## 注入了什么（solid 档主题 token）
///   * `appBarTheme.backgroundColor = colorScheme.surface`（＋ foregroundColor =
///     onSurface）——「背景 = surface 系」的 token 出处：后代若有真 AppBar，
///     默认底色即 solid surface（**不挂 LiquidGlassSurface** ✗，预算纪律）；
///   * `textTheme` 全族换 [LiquidFontFamily.text]（液态字阶）；
///   * `iconTheme` / `primaryIconTheme` 颜色 = `colorScheme.onSurface`（图标色）。
///
/// ## 透传零改
/// 语义 / 返回键 / leading / actions 全在子件手里，本件不包 Semantics、
/// 不加手势、不改命中测试 —— 子树对交互与无障碍完全等价于包装前。
class LiquidAppBarSkin extends StatelessWidget implements PreferredSizeWidget {
  const LiquidAppBarSkin({
    super.key,
    required this.child,
    this.fallbackPreferredSize = const Size.fromHeight(kToolbarHeight),
  });

  /// 被包装的 appbar 子件（原样透传 ✓ —— 零结构改动的前提）。
  final Widget child;

  /// 子件不是 [PreferredSizeWidget] 时的 preferredSize 兜底值。
  /// 默认 kToolbarHeight；`SimpleScaffold` 槽位不读它（按实测高度布局）。
  final Size fallbackPreferredSize;

  @override
  Size get preferredSize {
    final Widget current = child;
    return current is PreferredSizeWidget
        ? current.preferredSize
        : fallbackPreferredSize;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // 只有 InheritedWidget（Theme），零 RenderBox ⇒ 布局/尺寸与 child 完全一致。
    return Theme(
      data: theme.copyWith(
        // 背景 token = colorScheme.surface 系（solid 档，非真玻璃）。
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
        ),
        // 液态字阶：正文族全量换 LiquidText。
        textTheme: theme.textTheme.apply(fontFamily: LiquidFontFamily.text),
        // 图标色：onSurface 系。
        iconTheme: theme.iconTheme.copyWith(color: scheme.onSurface),
        primaryIconTheme: theme.primaryIconTheme.copyWith(
          color: scheme.onSurface,
        ),
      ),
      child: child,
    );
  }
}
