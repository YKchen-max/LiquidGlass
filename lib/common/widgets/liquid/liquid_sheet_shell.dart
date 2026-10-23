// SPDX-License-Identifier: GPL-3.0-or-later
//
// #28a U6 长尾包装层：详情页主题级准收官 —— 底部弹层玻璃壳。
//
// 定位（docs/UI重构方案.md §2 #28「弹层主题注入换肤（import＋包装两行式）」＋
// 真折射移植计划 §0.1.66 案 4「主树保持现状」）：包住 `showBottomSheet` 的
// 内容 builder 产物，给它挂「glassThick 玻璃底＋拖拽把手」，**内容零改透传**。
//
// 玻璃纪律（docs/UI重构方案.md §0.3）：弹层 = **瞬态**真玻璃（home 弹层先例
// LiquidActionSheet 同款 glassThick ✓），不占详情页常驻预算（常驻真玻璃仍 =
// 播放器顶栏＋底栏 2 处 ✓）。
//
// A3 纪律（照抄 liquid_action_sheet.dart 的「审视 A3 修复」段，现成实现）：
// route 滑入/滑出期间 BackdropFilter 每帧重采样背景（Windows v1 走 Skia =
// 滑动区域每帧全量模糊，低端机必卡）⇒ 过渡期用 solid 档（零背景采样），
// route 动画走到 **85%** 之后才挂真玻璃（thick）。
// 注：MiniScaffold 的本地 sheet（详情页 5 处接线全走它）不是模态 route ⇒
// `ModalRoute.of` 拿到的是宿主页 route（早已停在 1.0）⇒ 判据同式同实现、
// 行为 = 挂玻璃；真正的模态弹层（showModalBottomSheet 一族）则获得完整 A3。
//
// 布局纪律（**约束透明**，接线的生命线）：5 个既有面板里有的用
// `Column(max) + Expanded`、有的用 `SimpleScaffold`（`size = constraints.biggest`）
// ⇒ 壳**绝不**用 Column 追加把手（min-Column 会让满高内容溢出 ✗），而是用
// LiquidGlassPanel 的 **padding 顶出把手区**（Padding 会先扣减子件 maxHeight，
// 满高内容拿 H−14、总高恰 = H ✓）＋ Stack 叠一枚装饰把手（IgnorePointer，
// 不抢手势 ⇒ 面板自带把手/关闭钮的点击原样透传 ✓）。
//
// 动效纪律：本件**零新增动画**（AnimatedBuilder 只旁听宿主 route 的既有动画，
// 不自建 AnimationController）⇒ GlassAccessibility.motionDuration 口径不适用
// （无新时长可映射；A3 的 0.85 阈值与现成实现逐字同款）。
//
// import 纪律（S16 教训，u25 绊线组⑤扫本目录）：只引 material_ui（fork）＋
// kit 稳定入口＋本目录，**不引 flutter/material**。
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

/// 底部弹层玻璃壳：glassThick（settle 后）＋ A3 过渡降级 ＋ 拖拽把手 ＋ 内容透传。
///
/// **solid 降级档可渲染** ✓：过渡期（动画 ≤85%）与「降低透明度」封顶
/// （LiquidGlassRuntime.tierCap ⇒ kit 内部降档）都落到 `LiquidGlassMaterial.solid`
/// / solid tier —— 纯色半透明＋发丝描边、零背景采样，任何档位都不白屏。
class LiquidSheetShell extends StatelessWidget {
  const LiquidSheetShell({
    super.key,
    required this.child,
    this.showHandle = true,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(28)),
    this.animation,
  });

  /// 测试/组件断言用的把手 Key（生产无副作用）。
  static const Key handleKey = Key('liquid_sheet_shell_handle');

  /// 把手区高度（= 壳给内容 padding 出的顶部空间；把手叠画在这条区里）。
  /// 取 14：与面板自带 35px 把手行不重叠、且落在 BottomSheet 拖拽识别区
  /// （顶部 45px，bottom_sheet.dart `isPointerAllowed`）之内 ✓。
  static const double handleZoneHeight = 14;

  /// 弹层内容（**原样透传** ✓ —— 零结构改动的前提；手势/语义/Inherited 查找
  /// 全部原样可达：壳只加 InheritedWidget 与装饰层，不设任何 context 边界）。
  final Widget child;

  /// 是否画拖拽把手（装饰件；默认 true。面板自带把手时可按调用点关掉）。
  final bool showHandle;

  /// 壳圆角。本地 sheet 三边贴屏幕沿 ⇒ 默认只圆上两角（28，与
  /// LiquidActionSheet 同族观感）。
  final BorderRadius borderRadius;

  /// 显式驱动动画（测试接缝 / 非常规宿主用）；null ⇒ 取
  /// `ModalRoute.of(context)?.animation`（liquid_action_sheet 同款判据）。
  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // A3 纪律（照抄 liquid_action_sheet.dart「审视 A3 修复」）：
    // 过渡期 solid（零背景采样），动画 >85% 才挂 thick 真玻璃。
    final Animation<double>? animation =
        this.animation ?? ModalRoute.of(context)?.animation;
    return AnimatedBuilder(
      animation: animation ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        final bool settled = (animation?.value ?? 1.0) > 0.85;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            LiquidGlassPanel(
              material: settled
                  ? LiquidGlassMaterial.thick
                  : LiquidGlassMaterial.solid,
              borderRadius: borderRadius,
              // padding 顶出把手区 ⇒ 对满高内容（Expanded/biggest）约束透明。
              padding: EdgeInsets.only(
                top: showHandle ? handleZoneHeight : 0,
              ),
              child: child,
            ),
            if (showHandle)
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  // 装饰件：不包 Semantics（与 LiquidActionSheet 的拖拽条同口径），
                  // IgnorePointer ⇒ 点击穿到面板自带把手/关闭钮，交互零改。
                  child: Center(
                    child: Container(
                      key: handleKey,
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
