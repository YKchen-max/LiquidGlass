// #11 / M1a 测试③：**端口对既有 FakeGlass 路径零影响**（决策 3 的另一半）+ 决策 1 的守卫。
//
// 为什么用"结构/行为断言"而不是把源码哈希写进测试：FakeGlass 路径的**像素锚点**
// （整图 `6a87cd67…` / 客户区 `ea15bc07…`）是**宿主 App 级**证据，需要起 App 抓图；
// 而本任务是"管线入库、不接页面"，所以这里用**更强也更便宜**的替代：
//   * 既有 material 源文件**不引用折射模块**（端口确实没接进老路径 ✓）；
//   * kit 既有行为测试继续绿（FakeGlass 仍挂 BackdropFilter 等 ✓，见本套件其余文件）；
//   * `pubspec.yaml` **没有 `shaders:` 真键**、且 4 个 `.iplr` 作为普通 assets 声明 ✓
//     （决策 1 的守卫：谁手滑把 .frag 放进 `shaders:`，Windows 构建就会整块坏 ✗）；
//   * 端口前后 materials 源文件的 SHA256 清单落在 `.probe/m1-port/kit-materials-sha256.json` ✓
//     （**不写进测试**：那会变成自指的锁 —— 期望值只能在端口后生成 ✗）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('端口零影响（纯增量）', () {
    test('既有 material 源文件不 import 折射模块 ⇒ 端口没接进老路径', () {
      final dir = Directory('lib/src/materials');
      for (final f in dir.listSync().whereType<File>()) {
        final src = f.readAsStringSync();
        expect(src.contains('/refraction/'), isFalse,
            reason: '${f.path} 引用了折射模块 —— M1a 明确"不接页面/不改既有行为" ✗');
      }
    });

    test('折射模块只被 barrel 导出，不被任何既有 materials 文件引用（同上，方向相反）', () {
      final barrel = File('lib/liquid_glass_kit.dart').readAsStringSync();
      expect(barrel.contains('src/refraction/'), isTrue,
          reason: '新增模块必须从 barrel 可见（否则 M1b 接不进来）');
      // 源码级证据：materials 目录里出现 refraction 字样即视为"已接入"，本任务不允许 ✗
      final offender = Directory('lib/src/materials')
          .listSync()
          .whereType<File>()
          .where((f) => f.readAsStringSync().contains('refraction_assets'))
          .toList();
      expect(offender, isEmpty);
    });

    // 说明：**没有**做"materials 文件哈希锁定"式的测试 ✗ —— 那会是一个自指的锁
    // （期望值只能在端口后生成），而且它并不比"行为测试"更强。真正的零影响证据是：
    //   * kit 既有行为测试（本套件里"FakeGlass 档确实挂了 BackdropFilter"等）继续绿 ✓；
    //   * 端口前 materials 源文件的 SHA256 清单（端口后逐项复核，见
    //     `.probe/m1-port/kit-materials-sha256.json`）✓；
    //   * M1b 接页面时再取**宿主 App 级像素锚点**（整图 6a87cd67… / 客户区 ea15bc07…）✓。
  });

  group('决策 1 守卫：折射 shader 绝不进 `shaders:` 构建期块', () {
    test('pubspec：无 shaders: 块，且 4 个 .iplr 走普通 assets', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      // 只看**真 YAML 键**（行首缩进后的 `shaders:`），不看注释 ✗ ——
      // 我自己的说明注释里就写了 "shaders: 构建期块" 字样，用 contains 会被自己骗 ✓。
      final liveKey = RegExp(r'^\s*shaders:\s*$', multiLine: true);
      expect(liveKey.hasMatch(pubspec), isFalse,
          reason: 'shaders: 会触发 impellerc 编译 SkSL ⇒ Windows 构建必失败（#8 已证）✗');
      expect(pubspec.contains('#') && pubspec.contains('shaders:'), isTrue,
          reason: '注释里说明这条纪律是**期望**的（说明留在 pubspec 里便于接线人看到）');
      for (final name in <String>[
        'liquid_glass_geometry_blended',
        'liquid_glass_filter',
        'liquid_glass_final_render',
        'liquid_glass_arbitrary',
      ]) {
        expect(pubspec.contains('lib/assets/shaders/$name.iplr'), isTrue,
            reason: '$name.iplr 没被声明为资产 ⇒ 运行时 fromAsset 找不到 ✗');
      }
    });

    test('4 个 .iplr 资产确实在盘上，且 magic 是 IPLR（不是被误当成源文件）', () {
      for (final shader in LiquidGlassRefractionShader.values) {
        final f = File('lib/assets/shaders/${shader.fileName}');
        expect(f.existsSync(), isTrue, reason: shader.fileName);
        final head = f.readAsBytesSync().sublist(0, 8);
        // 头部含 'IPLR' magic（前 4 字节是容器长度，紧随其后是 IPLR）✓
        final marker = String.fromCharCodes(head.where((b) => b >= 32 && b < 127));
        expect(marker.contains('IPLR'), isTrue,
            reason: '${shader.fileName} 不是 .iplr 容器（magic=$marker）');
      }
    });
  });

  group('决策 3：绘制顺序纪律可断言', () {
    test('顺序正确时不抛', () {
      LiquidGlassPaintOrder.debugAssertBackdropBeforeGlass(
          backdropIndex: 0, glassIndex: 1);
    });

    test('顺序写反时 debug 下抛（M0 的坑：反了不报错、只表现为"看不见"✗）', () {
      expect(
        () => LiquidGlassPaintOrder.debugAssertBackdropBeforeGlass(
            backdropIndex: 3, glassIndex: 1, context: 'test'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('checkInChildren 能按下标判定，并对"不在同一列表"给出提示', () {
      final backdrop = Object();
      final glass = Object();
      expect(
        () => LiquidGlassPaintOrder.checkInChildren(
            children: <Object?>[backdrop, glass], backdrop: backdrop, glass: glass),
        returnsNormally,
      );
      expect(
        () => LiquidGlassPaintOrder.checkInChildren(
            children: <Object?>[glass, backdrop], backdrop: backdrop, glass: glass),
        throwsA(isA<AssertionError>()),
      );
      // 不在同一列表：跳过（不误报）✓
      expect(
        () => LiquidGlassPaintOrder.checkInChildren(
            children: <Object?>[backdrop], backdrop: backdrop, glass: glass),
        returnsNormally,
      );
      expect(LiquidGlassPaintOrder.contract, contains('玻璃必须排在其 backdrop 之后'));
    });
  });
}
