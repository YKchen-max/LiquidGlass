// SPDX-License-Identifier: GPL-3.0-or-later
//
// #19（task-94）玻璃调试面板：把「当前实况」摊开给排查用。
//
// 显示：档位（运行时 + 无障碍封顶后的结果 + 播放器策略档）／能力（shader filter、折射通道）／
//       无障碍三开关／当前强度／五点对照表。
//
// ⚠ **不放任何能绕过 capability 的入口** ✗：面板是**只读**的 ——
//   没有"强制折射"按钮、没有改档位的开关（唯一可改的是强度，而强度**不改档位** ✓）。
//   这是刻意的选择（task-94 要求）：能改档位的东西只在既有 `GlassPolicyForce` 门控 + `kReleaseMode`
//   保护下存在，不从这里开口 ✗。release 下保留本面板（只读 ⇒ 无风险 ✓）。
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/glass_strength.dart';
import 'package:PiliPlus/utils/liquid_glass_policy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

/// 启动期同步是否真的跑过：kit 侧的值 vs 解析值（不等 ⇒ 说明**没同步**）。
///
/// 为什么值得显示：home-glass 查出的真 bug 就是「sync 跑在 `GStorage.init()` 之前
/// ⇒ Pref 未就绪 ⇒ 静默按关 ⇒ 设置重启后失效」✗ —— 有这一行就能一眼看出 ✓。
bool _syncMismatch() =>
    (GlassStrength.strength - LiquidGlassRuntime.strength).abs() > 1e-9;

class GlassDebugPanelPage extends StatelessWidget {
  const GlassDebugPanelPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool mono = false,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(
        value,
        style: mono
            ? theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              )
            : theme.textTheme.bodyMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capability = LiquidGlassRuntime.capability;
    final runtimeTier = LiquidGlassRuntime.tier;
    final policyTier = LiquidGlassPolicy.decideOnAttach(
      LiquidGlassPolicy.contextOf(
        isPlaying: false,
        isSeeking: false,
        layoutTransient: false,
      ),
    );
    final table = GlassStrength.fivePointTable(LiquidGlassTokens.light);
    final sub = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.outline,
    );

    final body = ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            '只读面板：不含任何能绕过能力门禁的入口（改档位的东西只在既有门控下存在）。',
            style: sub,
          ),
        ),
        _row(context, '运行时档位 tier', runtimeTier.name, mono: true),
        _row(
          context,
          '档位封顶 tierCap（现在 / 出厂默认）',
          '${LiquidGlassRuntime.tierCap?.name ?? "不限"} / 不限',
          mono: true,
        ),
        _row(
          context,
          '封顶后实际档位 cappedTier',
          LiquidGlassRuntime.cappedTier(capability?.tier ?? runtimeTier).name,
          mono: true,
        ),
        _row(
          context,
          '播放器策略档（安全时机示例）',
          '${policyTier.tier.name} — ${policyTier.reason}',
          mono: true,
        ),
        _row(
          context,
          '能力：shader filter 支持',
          capability == null ? '未初始化' : '${capability.shaderFilterSupported}',
          mono: true,
        ),
        _row(
          context,
          '能力：判定理由',
          capability?.reason ?? '未初始化',
          mono: true,
        ),
        _row(
          context,
          '折射通道可用 / provider',
          '${isRefractionShaderChannelAvailable}'
              ' / ${LiquidGlassRuntime.refractionShaderProvider != null}',
          mono: true,
        ),
        _row(
          context,
          '无障碍开关：降低透明度',
          '${GlassAccessibility.reduceTransparency}',
          mono: true,
        ),
        _row(
          context,
          '无障碍开关：减弱动效',
          '${GlassAccessibility.reduceMotion}',
          mono: true,
        ),
        _row(
          context,
          '无障碍开关：增强对比（含系统高对比度）',
          '${GlassAccessibility.increaseContrast(context)}',
          mono: true,
        ),
        _row(
          context,
          '当前玻璃强度（现在 / 出厂默认）',
          '${GlassStrength.percent}% / ${GlassStrength.defaultPercent}%'
              '  →  kit=${LiquidGlassRuntime.strength.toStringAsFixed(2)}'
              '${_syncMismatch() ? "  ⚠ 与解析值不一致（未同步）" : "  ✓ 已同步"}',
          mono: true,
        ),
        _row(
          context,
          '无障碍开关（现在 / 出厂默认）',
          '降透明=${GlassAccessibility.reduceTransparency}/false'
              '  减动效=${GlassAccessibility.reduceMotion}/false'
              '  强对比=${GlassAccessibility.increaseContrast(context)}/false',
          mono: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('滑杆值 → 旋钮取值（light token，线性映射）', style: sub),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FixedColumnWidth(52),
              1: FixedColumnWidth(52),
              2: FixedColumnWidth(52),
              3: FixedColumnWidth(52),
              4: FixedColumnWidth(52),
              5: FixedColumnWidth(52),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  for (final h in const <String>[
                    '%',
                    'blur',
                    'tintα',
                    '高光',
                    '发丝',
                    '厚度',
                  ])
                    Text(h, style: theme.textTheme.labelSmall),
                ],
              ),
              for (final r in table)
                TableRow(
                  children: <Widget>[
                    for (final v in <double>[
                      r[0],
                      r[1],
                      r[2],
                      r[3],
                      r[4],
                      r[5],
                    ])
                      Text(
                        r[0] == v ? '${v.toInt()}' : v.toStringAsFixed(2),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
    if (!showAppBar) return body;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('玻璃调试面板')),
      body: body,
    );
  }
}
