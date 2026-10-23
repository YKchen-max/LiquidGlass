// SPDX-License-Identifier: GPL-3.0-or-later
//
// 覆盖式布局的"内容避开区"环境值（U2：顶栏 + 侧栏共用同一套事实源）。
//
// 用途：漂浮式玻璃顶栏/侧栏是**覆盖**在内容之上的，于是"内容的可见区域"不再是整个视口——
// 任何把落点或宽度算在视口边上的共享组件都需要知道这段被覆盖的尺寸：
//   * 顶部：共享的下拉刷新指示器（RefreshIndicator → RefreshLayout）把转圈下移到玻璃之下；
//   * 左侧：主布局把内容右推一个"侧栏实测宽度"，避免卡片被常驻侧栏永久遮住。
//
// 为什么用 InheritedWidget 而不是给每个页面加参数：`refreshIndicator` 被上百个页面复用，
// 逐个改调用点既动了他人的页面文件，也会把"默认路径零变化"的证明面扩大到不可控。
// 这里的值是**可选**的：没有祖先时 [topOf]/[leftOf] 返回 0 → 行为与上游逐像素一致。
//
// 设计边界：只提供数值，不参与布局分支、不插占位；消费方自己决定怎么用（落点 / padding）。
import 'package:material_ui/material_ui.dart';

/// 覆盖层占用的内容尺寸（逻辑像素）。
///
/// * [top] —— 顶部覆盖层高度（漂浮玻璃顶栏）；
/// * [left] —— 左侧覆盖层宽度（常驻侧栏）。
///
/// 两者默认 0，表示"没有覆盖层"，消费方应保持上游行为。
class OverlayInsets extends InheritedWidget {
  const OverlayInsets({
    super.key,
    this.top = 0,
    this.left = 0,
    required super.child,
  });

  final double top;
  final double left;

  /// 当前顶部覆盖层高度；没有这个祖先时返回 0。
  static double topOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OverlayInsets>()?.top ?? 0;

  /// 当前左侧覆盖层宽度；没有这个祖先时返回 0。
  static double leftOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OverlayInsets>()?.left ?? 0;

  @override
  bool updateShouldNotify(OverlayInsets oldWidget) =>
      oldWidget.top != top || oldWidget.left != left;
}

/// 兼容壳：只设置 [top]（task-11 的调用点一行不用改）。
///
/// **必须把外层的 `left` 一起带下去**：主页在"侧栏 overlay"之内还会再套一层顶栏 inset，
/// 如果这层只写 top，内层就把外层的 left 抹成 0 了（子页面再读就拿到 0）。
class TopOverlayInset extends StatelessWidget {
  const TopOverlayInset({super.key, required this.value, required this.child});

  /// 顶部覆盖层高度（逻辑像素）。
  final double value;

  final Widget child;

  /// 当前顶部覆盖层高度；没有祖先时返回 0。
  static double of(BuildContext context) => OverlayInsets.topOf(context);

  @override
  Widget build(BuildContext context) => OverlayInsets(
    top: value,
    left: OverlayInsets.leftOf(context),
    child: child,
  );
}