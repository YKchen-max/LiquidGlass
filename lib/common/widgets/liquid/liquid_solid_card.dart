// SPDX-License-Identifier: GPL-3.0-or-later
//
// #27 U5：列表卡「液态 solid 卡壳」——卡片容器的 chrome 统一入口。
//
// 纪律（docs/UI重构方案.md §0.3 / 问题文档 §4）：**列表卡片一律假玻璃/贴图，
// 永不上真玻璃**——本组件固定 `LiquidGlassMaterial.solid`（纯色半透明＋
// 发丝描边、零背景采样），真玻璃只留给导航/顶栏/控制条/弹层。
// 一屏真玻璃预算由页面侧核算（动态/我的两屏自身 0 处，主底导 1 处 ⇒ ≤2 ✓）。
//
// 按压反馈默认挂 [LiquidPressable]（Listener 旁路、不进手势竞技场 ⇒ 卡内
// 既有 tap/longPress 契约逐字不动）；时长过 GlassAccessibility.motionDuration
// （减弱动效 ⇒ 阶跃，T1 口径）。
//
// import 纪律（S16 教训）：只引 material_ui（fork）＋ kit 稳定入口＋本目录
// 动效原语，**不引 flutter/material**（u25 绊线组⑤扫本目录）。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';

/// solid 档卡片外壳：把任意 child 包进「发丝描边圆角卡」＋可选果冻按压。
///
/// 与 [LiquidVideoCard] 同口径（那件是首页双列卡专用、内容写死；本件是
/// #27 动态卡/我的资料卡/菜单组的**通用壳**，内容完全由调用方给定）。
class LiquidSolidCard extends StatelessWidget {
  const LiquidSolidCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.pressable = true,
    this.pressedScale = 0.96,
    this.margin,
    this.shadow = false,
  });

  /// 卡内容（手势/语义原样透传）。
  final Widget child;

  /// 卡壳圆角（同时是按压水波/描边的形状备忘）。
  final BorderRadius borderRadius;

  /// 是否包果冻按压（列表卡 true；菜单组这类「行各自可点」的容器传 false）。
  final bool pressable;

  /// 按到底缩放（大卡 0.96，同 [LiquidVideoCard]）。
  final double pressedScale;

  /// 卡外留白（**余量留在玻璃外**口径：网格/瀑布 extent 估大时多出的是
  /// 透明区而不是玻璃内空缝，见 liquid_video_card.dart 注释）。
  final EdgeInsetsGeometry? margin;

  /// 投影（贴内容层的列表卡 false；悬浮件可 true）。
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    Widget core = LiquidGlassSurface(
      material: LiquidGlassMaterial.solid,
      borderRadius: borderRadius,
      shadow: shadow,
      child: child,
    );
    if (pressable) {
      core = LiquidPressable(pressedScale: pressedScale, child: core);
    }
    if (margin != null) {
      core = Padding(padding: margin!, child: core);
    }
    return core;
  }
}
