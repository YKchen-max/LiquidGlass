// SPDX-License-Identifier: GPL-3.0-or-later
//
// #19（task-94）设置页：玻璃强度滑杆 + 调试面板入口。
//
// 语义提醒（界面上也写出来，避免用户与「降低透明度」混淆 ✗）：
//   * 强度**不改档位** —— 0% 是最弱的**同一档位**（几乎纯色），不是降档；
//   * 「降低透明度」才是真降档（封顶 solid），两者可同时开：那时强度仍作用于 solid ✓。
import 'package:PiliPlus/pages/setting/pages/glass_debug_panel.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/utils/glass_strength.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';

class GlassStrengthPage extends StatefulWidget {
  const GlassStrengthPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<GlassStrengthPage> createState() => _GlassStrengthPageState();
}

class _GlassStrengthPageState extends State<GlassStrengthPage> {
  late int _pct;

  @override
  void initState() {
    super.initState();
    _pct = GlassStrength.percent;
  }

  Future<void> _set(int v) async {
    setState(() => _pct = v);
    await GStorage.setting.put(SettingBoxKey.glassStrength, v);
    GlassStrength.syncRuntimeFlags();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.outline,
    );
    final body = ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            '强度只缩放同一档位内部的旋钮（模糊、底色、高光、发丝、折射参数），不改变档位。'
            '0% 最弱、100% 为出厂默认。',
            style: sub,
          ),
        ),
        ListTile(
          title: Row(
            children: [
              const Text('玻璃强度'),
              const Spacer(),
              Text('$_pct%', style: theme.textTheme.titleMedium),
            ],
          ),
          subtitle: const Text('0% = 最弱（仍走原档位）／100% = 出厂默认'),
        ),
        Slider(
          value: _pct.toDouble(),
          min: GlassStrength.minPercent.toDouble(),
          max: GlassStrength.maxPercent.toDouble(),
          divisions: 20,
          label: '$_pct%',
          onChanged: (v) => _set(v.round()),
        ),
        ListTile(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const GlassDebugPanelPage(),
            ),
          ),
          leading: const Icon(Icons.monitor_heart_outlined),
          title: const Text('玻璃调试面板'),
          subtitle: const Text('档位／判定理由／能力／无障碍开关／强度＋五点对照表'),
        ),
      ],
    );
    if (!widget.showAppBar) return body;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('玻璃强度')),
      body: body,
    );
  }
}
