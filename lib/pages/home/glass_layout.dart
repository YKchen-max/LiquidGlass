// SPDX-License-Identifier: GPL-3.0-or-later
//
// 首页顶部玻璃区的布局契约（U2 漂浮式）：顶栏高度与"内容顶部内边距"的单一事实源。
//
// 为什么单独一个文件：漂浮式（内容从玻璃底下穿过）要求
//     内容顶部内边距 == 顶栏**展开态**高度
// 而这个高度由顶栏自身的组成决定（搜索栏行是否显示、频道行是 42 条高还是 6 占位、
// 侧栏/竖屏布局差异……）。把常量与算式集中在这里、由 view.dart 与 5 个 tab 页共用，
// 内边距就会随顶栏定义自动跟随——而不是在页面里写死一个像素值（顶栏结构一变就错位）。
//
// 纯色档 / 折叠路径下**不会**注入 [HomeGlassInset]：tab 页拿不到祖先，[of] 返回 0，
// 控件树与几何都回到上游（这是"纯色档逐像素一致"的实现方式）。
import 'package:PiliPlus/common/style.dart';
import 'package:material_ui/material_ui.dart';

/// 频道行（直播/推荐/热门/分区/番剧…）条高。
const double kHomeChannelBarHeight = 42;

/// 频道行与搜索栏之间的间距。
const double kHomeChannelBarTopGap = 4;

/// 只剩一个 tab 时频道行的占位高度（上游行为）。
const double kHomeChannelBarEmptyHeight = 6;

/// 顶部区**展开态**总高度 = 搜索栏行（若显示）+ 频道行。
///
/// 只在这里算一次：`view.dart` 用它决定漂浮式内边距，tab 页用它决定首个 sliver 的留白。
double homeHeaderHeight({required bool showAppBar, required int tabCount}) =>
    (showAppBar ? Style.topBarHeight : 0) +
    (tabCount > 1
        ? kHomeChannelBarHeight + kHomeChannelBarTopGap
        : kHomeChannelBarEmptyHeight);

/// 首页漂浮式玻璃注入给 tab 页的顶部内边距。
///
/// 取值语义：
///   * 首页处于漂浮式玻璃档 → value = [homeHeaderHeight]（展开态顶栏高度）；
///   * 纯色档、折叠路径（`hideTopBar`）、或该 tab 页被别的路由复用（没有这个祖先）
///     → [of] 返回 0，tab 页保持上游几何，绝不会凭空多出一段空白。
class HomeGlassInset extends InheritedWidget {
  const HomeGlassInset({super.key, required this.value, required super.child});

  final double value;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeGlassInset>()?.value ?? 0;

  /// tab 页里的一行式接入：把留白作为**首个 sliver** 插进 slivers 列表。
  ///
  /// 返回 null（= 不插任何东西）是刻意的：用 `?HomeGlassInset.sliverSpacer(context)`
  /// 这种 null-aware element 写法，纯色档下控件树与上游**逐节点相同**，
  /// 才能拿到"0 像素差"的断言结果——而不是插一个高 0 的 sliver 去祈祷布局不变。
  static Widget? sliverSpacer(BuildContext context) {
    final inset = of(context);
    if (inset <= 0) return null;
    return SliverToBoxAdapter(child: SizedBox(height: inset));
  }

  @override
  bool updateShouldNotify(HomeGlassInset oldWidget) => oldWidget.value != value;
}