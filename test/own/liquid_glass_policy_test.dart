// task-8 守门规则的单元测试。
//
// 位置说明（Lead 2026-10-03）：门禁第 3 项跑的是 `flutter test test/own`（宿主自有测试），
// 所以本文件必须放在 `test/own/` 下——**没被门禁覆盖的测试等于没有测试**。
//
// 这里钉的是**安全关键**的一条：策略层**只能降档、不能升档**。
// 背景（Lead 点的第 1 条）：kit 的自动探测 / 黑名单是带安全理由的降档（例如无 offscreen MSAA
// 的 D3D11/GLES2 路径上 BackdropFilter 行为异常，问题台账 §3 #192918）；如果策略层能把档位
// 抬回玻璃，它就变成了"绕过能力矩阵的后门"（#11 的两个口子就是这么来的：强制档不做能力校验
// ⇒ debug 崩 / release 静默没玻璃）。所以这条不能只写在注释里。
//
// 另外钉两条纯逻辑：挂载决策表（暂停=玻璃 / 播放中=纯色…）与 720p 纹理陷阱规则。
// 实测依据见 `docs/性能压测.md` §9.5.6 与 `liquid_glass_policy.dart` 的文件头。
import 'package:PiliPlus/plugin/pl_player/utils/video_texture_size.dart';
import 'package:PiliPlus/utils/liquid_glass_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

/// 造一个指定档位的 capability（`overrideForTest` 要用）。
LiquidGlassCapability cap(LiquidGlassTier tier) => LiquidGlassCapability(
      tier: tier,
      platform: 'windows',
      osVersion: 'test',
      shaderFilterSupported: false,
      reason: 'unit test',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('effectiveTier: 策略只能降档，不能升档', () {
    tearDown(() => LiquidGlassRuntime.overrideForTest(null));

    test('kit 判 solid 时，策略要玻璃也只能拿到 solid（降档优先）', () {
      LiquidGlassRuntime.overrideForTest(cap(LiquidGlassTier.solid));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.solid,
        reason: '策略层没有资格把 kit 已经判死的档位抬回玻璃',
      );
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.solid,
      );
    });

    test('kit 是 fakeGlass 时，策略要玻璃就是玻璃（同档不被打回）', () {
      LiquidGlassRuntime.overrideForTest(cap(LiquidGlassTier.fakeGlass));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.fakeGlass,
      );
    });

    test('kit 是 fakeGlass 时，策略不能升到 refraction（未过能力门禁）', () {
      LiquidGlassRuntime.overrideForTest(cap(LiquidGlassTier.fakeGlass));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.refraction),
        LiquidGlassTier.fakeGlass,
        reason: '真折射要 shader 门禁，策略层不得越过',
      );
    });

    test('kit 是 refraction 时，策略要纯色就是纯色（允许策略降档）', () {
      LiquidGlassRuntime.overrideForTest(cap(LiquidGlassTier.refraction));
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.solid),
        LiquidGlassTier.solid,
      );
    });

    test('未初始化（kit 保守取 fakeGlass）时行为一致', () {
      LiquidGlassRuntime.overrideForTest(null);
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.fakeGlass),
        LiquidGlassTier.fakeGlass,
      );
      expect(
        LiquidGlassPolicy.effectiveTier(LiquidGlassTier.solid),
        LiquidGlassTier.solid,
      );
    });
  });

  group('挂载决策表（decideOnAttach）', () {
    tearDown(() => LiquidGlassPolicy.force = GlassPolicyForce.auto);

    test('默认（auto）：只有暂停/静止请求真折射档，其余场景给纯色', () {
      LiquidGlassPolicy.force = GlassPolicyForce.auto;

      expect(
        LiquidGlassPolicy.decideOnAttach(GlassBarContext.pausedIdle).tier,
        LiquidGlassTier.refraction,
        reason: '暂停/静止是唯一安全时机（无连续视频纹理更新）⇒ R1 起改为**请求真折射档**：'
            '请求 ≠ 能上 —— 合成后的档位仍由 kit 判定（`effectiveTier` 只降不升，见下一条测试）',
      );
      for (final ctx in <GlassBarContext>[
        GlassBarContext.playingSteady,
        GlassBarContext.seeking,
        GlassBarContext.layoutTransient,
      ]) {
        final d = LiquidGlassPolicy.decideOnAttach(ctx);
        expect(d.tier, LiquidGlassTier.solid, reason: '$ctx 应给纯色');
        expect(d.samplesBackdrop, isFalse);
      }
    });

    /// R1（task-78/79）**最该被锁住的一句话** ✓：
/// **策略"请求"、kit"判定"、不支持则回落** —— 请求 refraction **不等于**能上折射。
    test('kit 判 fakeGlass 时：pausedIdle 的**合成结果**必须是 fakeGlass（请求 ≠ 能上）', () {
      LiquidGlassPolicy.force = GlassPolicyForce.auto;
      LiquidGlassRuntime.overrideForTest(cap(LiquidGlassTier.fakeGlass));
      final requested =
          LiquidGlassPolicy.decideOnAttach(GlassBarContext.pausedIdle).tier;
      expect(requested, LiquidGlassTier.refraction, reason: '策略侧请求折射（R1 接线入口）');
      expect(
        LiquidGlassPolicy.effectiveTier(requested),
        LiquidGlassTier.fakeGlass,
        reason: 'kit 判定优先：策略请求折射但运行时只给 fakeGlass ⇒ 控制条必须回落既有路径 ✗',
      );
    });

    /// R1（task-80）**局部 opt-in 的两条门禁** ✓（Lead 指定：能力不可用必须回落 / 能力可用才放行）
    test('opt-in：能力不可用（通道 false）时必须回落既有路径', () {
      final prev = isShaderFilterSupportedOnThisRuntime;
      isShaderFilterSupportedOnThisRuntime = false;
      try {
        LiquidGlassPolicy.force = GlassPolicyForce.auto;
        final d = LiquidGlassPolicy.decideOnAttach(GlassBarContext.pausedIdle);
        expect(d.tier, LiquidGlassTier.refraction, reason: '策略侧仍请求折射 ✓');
        expect(
          LiquidGlassPolicy.useRefractionLayerFor(decision: d),
          isFalse,
          reason: '通道不可用 ⇒ 即使 opt-in 也必须回落（绝不绕过 capability ✗✓）',
        );
      } finally {
        isShaderFilterSupportedOnThisRuntime = prev;
      }
    });

    test('opt-in：通道可用 + 策略请求折射 ⇒ 放行走折射层（全局档位仍不动 ✓）', () {
      final prev = isShaderFilterSupportedOnThisRuntime;
      isShaderFilterSupportedOnThisRuntime = true;
      try {
        // app 现状：全局档位是 fakeGlass（未注册 provider ⇒ capability = fakeGlass ✓）
        LiquidGlassRuntime.overrideForTest(cap(LiquidGlassTier.fakeGlass));
        final d = LiquidGlassPolicy.decideOnAttach(GlassBarContext.pausedIdle);
        expect(
          LiquidGlassPolicy.useRefractionLayerFor(decision: d),
          isTrue,
          reason: '局部 opt-in 的意义：全局是 fakeGlass 也要给本层开口 ✓（但不改全局 ✗）',
        );
        expect(
          LiquidGlassRuntime.tier,
          LiquidGlassTier.fakeGlass,
          reason: 'opt-in 只作用于本层 ⇒ 全局档位保持原样（首页等不受影响 ✓）',
        );
      } finally {
        isShaderFilterSupportedOnThisRuntime = prev;
        LiquidGlassRuntime.overrideForTest(null);
      }
    });

    test('一行强制开关（复测用）：glass / solid 覆盖策略表', () {
      LiquidGlassPolicy.force = GlassPolicyForce.glass;
      expect(
        LiquidGlassPolicy.decideOnAttach(GlassBarContext.playingSteady).tier,
        LiquidGlassTier.fakeGlass,
        reason: '策略前那一组：播放中也挂玻璃',
      );

      LiquidGlassPolicy.force = GlassPolicyForce.solid;
      expect(
        LiquidGlassPolicy.decideOnAttach(GlassBarContext.pausedIdle).tier,
        LiquidGlassTier.solid,
        reason: '策略后那一组：全纯色',
      );
    });

    test('contextOf：过渡 > seek > 播放中/暂停 的优先级', () {
      expect(
        LiquidGlassPolicy.contextOf(
            isPlaying: true, isSeeking: true, layoutTransient: true),
        GlassBarContext.layoutTransient,
      );
      expect(
        LiquidGlassPolicy.contextOf(
            isPlaying: true, isSeeking: true, layoutTransient: false),
        GlassBarContext.seeking,
      );
      expect(
        LiquidGlassPolicy.contextOf(
            isPlaying: true, isSeeking: false, layoutTransient: false),
        GlassBarContext.playingSteady,
      );
      expect(
        LiquidGlassPolicy.contextOf(
            isPlaying: false, isSeeking: false, layoutTransient: false),
        GlassBarContext.pausedIdle,
      );
    });
  });

  group('720p 纹理陷阱规则（requestForSource）', () {
    test('源 1280x720 ⇒ 请求 1920x1080（实测干净格），且标记 trapAvoided', () {
      final r = VideoTextureSizePolicy.requestForSource(
        sourceWidth: 1280,
        sourceHeight: 720,
        platformOverride: 'windows',
      );
      expect(r, isNotNull);
      expect(r!.width, VideoTextureSizePolicy.avoidTargetWidth);
      expect(r.height, VideoTextureSizePolicy.avoidTargetHeight);
      expect(VideoTextureSizePolicy.avoidTargetWidth == 1280, isFalse,
          reason: '目标值必须与源尺寸不同，否则又落回陷阱格');
    });

    test('其它源保持原生（行为不变）', () {
      for (final s in <List<int>>[
        [1920, 1080],
        [3840, 2160],
        [854, 480],
      ]) {
        expect(
          VideoTextureSizePolicy.requestForSource(
            sourceWidth: s[0],
            sourceHeight: s[1],
            platformOverride: 'windows',
          ),
          isNull,
          reason: '${s[0]}x${s[1]} 无实测证据 ⇒ 保持 native，不引入未测变量',
        );
      }
    });

    test('非 Windows 一律不改（证据只在 Windows/Skia 路径上；且 Android setSize 会抛）', () {
      for (final p in <String>['android', 'ios', 'linux', 'macos']) {
        expect(
          VideoTextureSizePolicy.requestForSource(
            sourceWidth: 1280,
            sourceHeight: 720,
            platformOverride: p,
          ),
          isNull,
          reason: '$p 不应改纹理尺寸',
        );
      }
    });

    test('GLASS_TEXTURE_FIX=off 时连 720p 也不改（对照臂）', () {
      final saved = VideoTextureSizePolicy.mode;
      VideoTextureSizePolicy.mode = TextureFixMode.off;
      try {
        expect(
          VideoTextureSizePolicy.requestForSource(
            sourceWidth: 1280,
            sourceHeight: 720,
            platformOverride: 'windows',
          ),
          isNull,
        );
      } finally {
        VideoTextureSizePolicy.mode = saved;
      }
    });

    test('GLASS_TEXTURE_TARGET 覆盖：让"请求值 != 源尺寸"成为必然（判别性验证用）', () {
      final saved = VideoTextureSizePolicy.targetOverride;
      VideoTextureSizePolicy.targetOverride = (width: 1280, height: 720);
      try {
        // auto + 720p 源：仍会请求，但目标被覆盖（否则源 1920x1080 时读回不可判别）
        final a = VideoTextureSizePolicy.requestForSource(
          sourceWidth: 1280,
          sourceHeight: 720,
          platformOverride: 'windows',
        );
        expect(a, isNotNull);
        expect(a!.width, 1280);
        expect(a.height, 720);
        expect(a.width == 1280 && a.height == 720, isTrue);

        // force + 任意源：也走覆盖值
        final savedMode = VideoTextureSizePolicy.mode;
        VideoTextureSizePolicy.mode = TextureFixMode.force;
        try {
          final b = VideoTextureSizePolicy.requestForSource(
            sourceWidth: 1920,
            sourceHeight: 1080,
            platformOverride: 'windows',
          );
          expect(b, isNotNull);
          expect(b!.width, 1280);
          expect(b.height, 720);
          // 关键性质：覆盖后的请求值必须与源不同，否则读回无法区分"接受/拒绝"
          expect(b.height == 1080, isFalse);
        } finally {
          VideoTextureSizePolicy.mode = savedMode;
        }
      } finally {
        VideoTextureSizePolicy.targetOverride = saved;
      }
    });

    test('GLASS_TEXTURE_FIX=force 时任何源都请求目标值（验证链路用）', () {
      final saved = VideoTextureSizePolicy.mode;
      VideoTextureSizePolicy.mode = TextureFixMode.force;
      try {
        final r = VideoTextureSizePolicy.requestForSource(
          sourceWidth: 1920,
          sourceHeight: 1080,
          platformOverride: 'windows',
        );
        expect(r, isNotNull);
        expect(r!.width, VideoTextureSizePolicy.avoidTargetWidth);
        expect(r.height, VideoTextureSizePolicy.avoidTargetHeight);
      } finally {
        VideoTextureSizePolicy.mode = saved;
      }
    });
  });
}