// task-93（#18 无障碍映射）的单元测试：三个自建开关 + Windows 高对比度主题。
//
// 位置：`test/own/` —— 门禁第 3 项跑的就是 `flutter test test/own`（没被门禁覆盖的测试等于没有测试）。
//
// 三条安全关键的纪律，这里逐条钉死：
//   1. **默认全关 ⇒ 行为不变**（关时 `capTier`/`motionDuration` 必须"原样返回"）；
//   2. **只降不升**（"降低透明度"封顶到 solid，绝不可能抬档 ⇒ 不可能绕过能力矩阵）；
//   3. **传递路径可信**（环境变量/接缝/Pref 的优先级；存储未就绪时按关，且**不抛**）。
//
// 注意：本文件**不初始化 GStorage**（与既有 `liquid_glass_policy_test.dart` 一致）——
// 这恰好也是"存储不可用 ⇒ 出厂默认"这条的实测口径 ✓。
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/liquid_glass_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

LiquidGlassCapability _cap(LiquidGlassTier tier) => LiquidGlassCapability(
  tier: tier,
  platform: 'windows',
  osVersion: 'test',
  shaderFilterSupported: false,
  reason: 'unit test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GlassAccessibility.debugReset);
  tearDown(() {
    GlassAccessibility.debugReset();
    LiquidGlassRuntime.overrideForTest(null);
  });

  // ─────────────────────────────────── 组 A：封顶只降不升
  group('capTier：降低透明度 ⇒ 封顶到 solid（只降不升）', () {
    test('关：三个档位原样返回（出厂行为不变）', () {
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.refraction),
        LiquidGlassTier.refraction,
      );
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.fakeGlass,
      );
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.solid),
        LiquidGlassTier.solid,
      );
    });

    test('开：refraction ⇒ solid', () {
      GlassAccessibility.debugReduceTransparency = true;
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
    });

    test('开：fakeGlass ⇒ solid', () {
      GlassAccessibility.debugReduceTransparency = true;
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
      );
    });

    test('开：solid ⇒ solid（不会变成别的档）', () {
      GlassAccessibility.debugReduceTransparency = true;
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.solid),
        LiquidGlassTier.solid,
      );
    });

    test('开：绝不抬档 —— 输入已是 solid 时输出仍是 solid', () {
      GlassAccessibility.debugReduceTransparency = true;
      final out = GlassAccessibility.capTier(LiquidGlassTier.solid);
      expect(
        out.index,
        LiquidGlassTier.solid.index,
        reason: '封顶器只能往下压；若把 index 变小就是把档位抬回去了',
      );
    });

    test('来回切换两次：状态与结果一致（无粘滞）', () {
      GlassAccessibility.debugReduceTransparency = false;
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.fakeGlass,
      );
      GlassAccessibility.debugReduceTransparency = true;
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
      );
      GlassAccessibility.debugReduceTransparency = false;
      expect(
        GlassAccessibility.capTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.fakeGlass,
      );
    });
  });

  // ─────────────────────────────────── 组 B：动效时长
  group('motionDuration：减弱动效 ⇒ 0（阶跃）', () {
    test('关：原样返回 base（200ms）', () {
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 200)),
        const Duration(milliseconds: 200),
      );
    });

    test('开：归零', () {
      GlassAccessibility.debugReduceMotion = true;
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 200)),
        Duration.zero,
      );
    });

    test('关：base 本身是 0 时仍为 0', () {
      expect(GlassAccessibility.motionDuration(Duration.zero), Duration.zero);
    });

    test('开：任意 base（1ms / 2s）都归零', () {
      GlassAccessibility.debugReduceMotion = true;
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 1)),
        Duration.zero,
      );
      expect(
        GlassAccessibility.motionDuration(const Duration(seconds: 2)),
        Duration.zero,
      );
    });

    test('开：与 base 的取值无关（同一结果）', () {
      GlassAccessibility.debugReduceMotion = true;
      final a = GlassAccessibility.motionDuration(
        const Duration(milliseconds: 200),
      );
      final b = GlassAccessibility.motionDuration(
        const Duration(milliseconds: 999),
      );
      expect(a, b);
    });

    test('关：返回的 Duration 与 base 相等（逐字段）', () {
      const base = Duration(milliseconds: 200, microseconds: 7);
      final out = GlassAccessibility.motionDuration(base);
      expect(out.inMicroseconds, base.inMicroseconds);
    });
  });

  // ─────────────────────────────────── 组 C：增强对比的「或」语义（含 Windows 高对比度）
  group('increaseContrast：自建开关 或 系统高对比度（testWidgets）', () {
    testWidgets('自建关 + 系统关 ⇒ 假', (tester) async {
      GlassAccessibility.debugIncreaseContrastSwitch = false;
      late bool got;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: false),
          child: Builder(
            builder: (c) {
              got = GlassAccessibility.increaseContrast(c);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(got, isFalse);
    });

    testWidgets('自建开 + 系统关 ⇒ 真', (tester) async {
      GlassAccessibility.debugIncreaseContrastSwitch = true;
      late bool got;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: false),
          child: Builder(
            builder: (c) {
              got = GlassAccessibility.increaseContrast(c);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(got, isTrue);
    });

    testWidgets('自建关 + 系统开（Windows 高对比度）⇒ 真', (tester) async {
      GlassAccessibility.debugIncreaseContrastSwitch = false;
      late bool got;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: Builder(
            builder: (c) {
              got = GlassAccessibility.increaseContrast(c);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(got, isTrue, reason: '系统高对比度主题必须被 honor，不需要用户再开一次');
    });

    testWidgets('自建开 + 系统开 ⇒ 真（或关系不冲突）', (tester) async {
      GlassAccessibility.debugIncreaseContrastSwitch = true;
      late bool got;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: Builder(
            builder: (c) {
              got = GlassAccessibility.increaseContrast(c);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(got, isTrue);
    });

    testWidgets('系统开时用户在设置里关掉 ⇒ 仍为真（系统级设置不可被应用关掉）', (tester) async {
      GlassAccessibility.debugIncreaseContrastSwitch = false;
      late bool got;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: Builder(
            builder: (c) {
              got = GlassAccessibility.increaseContrast(c);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(got, isTrue);
    });
  });

  // ─────────────────────────────────── 组 D：取值优先级与鲁棒性
  group('取值传递：环境变量 > 接缝 > Pref > 出厂默认', () {
    test('存储未就绪 ⇒ 三个开关都是假（且不抛）', () {
      expect(GlassAccessibility.reduceTransparency, isFalse);
      expect(GlassAccessibility.reduceMotion, isFalse);
      expect(GlassAccessibility.increaseContrastSwitch, isFalse);
    });

    test('env="true" ⇒ 真', () {
      GlassAccessibility.environment = const {
        'GLASS_A11Y_REDUCE_TRANSPARENCY': 'true',
      };
      expect(GlassAccessibility.reduceTransparency, isTrue);
    });

    test('env="1" ⇒ 真', () {
      GlassAccessibility.environment = const {
        'GLASS_A11Y_REDUCE_TRANSPARENCY': '1',
      };
      expect(GlassAccessibility.reduceTransparency, isTrue);
    });

    test('env="yes" ⇒ 假（只认字面量 true/1，§18.82 同规矩）', () {
      GlassAccessibility.environment = const {
        'GLASS_A11Y_REDUCE_TRANSPARENCY': 'yes',
      };
      expect(GlassAccessibility.reduceTransparency, isFalse);
    });

    test('env="false" ⇒ 假', () {
      GlassAccessibility.environment = const {
        'GLASS_A11Y_REDUCE_TRANSPARENCY': 'false',
      };
      expect(GlassAccessibility.reduceTransparency, isFalse);
    });

    test('env 大小写敏感（"TRUE" ⇒ 假）', () {
      GlassAccessibility.environment = const {
        'GLASS_A11Y_REDUCE_TRANSPARENCY': 'TRUE',
      };
      expect(GlassAccessibility.reduceTransparency, isFalse);
    });

    test('env 优先于接缝（env=true + 接缝=false ⇒ 真）', () {
      GlassAccessibility.environment = const {'GLASS_A11Y_REDUCE_MOTION': '1'};
      GlassAccessibility.debugReduceMotion = false;
      expect(GlassAccessibility.reduceMotion, isTrue);
    });

    test('env 逐个开关独立：设 MOTION 不影响 TRANSPARENCY', () {
      GlassAccessibility.environment = const {'GLASS_A11Y_REDUCE_MOTION': '1'};
      expect(GlassAccessibility.reduceMotion, isTrue);
      expect(GlassAccessibility.reduceTransparency, isFalse);
    });

    test('env 逐个开关独立：设 MOTION 不影响 CONTRAST', () {
      GlassAccessibility.environment = const {'GLASS_A11Y_REDUCE_MOTION': '1'};
      expect(GlassAccessibility.increaseContrastSwitch, isFalse);
    });

    test('env 逐个开关独立：设 CONTRAST 不影响 TRANSPARENCY', () {
      GlassAccessibility.environment = const {'GLASS_A11Y_CONTRAST': '1'};
      expect(GlassAccessibility.increaseContrastSwitch, isTrue);
      expect(GlassAccessibility.reduceTransparency, isFalse);
    });
  });

  // ─────────────────────────────────── 组 E：syncRuntimeFlags 与 kit 侧 token
  group('syncRuntimeFlags 与 kit token 强制值', () {
    test('默认：kit 标志为假（出厂不变）', () {
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.increaseContrast, isFalse);
    });

    test('接缝开 ⇒ 同步后 kit 标志为真', () {
      GlassAccessibility.debugIncreaseContrastSwitch = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.increaseContrast, isTrue);
    });

    test('接缝关 ⇒ 同步后 kit 标志为假', () {
      GlassAccessibility.debugIncreaseContrastSwitch = false;
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.increaseContrast, isFalse);
    });

    test('env 开 ⇒ 同步后 kit 标志为真', () {
      GlassAccessibility.environment = const {'GLASS_A11Y_CONTRAST': 'true'};
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.increaseContrast, isTrue);
    });

    test('light token：压暗量抬到 ≥0.50', () {
      final t = LiquidGlassTokens.light.forIncreasedContrast();
      expect(t.adaptiveDarken, greaterThanOrEqualTo(0.50));
      expect(
        LiquidGlassTokens.light.adaptiveDarken,
        lessThan(0.50),
        reason: '这条测试要有意义，前提是原值低于下限',
      );
    });

    test('light token：发丝加粗到 ≥1.2', () {
      expect(
        LiquidGlassTokens.light.forIncreasedContrast().borderWidth,
        greaterThanOrEqualTo(1.2),
      );
    });

    test('light token：发丝不透明度抬到 ≥0.55', () {
      expect(
        LiquidGlassTokens.light.forIncreasedContrast().borderColor.a,
        greaterThanOrEqualTo(0.55),
      );
    });

    test('dark token：抬升量提到 ≥0.30', () {
      final t = LiquidGlassTokens.dark.forIncreasedContrast();
      expect(t.adaptiveLift, greaterThanOrEqualTo(0.30));
      expect(LiquidGlassTokens.dark.adaptiveLift, lessThan(0.30));
    });

    test('dark token：压暗量提到 ≥0.50', () {
      expect(
        LiquidGlassTokens.dark.forIncreasedContrast().adaptiveDarken,
        greaterThanOrEqualTo(0.50),
      );
    });

    test('dark token：发丝加粗到 ≥1.2', () {
      expect(
        LiquidGlassTokens.dark.forIncreasedContrast().borderWidth,
        greaterThanOrEqualTo(1.2),
      );
    });

    test('只抬不降：已强于下限的取值不被下调', () {
      final strong = LiquidGlassTokens.light.copyWith(adaptiveDarken: 0.9);
      expect(strong.forIncreasedContrast().adaptiveDarken, 0.9);
    });

    test('不改其它字段：blur / saturation / tint 保持不变', () {
      final base = LiquidGlassTokens.light;
      final forced = base.forIncreasedContrast();
      expect(forced.blur, base.blur);
      expect(forced.saturation, base.saturation);
      expect(forced.tint, base.tint);
      expect(forced.tintOpacity, base.tintOpacity);
      expect(forced.lightIntensity, base.lightIntensity);
    });

    test('不改其它字段：lightAngle / shadowOpacity / thickness 保持不变', () {
      final base = LiquidGlassTokens.dark;
      final forced = base.forIncreasedContrast();
      expect(forced.lightAngle, base.lightAngle);
      expect(forced.shadowOpacity, base.shadowOpacity);
      expect(forced.thickness, base.thickness);
    });
  });

  // ─────────────────────────────────── 组 F：与策略层的集成
  group('与 LiquidGlassPolicy 集成（封顶发生在能力夹取之后）', () {
    test('关：与旧行为一致（runtime=fakeGlass + 策略要折射 ⇒ fakeGlass）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.fakeGlass,
      );
    });

    test('开：即使 runtime 允许折射，也被封顶到 solid', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.refraction));
      GlassAccessibility.debugReduceTransparency = true;
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
    });

    test('开：runtime 已是 solid 时仍为 solid（不抬档、不报错）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.solid));
      GlassAccessibility.debugReduceTransparency = true;
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
      );
    });

    test('关：runtime 是 solid 时策略要玻璃也拿 solid（既有纪律未被破坏）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.solid));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
      );
    });

    test('组合不打架 1：降透明 + 强对比同开 ⇒ 档位 solid 且 token 被强制', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.refraction));
      GlassAccessibility.debugReduceTransparency = true;
      GlassAccessibility.debugIncreaseContrastSwitch = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      expect(LiquidGlassRuntime.increaseContrast, isTrue);
      expect(
        LiquidGlassTokens.light.forIncreasedContrast().borderWidth,
        greaterThanOrEqualTo(1.2),
      );
    });

    test('组合不打架 2：降透明 + 减动效同开 ⇒ solid 且时长为 0', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.refraction));
      GlassAccessibility.debugReduceTransparency = true;
      GlassAccessibility.debugReduceMotion = true;
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 200)),
        Duration.zero,
      );
    });

    test('组合不打架 3：减动效 + 强对比同开 ⇒ 时长 0 且 kit 标志为真', () {
      GlassAccessibility.debugReduceMotion = true;
      GlassAccessibility.debugIncreaseContrastSwitch = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 200)),
        Duration.zero,
      );
      expect(LiquidGlassRuntime.increaseContrast, isTrue);
    });

    test('组合不打架 4：三开关同开 ⇒ 三条语义同时成立', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.refraction));
      GlassAccessibility.debugReduceTransparency = true;
      GlassAccessibility.debugReduceMotion = true;
      GlassAccessibility.debugIncreaseContrastSwitch = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 200)),
        Duration.zero,
      );
      expect(LiquidGlassRuntime.increaseContrast, isTrue);
    });

    test('组合不打架 5：全关 ⇒ 三条都回到出厂语义', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.fakeGlass,
      );
      expect(
        GlassAccessibility.motionDuration(const Duration(milliseconds: 200)),
        const Duration(milliseconds: 200),
      );
      expect(LiquidGlassRuntime.increaseContrast, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 全局档位封顶（Lead 补，task-93 的实测发现 ✓）：
  //   **app chrome（侧栏/顶栏/底导）走的是 kit 的全局 `LiquidGlassRuntime.tier`** ✓，
  //   而 `LiquidGlassPolicy.effectiveTier` 只覆盖播放器/直播两条路径 ✗ ⇒
  //   只封后者时**侧栏不受"降低透明度"影响** ✗（作者临死前正是卡在这一步）。
  //   另一处更隐蔽：`LiquidGlassSurface` 用的是 `cap?.tier`（= 局部覆盖 ?? 全局能力 ⇒
  //   **几乎总是非空** ⇒ **原始**能力档位 ✗）⇒ **绕过 getter** ✗ ⇒ 必须走 `cappedTier` ✓。
  // ---------------------------------------------------------------------------
  group('全局档位封顶（app chrome 那条路径）', () {
    test('关：全局 tier 与能力一致；cappedTier 原样返回（出厂不变）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      expect(LiquidGlassRuntime.tier, LiquidGlassTier.fakeGlass);
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.refraction),
        LiquidGlassTier.refraction,
      );
    });

    test('开：全局 tier 封顶到 solid；**原始档位输入**也被封（surface 旁路 ✓）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      GlassAccessibility.debugReduceTransparency = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.tier, LiquidGlassTier.solid);
      // surface 取的就是"原始能力档位"⇒ 必须经 cappedTier 才被封 ✓
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
      expect(
        LiquidGlassRuntime.cappedTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
      );
    });

    test('开：能力已是 solid ⇒ 仍 solid（只降不抬、不报错）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.solid));
      GlassAccessibility.debugReduceTransparency = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.tier, LiquidGlassTier.solid);
    });

    test('关掉开关 ⇒ 封顶撤除（可逆，不留后遗症）', () {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      GlassAccessibility.debugReduceTransparency = true;
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.tier, LiquidGlassTier.solid);

      GlassAccessibility.debugReduceTransparency = false;
      GlassAccessibility.syncRuntimeFlags();
      expect(LiquidGlassRuntime.tier, LiquidGlassTier.fakeGlass);
    });
  });
}
