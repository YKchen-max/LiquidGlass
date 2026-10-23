// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26a 接线组件：LiquidActionItem —— 互动行（赞/踩/币/藏/稍后/分享）的 liquid 视觉版。
//
// 划界说明（重要）：
//   * 存量 `ActionItem`（`pages/video/introduction/ugc/widgets/action_item.dart`）**另有 4 个
//     页面在用**（`pages/audio/view.dart`、`pages/video/introduction/pgc/view.dart`、
//     `pages/video/widgets/header_control.dart`，均不在本单写范围内）⇒ **不动它** ✗；
//     本文件是"新风格 ActionItem"（任务 §① 明确允许的两条路之一），只在
//     `introduction/ugc/view.dart` 的互动行上换装 ✓。
//   * **参数签名与存量逐一对齐**（`icon/selectIcon/onTap/onLongPress/text/selectStatus/
//     semanticsLabel/expand/animation/onStartTriple/onCancelTriple`）⇒ 调用点只改类名，
//     六个功能的 controller 绑定**零改动** ✓（功能守恒由构造保证）。
//
// 纪律：
//   * 本目录**禁 flutter 的 material 包** ✗（全树是 material_ui fork；走 flutter 那套 Theme
//     会静默落亮色 fallback ⇒ 黑字糊黑卡）。本文件只从 `material_ui` 取主题 ✓。
//   * 按压反馈走 `LiquidPressable`（`liquid_motion.dart` ✓）——它内部已把两条时长
//     过 `GlassAccessibility.motionDuration` ✓，并且用 `Listener` 旁路观察指针、
//     **不进手势竞技场** ⇒ 下方 InkWell 的 tap/long-press/三连手势原样保留 ✓。
//   * 本文件新增的文字切换动画时长也过 `motionDuration` ✓（T1 教训）。
import 'package:PiliPlus/common/widgets/custom_arc.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

/// 互动行单元（liquid 视觉版），签名与存量 `ActionItem` 一致。
class LiquidActionItem extends StatelessWidget {
  const LiquidActionItem({
    super.key,
    required this.icon,
    this.selectIcon,
    this.onTap,
    this.onLongPress,
    this.text,
    this.selectStatus = false,
    required this.semanticsLabel,
    this.expand = true,
    this.animation,
    this.onStartTriple,
    this.onCancelTriple,
  }) : assert(!selectStatus || selectIcon != null),
       _isThumbsUp = onStartTriple != null;

  final Icon icon;
  final Icon? selectIcon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? text;
  final bool selectStatus;
  final String semanticsLabel;
  final bool expand;
  final Animation<double>? animation;
  final VoidCallback? onStartTriple;
  final void Function([bool])? onCancelTriple;
  final bool _isThumbsUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final primary = !expand && colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    Widget child = Icon(
      selectStatus ? selectIcon!.icon! : icon.icon,
      size: 18,
      color: selectStatus ? primary : icon.color ?? colorScheme.outline,
      semanticLabel: semanticsLabel,
    );

    if (animation != null) {
      child = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: animation!,
            builder: (context, child) =>
                Arc(size: 28, color: primary, progress: -animation!.value),
          ),
          child,
        ],
      );
    } else {
      child = SizedBox.square(dimension: 28, child: child);
    }

    child = LiquidPressable(
      // 胶囊尺度按压：目标较小 ⇒ 用 0.92（见 LiquidPressable.pressedScale 的取值建议）。
      pressedScale: 0.92,
      child: Material(
        type: .transparency,
        child: InkWell(
          borderRadius: const .all(.circular(6)),
          onTap: _isThumbsUp ? null : onTap,
          onLongPress: _isThumbsUp ? null : onLongPress,
          onSecondaryTap: PlatformUtils.isMobile || _isThumbsUp
              ? null
              : onLongPress,
          onTapDown: _isThumbsUp ? (_) => onStartTriple!() : null,
          onTapUp: _isThumbsUp ? (_) => onCancelTriple!(true) : null,
          onTapCancel: _isThumbsUp ? onCancelTriple : null,
          child: expand
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [child, _buildText(theme)],
                )
              : child,
        ),
      ),
    );
    return expand ? Expanded(child: child) : child;
  }

  Widget _buildText(ThemeData theme) {
    final hasText = text != null;
    final child = Text(
      hasText ? text! : '-',
      key: hasText ? ValueKey(text!) : null,
      style: TextStyle(
        color: selectStatus
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
        fontSize: theme.textTheme.labelSmall!.fontSize,
      ),
    );
    if (hasText) {
      return AnimatedSwitcher(
        // 与存量同手感，但时长过 #18 无障碍映射（减弱动效 ⇒ 阶跃）✓ T1。
        duration: GlassAccessibility.motionDuration(
          const Duration(milliseconds: 300),
        ),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: child,
      );
    }
    return child;
  }
}