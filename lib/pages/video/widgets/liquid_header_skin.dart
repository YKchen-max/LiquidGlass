// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26 批2 · 皮肤件（二）：**播放器顶栏玻璃底**
//
// 做法与理由（task-117 勘查 → task-118 执行 ✓）：
//   * `HeaderControl` 是 78 KB 的 Obx 装配体 ✗ —— 从**内部**插玻璃底风险高、功能守恒难证 ✓；
//     ⇒ 改为在**调用点**包一层皮肤件（"换皮不换骨" ✓），`HeaderControl` 内部**一行未动** ✓✓。
//   * 材质**继承 B1/B5** ✓：`LiquidGlassSurface` ＋ `LiquidGlassMaterial.regular` ✓
//     （与同族先例 `liquid_top_bar.dart:27-30` 完全同款 ✓）。
//   * **挂载纪律 §6.1** ✓：`visible == false` ⇒ **直接返回 child、不挂任何玻璃层** ✗
//     （不白烧 GPU ✓；显隐信号沿用现结构的 `showControls` ✓）。
//   * **玻璃预算** ✓：本件＝顶栏 1 处 ✓（底栏 R1 玻璃条已存在 ⇒ 全页 2 处 ✓ 在 §0.3 上限内）。
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

/// 顶栏玻璃底（皮肤件 ✓）。**不含任何业务逻辑** ✗：只决定"这一帧要不要挂玻璃" ✓。
class LiquidHeaderGlass extends StatelessWidget {
  const LiquidHeaderGlass({
    super.key,
    required this.visible,
    required this.child,
    this.borderRadius = const BorderRadius.vertical(
      bottom: Radius.circular(14),
    ),
    this.padding = EdgeInsets.zero,
    this.material = LiquidGlassMaterial.regular,
  });

  /// 控制条是否可见（沿用现结构显隐信号 ✓）。
  final bool visible;

  /// 原顶栏件（**原样透传** ✓ —— 功能守恒的前提 ✓）。
  final Widget child;

  /// 全宽顶栏 ⇒ 只圆下两角 ✓（上两角贴屏幕边 ✓）；可调 ✓。
  final BorderRadius borderRadius;

  /// 玻璃层内边距（默认零：**不改变原布局尺寸** ✓）。
  final EdgeInsetsGeometry padding;

  /// Material tier (B1/B5 policy): playing => solid (no per-frame
  /// BackdropFilter resampling of the video texture), paused/idle => regular.
  /// Default regular keeps preview/default call sites unchanged.
  final LiquidGlassMaterial material;

  @override
  Widget build(BuildContext context) {
    // §6.1：隐藏 ⇒ 摘层（连壳都不包 ✓）
    if (!visible) return child;
    return LiquidGlassSurface(
      material: material,
      borderRadius: borderRadius,
      shadow: false,
      padding: padding,
      child: child,
    );
  }
}
