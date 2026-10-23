// SPDX-License-Identifier: GPL-3.0-or-later
//
// #27 U5（我的页接线）：液态菜单行 + 菜单组（线框⑥菜单区）。
//
// 形态：icon + label（+ 可选 suffix/trailing）+ chevron；**solid 行**——
// 组容器走 [LiquidSolidCard]（solid 档、零真玻璃，§0.3 列表卡纪律），
// 行与行之间发丝 Divider。行按压反馈 [LiquidPressable] 0.98（行是窄条，
// 缩放比大卡轻一档）。
//
// 功能守恒口径：行只收 icon/label/回调/trailing，**回调由页面侧原样传入**
// （我的页 controller.list 与 header 既有 onTap 零改动搬入，见 pages/mine/view.dart）。
//
// import 纪律（S16 教训）：只引 material_ui（fork）＋本目录组件，
// **不引 flutter/material**（u25 绊线组⑤扫本目录）。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_solid_card.dart';

/// 单条液态菜单行：icon + label +（suffix）+（trailing）+ chevron。
class LiquidMenuTile extends StatelessWidget {
  const LiquidMenuTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.suffix,
    this.trailing,
    this.chevron = true,
    this.semanticLabel,
    this.iconSize = 20,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 紧跟 label 的附加文案位（如「我的收藏」的文件夹计数）。
  final Widget? suffix;

  /// 行尾自定义控件位（如收藏行的刷新按钮）；位于 chevron 之前。
  final Widget? trailing;

  /// 是否画行尾 chevron（跳转类行 true；开关/切换类行 false）。
  final bool chevron;

  /// 读屏标签；缺省用 [label]（开关类行传带状态的文案，同原 tooltip 语义）。
  final String? semanticLabel;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: LiquidPressable(
        pressedScale: 0.98,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            fontFamily: LiquidFontFamily.text,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      ?suffix,
                    ],
                  ),
                ),
                ?trailing,
                if (chevron)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 菜单组：solid 卡壳内竖排若干 [LiquidMenuTile]，行间发丝 Divider。
class LiquidMenuGroup extends StatelessWidget {
  const LiquidMenuGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  /// 行列表（允许 Obx 之类 reactive 包装件作为一行）。
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidSolidCard(
      pressable: false, // 行各自可点 ⇒ 组壳不整卡按压
      margin: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.25),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
