// task-124 绊线：**播放器 key 契约**（wrap 路线的墓碑 ✓）。
//
// 背景（实机红屏实证 ✓✗✓）：`pl_player/view/view.dart:220` 有
//   `(widget.headerControl.key as GlobalKey<TimeBatteryMixin>).currentState`
// ⇒ `headerControl` 这个实参**必须**是 `HeaderControl` 本体（其 key 是
// `videoDetailController.headerCtrKey` ✓ `controller.dart:149` 定义 ✓）。
// 一旦有人在**装配处**把它包成任何 wrapper（Obx / LiquidHeaderGlass / …）✗，
// 该 cast 就拿到 null ⇒ 视频区红屏 ✗✗（2026-10-05 已真实发生一次 ✓）。
//
// 本绊线用**源文本扫描**钉死两件事 ✓：
//   1) cast 行仍在（契约还在 ✓ —— 若哪天播放器改成安全取值，这里也会红，提醒同步改口径 ✓）；
//   2) `pages/video/view.dart` 的 `headerControl:` 实参**没有被 wrapper 包** ✓。
// 这是 S15 绊线的同款口径：**用源码文本守住一条"只能靠人记住"的约束** ✓。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relative) {
  // 测试工作目录 = app/（flutter test 的约定 ✓）
  final f = File(relative);
  expect(f.existsSync(), isTrue, reason: '找不到 $relative（工作目录应为 app/）');
  return f.readAsStringSync();
}

void main() {
  group('播放器 key 契约绊线（wrap 路线已证伪 ✓）', () {
    test('player 侧仍以 GlobalKey<TimeBatteryMixin> 强转 headerControl.key ✓', () {
      final src = _read('lib/plugin/pl_player/view/view.dart');
      expect(
        src.contains(
          '(widget.headerControl.key as GlobalKey<TimeBatteryMixin>).currentState',
        ),
        isTrue,
        reason:
            '这句是"headerControl 必须是 HeaderControl 本体"的契约来源 ✓；'
            '若它被改掉，请同步更新本绊线与 #26b-2 的口径 ✓',
      );
    });

    test('装配处 headerControl 实参是 HeaderControl 本体、不是 wrapper ✓', () {
      final src = _read('lib/pages/video/view.dart');
      expect(
        src.contains('headerControl: HeaderControl('),
        isTrue,
        reason: '装配处必须直接传 HeaderControl（wrap 过就会红屏 ✗）',
      );
      for (final bad in <String>[
        'headerControl: Obx(',
        'headerControl: LiquidHeaderGlass(',
        'headerControl: KeyedSubtree(',
      ]) {
        expect(
          src.contains(bad),
          isFalse,
          reason: '发现 $bad ⇒ 又走回 wrap 路线了 ✗✗（会红屏：key=null）',
        );
      }
    });

    test('皮肤件是挂在 HeaderControl 的 build 内层 ✓（而非装配处）', () {
      final src = _read('lib/pages/video/widgets/header_control.dart');
      expect(
        src.contains('LiquidHeaderGlass('),
        isTrue,
        reason: '顶栏玻璃底应挂在 HeaderControl 自己的 build 里 ✓（task-124 裁定 ✓）',
      );
      expect(
        src.contains('visible: plPlayerController.showControls.value'),
        isTrue,
        reason: '显隐信号必须与播放器同源（showControls）✓',
      );
    });
  });
}
