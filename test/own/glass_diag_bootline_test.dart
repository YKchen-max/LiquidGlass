// SPDX-License-Identifier: GPL-3.0-or-later
//
// M3 候选②「引导行常量断言」（排期登记的 5 分钟枪；commit 6cb8665 留账
// "引导行单测缺（可补常量断言）"——本文件即补账）。
//
// 钉什么：`[GlassDiag]` 启动自证行（手册 §103：dart-define 在产物上隐身 ⇒
// 门控必须启动一行自证）读的两个编译期门控常量的**出厂默认值**。
// 测试环境不带任何 --dart-define ⇒ 两常量必须恒 false：
//   * `glassFrameTimingEnabled == false` ⇒ install() 零注册、零分配、零回调；
//   * `glassKeepControlsEnabled == false` ⇒ 出厂路径控制条行为零影响。
// 这两条是"release 零行为"硬要求的外围防线（release 由 `!kReleaseMode` 折叠保证，
// 本测试保证的是**非 release 且未显式开启**时同样零行为——取证轮之外不偷跑）。
//
// 位置纪律：门禁第 3 项跑 `flutter test test/own`——没被门禁覆盖的测试等于没有测试。
import 'package:PiliPlus/debug/glass_frame_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('引导行常量断言：无 define ⇒ 门控恒 false（M3 候选②）', () {
    test('glassFrameTimingEnabled：无 GLASS_FRAME_TIMING define ⇒ false', () {
      expect(
        glassFrameTimingEnabled,
        isFalse,
        reason: '测试环境不带 --dart-define；若此断言红了，说明门控被改成了'
            '运行时开关或默认开启——出厂零行为被破，必须回退',
      );
    });

    test('glassKeepControlsEnabled：无 GLASS_KEEP_CONTROLS define ⇒ false', () {
      expect(
        glassKeepControlsEnabled,
        isFalse,
        reason: '常显控制条只许在取证轮由 dart-define 显式开启；'
            '默认恒 false ⇒ 出厂路径控制条显隐行为零影响',
      );
    });

    test('启动行读的 keepControls 与门控常量同源（防两处漂移）', () {
      // [GlassDiag] 启动行（pl_player view.dart）读 GlassFrameTimingDebug.keepControls；
      // 它必须是门控常量的**同一来源**（getter 转发），不许各算各的。
      expect(
        GlassFrameTimingDebug.keepControls,
        equals(glassKeepControlsEnabled),
        reason: '启动自证行报的值必须与真实门控一致，否则 §103 的'
            '"先读这行再读业务日志"会把排查带沟里',
      );
      expect(GlassFrameTimingDebug.keepControls, isFalse);
    });
  });
}
