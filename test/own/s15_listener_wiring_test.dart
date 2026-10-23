// SPDX-License-Identifier: GPL-3.0-or-later
//
// S15 绊线（2026-10-04 夜）：钉 showControls 监听注册行的存在与位置。
//
// 背景：6cb8665（task-114）误删
//   `_controlsListener = plPlayerController.showControls.listen(_onControlChanged);`
// ⇒ 嵌入态控制条整条不可见/不可点（P0；task-115"嵌入态不可见"与 M3① 同根；
//   证据链 `.probe/m1b54/REPORT.md`）。这类"删一行注册"的回归在 analyze/单测里
//   几乎无感（当夜只有一条 unused-element warning 淹没在噪声里 ⇒ 手册 §105），
//   故在**源码文本层**设绊线：再有人删/改这行，本用例当场红。
// 与门禁第 7 步"shader asset scan"同族（源码/资产层绊线 ✓）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S15 绊线：showControls 监听注册行存在（6cb8665 教训）', () {
    final src = File('lib/plugin/pl_player/view/view.dart').readAsStringSync();
    const registration =
        '_controlsListener = plPlayerController.showControls.listen(';
    expect(
      src.contains(registration),
      isTrue,
      reason: '缺这行 ⇒ _onControlChanged 永不调用 ⇒ forward() 永不执行 ⇒ '
          '控制条永停 AppBarAni 隐藏位移（嵌入态整条不可见/不可点，P0 S15）。'
          '若你有意移除：先读 .probe/m1b54/REPORT.md，并同时删除本绊线。',
    );
    // 注册必须先于 keepControls 引导块：引导块的 showControls=true
    // 要走这条监听才能驱动 forward（S15 修复时的落位纪律）。
    final regIdx = src.indexOf(registration);
    final bootIdx = src.indexOf('if (GlassFrameTimingDebug.keepControls)');
    expect(
      regIdx != -1 && bootIdx != -1 && regIdx < bootIdx,
      isTrue,
      reason: '监听注册必须在 keepControls 引导块之前，否则引导首显无驱动',
    );
  });
}
