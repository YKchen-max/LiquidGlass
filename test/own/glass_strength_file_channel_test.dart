// task-107（(B) 强度文件通道）的单元测试。
//
// 优先级（写死 ✓）：**env > 文件 > 测试接缝 > Pref > 默认(100)**；
// 文件通道 = **adb 取证用、非产品功能**，`!kReleaseMode` 门控，**读失败/非法一律静默回落** ✓。
//
// 本文件不初始化 GStorage（与既有 own 测试一致）⇒ "存储不可用" 天然覆盖"回落默认" ✓。
import 'dart:io' show File;

import 'package:PiliPlus/utils/glass_strength.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GlassStrength.debugReset);
  tearDown(GlassStrength.debugReset);

  group('文件通道：解析（纯函数）', () {
    test('合法值：0 / 50 / 100 / 带空白 ⇒ 原值', () {
      expect(GlassStrength.parseFilePercent('0', isRelease: false), 0);
      expect(GlassStrength.parseFilePercent('50', isRelease: false), 50);
      expect(GlassStrength.parseFilePercent('100', isRelease: false), 100);
      expect(GlassStrength.parseFilePercent(' 75 ', isRelease: false), 75);
    });

    test('非法值一律 -1（空 / null / 负 / >100 / 非数字）', () {
      expect(GlassStrength.parseFilePercent('', isRelease: false), -1);
      expect(GlassStrength.parseFilePercent(null, isRelease: false), -1);
      expect(GlassStrength.parseFilePercent('-5', isRelease: false), -1);
      expect(GlassStrength.parseFilePercent('101', isRelease: false), -1);
      expect(GlassStrength.parseFilePercent('abc', isRelease: false), -1);
      expect(GlassStrength.parseFilePercent('NaN', isRelease: false), -1);
      expect(GlassStrength.parseFilePercent('50.5', isRelease: false), -1);
    });

    test('release 恒不启用（同一份合法原文 ⇒ -1 ✓）', () {
      expect(GlassStrength.parseFilePercent('50', isRelease: true), -1);
      expect(GlassStrength.parseFilePercent('0', isRelease: true), -1);
    });
  });

  group('文件通道：优先级（env > 文件 > 接缝 > Pref > 默认）', () {
    test('文件 > 接缝（文件 40 + 接缝 90 ⇒ 40）', () {
      GlassStrength.debugFileRaw = '40';
      GlassStrength.debugStrengthPercent = 90;
      expect(GlassStrength.percent, 40);
    });

    test('env > 文件（env 10 + 文件 40 ⇒ 10）', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': '10'};
      GlassStrength.debugFileRaw = '40';
      expect(GlassStrength.percent, 10);
    });

    test('文件合法但越界 ⇒ 回落接缝（文件 101 + 接缝 30 ⇒ 30）', () {
      GlassStrength.debugFileRaw = '101';
      GlassStrength.debugStrengthPercent = 30;
      expect(GlassStrength.percent, 30);
    });

    test('文件为空 ⇒ 等价"没有文件" ⇒ 回落接缝/默认（接缝 null ⇒ 100）', () {
      GlassStrength.debugFileRaw = '';
      expect(GlassStrength.percent, 100);
      GlassStrength.debugStrengthPercent = 25;
      expect(GlassStrength.percent, 25);
    });

    test('无接缝无文件（生产测试环境：文件不存在）⇒ 默认 100 ✓', () {
      // debugFileRaw = null ⇒ 会去读真实路径；测试机上该路径不存在 ⇒ 静默 -1 ⇒ 默认 ✓
      expect(GlassStrength.percent, 100);
      expect(GlassStrength.strength, 1.0);
    });
  });

  group('§100 联动：文件值 ⇒ 折射层下限夹取', () {
    test('文件 = 0 ⇒ 强度 0 ⇒ thickness 走 0.5 下限（不是 0 ✗）', () {
      GlassStrength.debugFileRaw = '0';
      expect(GlassStrength.percent, 0);
      expect(GlassStrength.strength, 0.0);
      // 0% 的 token 厚度为 0 ⇒ 必须被下限兜住（否则 shader 里 0/0 ✗）
      expect(
        clampRefractionThickness(
          LiquidGlassTokens.light.forStrength(GlassStrength.strength).thickness,
          42.0,
        ),
        kMinRefractionThickness,
      );
    });

    test('文件 = 50 ⇒ thickness 缩放后再夹取（30→15，未触上限/下限 ✓）', () {
      GlassStrength.debugFileRaw = '50';
      final t = LiquidGlassTokens.light.forStrength(GlassStrength.strength);
      expect(clampRefractionThickness(t.thickness, 42.0), 15.0);
    });

    test('文件 = 100 ⇒ 与出厂一致（30 → 21 = h/2 既有夹取 ✓）', () {
      GlassStrength.debugFileRaw = '100';
      final t = LiquidGlassTokens.light.forStrength(GlassStrength.strength);
      expect(identical(t, LiquidGlassTokens.light), isTrue);
      expect(clampRefractionThickness(t.thickness, 42.0), 21.0);
    });
  });

  group('取证通道的边界安全', () {
    test('读失败不炸：路径不存在时 percent 仍能正常返回（静默回落 ✓）', () {
      expect(
        File(GlassStrength.evidenceFilePath).existsSync(),
        isFalse,
        reason: '测试机上该路径不应存在（这正是要覆盖的回落路径 ✓）',
      );
      expect(() => GlassStrength.percent, returnsNormally);
      expect(GlassStrength.percent, 100);
    });

    test('debugReset 清掉文件接缝（用例之间不串味 ✓）', () {
      GlassStrength.debugFileRaw = '40';
      expect(GlassStrength.percent, 40);
      GlassStrength.debugReset();
      expect(GlassStrength.percent, 100);
    });

    test('文件通道不影响 env（两者独立 ✓）', () {
      GlassStrength.debugFileRaw = '40';
      expect(GlassStrength.percent, 40);
      GlassStrength.environment = const {'GLASS_STRENGTH': '70'};
      expect(GlassStrength.percent, 70);
    });
  });
}
