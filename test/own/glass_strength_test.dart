// task-94（#19 玻璃强度滑杆 + 调试面板）的单元测试。
//
// 硬要求逐条钉死：
//   1. **默认 100% ⇒ 出厂行为不变**（`forStrength(1.0)` 必须**返回同一个对象** —— 最强形式的保证）；
//   2. **不改档位**（强度只缩放旋钮；档位仍由能力/策略/无障碍封顶 `cappedTier` 决定）；
//   3. **不缩放对比度保护**（`adaptiveLift/adaptiveDarken` 在任何强度下都不变 ⇒ 与 #18/task-9/12 不打架）；
//   4. **五点对照表**（0/25/50/75/100）由**同一个函数**产出（面板显示与单测断言同源 ✓）。
import 'package:PiliPlus/utils/glass_strength.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GlassStrength.debugReset);
  tearDown(() {
    GlassStrength.debugReset();
    LiquidGlassRuntime.tierCap = null;
  });

  group('forStrength：线性缩放与两端行为', () {
    test('100%（1.0）⇒ 返回**同一个对象**（出厂渲染逐字节不变的最强保证）', () {
      final base = LiquidGlassTokens.light;
      expect(identical(base.forStrength(1.0), base), isTrue);
    });

    test('>100%（例如 1.5）也按 100% 处理（返回原对象）', () {
      final base = LiquidGlassTokens.dark;
      expect(identical(base.forStrength(1.5), base), isTrue);
    });

    test('0%: blur / tintOpacity / 高光 / 厚度 / 色散 归零', () {
      final t = LiquidGlassTokens.light.forStrength(0);
      expect(t.blur, 0);
      expect(t.tintOpacity, 0);
      expect(t.highlightOpacity, 0);
      expect(t.thickness, 0);
      expect(t.chromaticAberration, 0);
      expect(t.shadowOpacity, 0);
      expect(t.ambientStrength, 0);
    });

    test('0%: 折射退回无折射（refractiveIndex = 1.0）、饱和度退回无增益（1.0）', () {
      final t = LiquidGlassTokens.dark.forStrength(0);
      expect(t.refractiveIndex, 1.0);
      expect(t.saturation, 1.0);
    });

    test('0%: 发丝保留下限（宽度 ≥0.5、α ≥0.25）—— 形状仍可辨', () {
      final t = LiquidGlassTokens.light.forStrength(0);
      expect(t.borderWidth, greaterThanOrEqualTo(0.5));
      expect(t.borderColor.a, greaterThanOrEqualTo(0.25));
    });

    test('25%: 各旋钮为 0.25 倍（blur）', () {
      final base = LiquidGlassTokens.light;
      final t = base.forStrength(0.25);
      expect(t.blur, closeTo(base.blur * 0.25, 1e-12));
    });

    test('50%: 各旋钮为 0.5 倍（tintOpacity / 高光 / 厚度）', () {
      final base = LiquidGlassTokens.dark;
      final t = base.forStrength(0.5);
      expect(t.tintOpacity, closeTo(base.tintOpacity * 0.5, 1e-12));
      expect(t.highlightOpacity, closeTo(base.highlightOpacity * 0.5, 1e-12));
      expect(t.thickness, closeTo(base.thickness * 0.5, 1e-12));
    });

    test('75%: 各旋钮为 0.75 倍（blur / 环境光 / 阴影）', () {
      final base = LiquidGlassTokens.light;
      final t = base.forStrength(0.75);
      expect(t.blur, closeTo(base.blur * 0.75, 1e-12));
      expect(t.ambientStrength, closeTo(base.ambientStrength * 0.75, 1e-12));
      expect(t.shadowOpacity, closeTo(base.shadowOpacity * 0.75, 1e-12));
    });

    test('refractiveIndex 按「距 1.0 的增量」缩放（0% ⇒ 1.0，100% ⇒ 原值）', () {
      final base = LiquidGlassTokens.dark; // n = 1.21
      expect(base.forStrength(0).refractiveIndex, 1.0);
      expect(
        base.forStrength(0.5).refractiveIndex,
        closeTo(1 + (base.refractiveIndex - 1) * 0.5, 1e-12),
      );
      expect(
        base.forStrength(0.999).refractiveIndex,
        closeTo(1 + (base.refractiveIndex - 1) * 0.999, 1e-12),
      );
    });

    test('饱和度为 1.0 时任何强度都不变（无增益不产生负增益）', () {
      final flat = LiquidGlassTokens.light.copyWith(saturation: 1.0);
      expect(flat.forStrength(0.0).saturation, 1.0);
      expect(flat.forStrength(0.5).saturation, 1.0);
    });

    test('负强度按 0 处理（不产生负值旋钮）', () {
      final t = LiquidGlassTokens.light.forStrength(-0.5);
      expect(t.blur, 0);
      expect(t.tintOpacity, 0);
    });

    test('单调：强度越大，blur / tintOpacity / 厚度 不减', () {
      final base = LiquidGlassTokens.light;
      var prevBlur = -1.0;
      for (final s in <double>[0, 0.25, 0.5, 0.75, 1.0]) {
        final t = base.forStrength(s);
        expect(t.blur, greaterThanOrEqualTo(prevBlur));
        prevBlur = t.blur;
      }
    });

    test('thickness 缩放后仍非负（几何侧另有 h/2 夹取）', () {
      for (final s in <double>[0, 0.25, 0.5, 0.75, 1.0]) {
        expect(
          LiquidGlassTokens.dark.forStrength(s).thickness,
          greaterThanOrEqualTo(0),
        );
      }
    });

    test('不改方向类参数：lightAngle 恒定', () {
      final base = LiquidGlassTokens.light;
      for (final s in <double>[0, 0.5, 1.0]) {
        expect(base.forStrength(s).lightAngle, base.lightAngle);
      }
    });

    test('不改 tint 颜色本身（只缩放它的 α）', () {
      final base = LiquidGlassTokens.light;
      expect(base.forStrength(0.5).tint, base.tint);
    });
  });

  group('与 #18 不打架：强度不动档位、也不撤掉对比度保护', () {
    test('强度不改变 adaptiveLift / adaptiveDarken（0% 也一样）', () {
      for (final base in <LiquidGlassTokens>[
        LiquidGlassTokens.light,
        LiquidGlassTokens.dark,
      ]) {
        for (final s in <double>[0, 0.25, 0.5, 0.75, 1.0]) {
          final t = base.forStrength(s);
          expect(
            t.adaptiveLift,
            base.adaptiveLift,
            reason: '对比度保护属无障碍语义（task-9/12/93），不能被「强度」缩放 ✗',
          );
          expect(t.adaptiveDarken, base.adaptiveDarken);
        }
      }
    });

    test('降透明封顶 solid 时，强度仍作用于 solid 档（档位不变、旋钮变）', () {
      LiquidGlassRuntime.tierCap = LiquidGlassTier.solid;
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      final scaled = LiquidGlassTokens.light.forStrength(0.5);
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
        reason: '强度只缩放旋钮，不会把封顶解除 ✗',
      );
      expect(scaled.blur, closeTo(LiquidGlassTokens.light.blur * 0.5, 1e-12));
    });

    test('组合顺序 forStrength → forIncreasedContrast：强对比下限仍生效', () {
      final t = LiquidGlassTokens.light.forStrength(0.2).forIncreasedContrast();
      expect(t.borderWidth, greaterThanOrEqualTo(1.2));
      expect(t.adaptiveDarken, greaterThanOrEqualTo(0.50));
      expect(t.adaptiveLift, greaterThanOrEqualTo(0.30));
    });

    test('反向组合（先强对比再缩放）会削弱保护 ⇒ 单一收口把顺序定死', () {
      final t = LiquidGlassTokens.light.forIncreasedContrast().forStrength(0.2);
      expect(
        t.borderWidth,
        lessThan(1.2),
        reason: '这正是 kit 里把顺序写成 forStrength → forIncreasedContrast 的原因之一',
      );
      expect(
        t.adaptiveDarken,
        greaterThanOrEqualTo(0.50),
        reason: '对比度旋钮本身不参与缩放，所以这条不受顺序影响 ✓',
      );
    });
  });

  group('强度解析：环境变量 > 接缝 > Pref > 出厂默认 100', () {
    test('存储未就绪 ⇒ 100%（不抛）', () {
      expect(GlassStrength.percent, 100);
      expect(GlassStrength.strength, 1.0);
    });

    test('接缝 0 ⇒ 0.0', () {
      GlassStrength.debugStrengthPercent = 0;
      expect(GlassStrength.percent, 0);
      expect(GlassStrength.strength, 0.0);
    });

    test('接缝 50 ⇒ 0.5', () {
      GlassStrength.debugStrengthPercent = 50;
      expect(GlassStrength.strength, 0.5);
    });

    test('接缝越界会被夹到 0..100', () {
      GlassStrength.debugStrengthPercent = 500;
      expect(GlassStrength.percent, 100);
      GlassStrength.debugStrengthPercent = -20;
      expect(GlassStrength.percent, 0);
    });

    test('env="25" ⇒ 25', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': '25'};
      expect(GlassStrength.percent, 25);
    });

    test('env 带空白也能解析（" 75 "）', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': ' 75 '};
      expect(GlassStrength.percent, 75);
    });

    test('env 非法值被忽略 ⇒ 退回下一优先级（接缝）', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': 'abc'};
      GlassStrength.debugStrengthPercent = 40;
      expect(GlassStrength.percent, 40);
    });

    test('env 越界被忽略（"101"）', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': '101'};
      GlassStrength.debugStrengthPercent = 40;
      expect(GlassStrength.percent, 40);
    });

    test('env 优先于接缝（env=10 + 接缝=90 ⇒ 10）', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': '10'};
      GlassStrength.debugStrengthPercent = 90;
      expect(GlassStrength.percent, 10);
    });

    test('syncRuntimeFlags：默认 100 ⇒ kit 强度 1.0（出厂不变）', () {
      GlassStrength.syncRuntimeFlags();
      expect(LiquidGlassRuntime.strength, 1.0);
    });

    test('syncRuntimeFlags：50 ⇒ kit 强度 0.5', () {
      GlassStrength.debugStrengthPercent = 50;
      GlassStrength.syncRuntimeFlags();
      expect(LiquidGlassRuntime.strength, 0.5);
    });

    test('syncRuntimeFlags：env=0 ⇒ kit 强度 0.0', () {
      GlassStrength.environment = const {'GLASS_STRENGTH': '0'};
      GlassStrength.syncRuntimeFlags();
      expect(LiquidGlassRuntime.strength, 0.0);
    });
  });

  group('五点对照表（单一来源：面板与单测同调一个函数）', () {
    test('返回 5 行（0/25/50/75/100）', () {
      final table = GlassStrength.fivePointTable(LiquidGlassTokens.light);
      expect(table.length, 5);
      expect(table.map((r) => r[0].toInt()).toList(), <int>[
        0,
        25,
        50,
        75,
        100,
      ]);
    });

    test('blur 列线性（light：8 → 0/2/4/6/8）', () {
      final base = LiquidGlassTokens.light;
      final col = GlassStrength.fivePointTable(base).map((r) => r[1]).toList();
      expect(col, <double>[
        0,
        base.blur * 0.25,
        base.blur * 0.5,
        base.blur * 0.75,
        base.blur,
      ]);
    });

    test('最后一行（100%）与基准 token 完全一致（默认不变）', () {
      final base = LiquidGlassTokens.dark;
      final last = GlassStrength.fivePointTable(base).last;
      expect(last[1], base.blur);
      expect(last[2], base.tintOpacity);
      expect(last[3], base.highlightOpacity);
      expect(last[4], base.borderWidth);
      expect(last[5], base.thickness);
      expect(last[6], base.refractiveIndex);
      expect(last[7], base.chromaticAberration);
    });

    test('第一行（0%）满足最弱语义（blur/thickness/色散 = 0，折射率 = 1.0）', () {
      final first = GlassStrength.fivePointTable(LiquidGlassTokens.light).first;
      expect(first[1], 0); // blur
      expect(first[5], 0); // thickness
      expect(first[6], 1.0); // refractiveIndex
      expect(first[7], 0); // chromaticAberration
    });

    test('发丝列有下限（0% 行 ≥0.5）', () {
      final first = GlassStrength.fivePointTable(LiquidGlassTokens.dark).first;
      expect(first[4], greaterThanOrEqualTo(0.5));
    });
  });
}
