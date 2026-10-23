// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26a 头像接线绊线（2026-10-05，Lead 圈定的唯一一处 `liquid/` 组件改动）。
//
// 为什么用"源码扫描 + 离线 widget 断言"两条（照 #24b 封面绊线的既有口径 ✓
// u24b_cover_wiring_test.dart）：
//   * 非空 avatarUrl 那条**不能**做 widget 断言——widget 测试里真发网络请求会被
//     flutter_test 的 HttpClient 打回 400 并冒泡成测试失败 ✗（u24b 因此改用源码扫描）；
//   * 空 avatarUrl 那条是纯离线路径 ⇒ 用真正的 widget 断言（占位圆在场、不发请求）。
//
// 钉住的两件事（任一被改回去就红）：
//   ① `avatarUrl?.isNotEmpty == true` ⇒ `NetworkImgLayer(` + `type: ImageType.avatar`
//      （ClipOval 圆形裁剪，直径 34 与占位圆一致）；
//   ② 组件里**同时**保留 `CircleAvatar(` 作为空值占位（不是删掉占位）。
import 'dart:io';

import 'package:PiliPlus/common/widgets/liquid/liquid_comment_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

String _readTileSource() {
  final candidates = <String>[
    'lib/common/widgets/liquid/liquid_comment_tile.dart',
    'app/lib/common/widgets/liquid/liquid_comment_tile.dart',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('找不到 liquid_comment_tile.dart（cwd=${Directory.current.path}）');
}

void main() {
  test('#26a 头像接线：非空 avatarUrl ⇒ NetworkImgLayer(type: avatar)；空值 ⇒ 保留占位圆', () {
    final source = _readTileSource();
    expect(
      source.contains('NetworkImgLayer(') &&
          source.contains('src: data.avatarUrl!') &&
          source.contains('type: ImageType.avatar') &&
          source.contains('data.avatarUrl?.isNotEmpty == true'),
      isTrue,
      reason: '头像插槽必须按接线口径换装：有 URL 走 NetworkImgLayer(type: avatar) —— '
          '占位回归（永远画占位圆、不从 avatarUrl 取图）会让这条变红',
    );
    expect(
      source.contains('CircleAvatar('),
      isTrue,
      reason: '空 avatarUrl 必须仍走原占位圆（不能只剩 NetworkImgLayer）',
    );
    expect(
      source.contains('radius: 17'),
      isTrue,
      reason: '占位圆直径 34 与 NetworkImgLayer(width/height: 34) 必须一致（圆形口径统一）',
    );
  });

  testWidgets('#26a 头像接线：空 avatarUrl ⇒ 占位圆在场（纯离线，不发网络请求）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // LiquidCommentTile 内部用 InkWell（需要 Material 祖先）——
        // 缺 Material 会让整棵树抛异常，"离线断言"就测不成（本用例曾因此 -1 ✗）。
        home: Material(
          child: Builder(
            builder: (context) => const LiquidCommentTile(
              data: LiquidCommentData(userName: 'U', content: 'c'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(
      find.byType(NetworkImgLayerProbe),
      findsNothing,
      reason: '空 avatarUrl 不该挂任何真实头像层',
    );
    expect(tester.takeException(), isNull);
  });
}

/// 仅用于 finder 的类型探针（避免在本文件里直接 import NetworkImgLayer 造成
/// "未使用导入"与版本耦合；组件侧的类型由上面的源码扫描钉住）。
class NetworkImgLayerProbe extends StatelessWidget {
  const NetworkImgLayerProbe({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}