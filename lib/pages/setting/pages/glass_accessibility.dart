// SPDX-License-Identifier: GPL-3.0-or-later
//
// #18 无障碍映射（task-93）的设置页：三个开关（Apple 语义）。
//
// 每个开关都直接作用在既有的三级降级矩阵上，不新造机制：
//   * 降低透明度 ⇒ 玻璃档位封顶到**纯色**（`LiquidGlassPolicy.effectiveTier` 收口）；
//   * 减弱动效   ⇒ 玻璃相关过渡时长归零（控制条换档淡入 ⇒ 阶跃）；
//   * 增强对比   ⇒ 强制启用 kit 的自适应对比度（并加粗发丝）。
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/widgets/switch_item.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';

class GlassAccessibilityPage extends StatelessWidget {
  const GlassAccessibilityPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '这三个开关与系统无障碍设置同语义；默认全关时玻璃表现与之前完全一致。',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        SetSwitchItem(
          title: '降低透明度',
          subtitle:
              '把玻璃档位封顶到纯色（不采样背景）。顺带白拿性能：'
              '密集负载下折射档每帧贵 +7.95 ms',
          setKey: SettingBoxKey.glassReduceTransparency,
          leading: const Icon(Icons.blur_off_outlined),
          onChanged: (_) => GlassAccessibility.syncRuntimeFlags(),
        ),
        SetSwitchItem(
          title: '减弱动效',
          subtitle: '与玻璃相关的过渡（控制条换档淡入）改为瞬时切换（阶跃），不做淡入',
          setKey: SettingBoxKey.glassReduceMotion,
          leading: const Icon(Icons.motion_photos_off_outlined),
          onChanged: (_) => GlassAccessibility.syncRuntimeFlags(),
        ),
        SetSwitchItem(
          title: '增强对比',
          subtitle:
              '强制启用自适应对比度并加粗玻璃描边；'
              'Windows 高对比度主题打开时自动视同开启',
          setKey: SettingBoxKey.glassIncreaseContrast,
          leading: const Icon(Icons.contrast_outlined),
          onChanged: (_) => GlassAccessibility.syncRuntimeFlags(),
        ),
      ],
    );
    if (!showAppBar) {
      return body;
    }
    return SimpleScaffold(
      appBar: AppBar(title: const Text('玻璃无障碍')),
      body: body,
    );
  }
}
