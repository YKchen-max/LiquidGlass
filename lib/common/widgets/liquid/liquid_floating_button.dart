// SPDX-License-Identifier: GPL-3.0-or-later
//
// #27 U5（动态页接线）：液态悬浮圆钮（线框⑤发布入口的换装件）。
//
// 语义：**位置与回调由页面侧原样给定**（动态页 appBar 的 actions/leading 槽位
// 不变、`CreateDynPanel.onCreateDyn` 不变），本件只负责造型——solid 档圆片
// （零背景采样；本屏真玻璃预算＝主底导 1 处已占，发布钮不占预算）＋
// [LiquidPressable] 0.90 果冻按压（小圆钮位移感知强，比大卡缩得狠一档）＋
// Tooltip/ Semantics 保留原 tooltip 文案。
//
// import 纪律（S16 教训）：只引 material_ui（fork）＋ kit 稳定入口＋本目录
// 动效原语，**不引 flutter/material**（u25 绊线组⑤扫本目录）。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';

/// 圆形悬浮钮：solid 玻璃圆片 + 图标 + 果冻按压。
class LiquidFloatingButton extends StatelessWidget {
  const LiquidFloatingButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.diameter = 38,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// 悬停 tooltip 与读屏标签共用文案（原 IconButton.tooltip 语义保留）。
  final String? tooltip;

  final double diameter;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip ?? '',
        child: LiquidPressable(
          pressedScale: 0.9,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: LiquidGlassSurface(
              material: LiquidGlassMaterial.solid,
              borderRadius: BorderRadius.circular(diameter / 2),
              shadow: true, // 悬浮件：投影是"浮起"观感来源
              child: SizedBox(
                width: diameter,
                height: diameter,
                child: Icon(icon, size: iconSize, color: scheme.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
