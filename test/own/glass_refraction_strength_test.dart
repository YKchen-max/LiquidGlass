// task-104（DA：强度⇒折射层接线 + `h/2` 夹取）的单元测试。
//
// 三条不变量逐条钉死（§89/§93 家族：夹取类逻辑必须测**方向**）：
//   1. **上限只降不抬**：结果**永不超过** `h/2` ✓；
//   2. **数值下限**：结果**永不小于** `kMinRefractionThickness` ✓（thickness=0 会让 shader 除 0 ✗）；
//   3. **100% ⇒ 与接线前等价**：`forStrength(1.0)` 返回原对象 ✓，
//      且 `clampRefractionThickness(t, h)` 与接线前的 `math.min(t, h/2)` 在正常区间**逐值相同** ✓。
//
// 边界用例（本轮特意补的）：`thickness = h/2 ± ε` 两例 ＋ 只降不抬 ＋ 高度无意义（0/∞）。
import 'package:PiliPlus/utils/glass_strength.dart';

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('h/2 夹取：方向用例（边界必测）', () {
    test('thickness = h/2 ⇒ 原样（边界不收紧）', () {
      expect(clampRefractionThickness(21.0, 42.0), 21.0);
    });

    test('thickness = h/2 + ε ⇒ 夹到 h/2（上限生效 ✓）', () {
      expect(clampRefractionThickness(21.0 + 0.25, 42.0), 21.0);
    });

    test('thickness = h/2 − ε ⇒ 原样（不因为接近上限被改 ✓）', () {
      expect(
        clampRefractionThickness(21.0 - 0.25, 42.0),
        closeTo(20.75, 1e-12),
      );
    });

    test('远小于 h/2 ⇒ 原样（**只降不抬** ✓，不会"补"到 h/2）', () {
      expect(clampRefractionThickness(5.0, 42.0), 5.0);
    });

    test('不变量：任何输入下结果 ≤ max(h/2, 下限)', () {
      for (final h in <double>[0.0, 1.0, 42.0, 1000.0, double.infinity]) {
        for (final t in <double>[0.0, 0.1, 0.5, 5.0, 21.0, 500.0, -3.0]) {
          final out = clampRefractionThickness(t, h);
          final half = h / 2;
          expect(out.isFinite, isTrue);
          expect(out, greaterThanOrEqualTo(kMinRefractionThickness));
          if (half.isFinite && half > 0) {
            expect(out, lessThanOrEqualTo(half));
          }
        }
      }
    });

    test('高度无意义（0 / 负 / 非有限）⇒ 不设上限，但仍守住数值下限', () {
      expect(clampRefractionThickness(30.0, 0.0), 30.0);
      expect(clampRefractionThickness(30.0, -8.0), 30.0);
      expect(clampRefractionThickness(30.0, double.infinity), 30.0);
      expect(clampRefractionThickness(30.0, double.nan), 30.0);
    });

    test('数值下限：0 / 负数 / NaN ⇒ 顶到 kMinRefractionThickness（避免 shader 除 0 ✗）', () {
      expect(clampRefractionThickness(0.0, 42.0), kMinRefractionThickness);
      expect(clampRefractionThickness(-5.0, 42.0), kMinRefractionThickness);
      expect(
        clampRefractionThickness(double.nan, 42.0),
        kMinRefractionThickness,
      );
    });

    test('下限与上限冲突时（卡片极扁）上限优先 ⇒ 结果 = h/2', () {
      // h/2 = 0.2 < 下限 0.5 ⇒ 输出 0.2（承认这已经超出"数值有效"区间，但不许突破 h/2 ✗）
      expect(clampRefractionThickness(30.0, 0.4), 0.2);
    });

    test('真实控制条参数（h=42 逻辑、token.thickness=30）⇒ 21（与既有行为一致 ✓）', () {
      expect(
        clampRefractionThickness(LiquidGlassTokens.light.thickness, 42.0),
        21.0,
      );
    });
  });

  group('100% ⇒ 与接线前等价（硬要求）', () {
    test('forStrength(1.0) 返回**同一个对象**（连 copyWith 都不走 ✓）', () {
      final base = LiquidGlassTokens.light;
      expect(identical(base.forStrength(1.0), base), isTrue);
    });

    test('强度 100% 时，折射列取值与基准 token 逐项相同', () {
      final base = LiquidGlassTokens.light;
      final t = base.forStrength(1.0);
      expect(t.thickness, base.thickness);
      expect(t.refractiveIndex, base.refractiveIndex);
      expect(t.chromaticAberration, base.chromaticAberration);
      expect(t.lightIntensity, base.lightIntensity);
      expect(t.ambientStrength, base.ambientStrength);
      expect(t.saturation, base.saturation);
    });

    test('夹取规则与接线前的 math.min(t, h/2) 在正常区间逐值相同', () {
      final base = LiquidGlassTokens.dark;
      for (final h in <double>[20.0, 42.0, 60.0, 120.0, 264.0]) {
        final newRule = clampRefractionThickness(base.thickness, h);
        final oldRule = math.min(base.thickness, h / 2);
        final floorApplied = oldRule < kMinRefractionThickness;
        expect(
          newRule,
          floorApplied ? kMinRefractionThickness : oldRule,
          reason: 'h=$h：除"下限兜底"这一条新增保护外，必须与旧式完全一致 ✓',
        );
      }
    });
  });

  group('强度⇒折射列：走同一个缩放收口（不发明第二套 ✗）', () {
    test(
      '50% ⇒ thickness / chromaticAberration 减半，refractiveIndex 按 1+(n−1)s',
      () {
        final base = LiquidGlassTokens.light;
        final t = base.forStrength(0.5);
        expect(t.thickness, closeTo(base.thickness * 0.5, 1e-12));
        expect(
          t.chromaticAberration,
          closeTo(base.chromaticAberration * 0.5, 1e-12),
        );
        expect(
          t.refractiveIndex,
          closeTo(1 + (base.refractiveIndex - 1) * 0.5, 1e-12),
        );
      },
    );

    test('0% ⇒ 无折射语义（n=1.0、色散=0、厚度=0）⇒ 经夹取后仍 ≥ 数值下限', () {
      final t = LiquidGlassTokens.light.forStrength(0.0);
      expect(t.refractiveIndex, 1.0);
      expect(t.chromaticAberration, 0.0);
      expect(t.thickness, 0.0);
      expect(
        clampRefractionThickness(t.thickness, 42.0),
        kMinRefractionThickness,
        reason: '0% 的 0 厚度必须被下限兜住，否则 shader 里是 0/0 ✗',
      );
    });

    test('25 / 75% 的厚度列与五点表一致（单一来源 sampleAt ✓）', () {
      final base = LiquidGlassTokens.light;
      final table = GlassStrength.fivePointTable(base);
      for (final row in table) {
        final pct = row[0].toInt();
        if (pct == 0 || pct == 25 || pct == 50 || pct == 75 || pct == 100) {
          expect(
            row[5],
            base.forStrength(pct / 100).thickness,
            reason: 'sampleAt 的厚度列必须就是 forStrength 的结果（同一收口 ✓）',
          );
        }
      }
    });
  });

  group('与无障碍不打架（判据 (d)）', () {
    test('tierCap = solid ⇒ 档位不上升，接线不改变降档语义', () {
      LiquidGlassRuntime.tierCap = LiquidGlassTier.solid;
      addTearDown(() => LiquidGlassRuntime.tierCap = null);
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      // 折射层的参数装配不碰档位 ⇒ 即便强度=50%，"封顶"结论也不变 ✓
      final t = LiquidGlassTokens.light.forStrength(0.5);
      expect(
        clampRefractionThickness(t.thickness, 42.0),
        lessThanOrEqualTo(21.0),
      );
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
    });

    test('强度不改对比度保护（折射列缩放不影响 adaptiveLift/Darken ✓）', () {
      final base = LiquidGlassTokens.dark;
      final t = base.forStrength(0.5);
      expect(t.adaptiveLift, base.adaptiveLift);
      expect(t.adaptiveDarken, base.adaptiveDarken);
    });

    test('降低透明度（封顶 solid）时，强度滑杆仍可用（互不打架 ✓）', () {
      GlassStrength.debugStrengthPercent = 50;
      addTearDown(GlassStrength.debugReset);
      expect(GlassStrength.strength, 0.5);
      LiquidGlassRuntime.tierCap = LiquidGlassTier.solid;
      addTearDown(() => LiquidGlassRuntime.tierCap = null);
      // 两条语义正交：一条管档位、一条管旋钮 ✓
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      expect(
        LiquidGlassTokens.light.forStrength(GlassStrength.strength).thickness,
        closeTo(LiquidGlassTokens.light.thickness * 0.5, 1e-12),
      );
    });
  });
}
