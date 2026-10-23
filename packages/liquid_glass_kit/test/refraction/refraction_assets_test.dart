// #11 / M1a 测试②（决策 2）：资产键**参数化** + 失败**必须打日志**（不静默 ✗）。
//
// 依据是 M0 的真实根因：上游把键硬编码成 `packages/liquid_glass_renderer/…`，
// 而"包被当 app 根"时 Flutter 不加前缀 ⇒ 键解析不到 ⇒ `fromAsset` **静默不就绪** ✗
// ⇒ 玻璃整块不画，我们为此白跑了 5 个实验臂 ✗。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('资产键（参数化，禁止硬编码上游包名）', () {
    tearDown(() {
      LiquidGlassRefractionAssets.assetRoot =
          'packages/liquid_glass_kit/lib/assets/shaders/';
      debugPrint = debugPrintThrottled;
    });

    test('默认根 = 本 kit 的包名（不是上游包名）', () {
      expect(LiquidGlassRefractionAssets.assetRoot,
          'packages/liquid_glass_kit/lib/assets/shaders/');
      expect(LiquidGlassRefractionAssets.allKeys, hasLength(4));
      for (final k in LiquidGlassRefractionAssets.allKeys) {
        expect(k, startsWith('packages/liquid_glass_kit/lib/assets/shaders/'));
        expect(k, endsWith('.iplr'));
        // 决策 2 的硬要求：**不得**出现上游包名 ✗
        expect(k, isNot(contains('liquid_glass_renderer')));
      }
    });

    test('根可注入 ⇒ 键随之变化（"当 app 根用"就是设成空串）', () {
      LiquidGlassRefractionAssets.assetRoot = '';
      expect(LiquidGlassRefractionAssets.keyFor(
              LiquidGlassRefractionShader.finalRender),
          'liquid_glass_final_render.iplr');
      LiquidGlassRefractionAssets.assetRoot = 'custom/root/';
      expect(LiquidGlassRefractionAssets.keyFor(
              LiquidGlassRefractionShader.geometryBlended),
          'custom/root/liquid_glass_geometry_blended.iplr');
    });

    test('四支键与文件名一一对应（顺序固定）', () {
      expect(
        LiquidGlassRefractionAssets.allKeys,
        [
          'packages/liquid_glass_kit/lib/assets/shaders/liquid_glass_geometry_blended.iplr',
          'packages/liquid_glass_kit/lib/assets/shaders/liquid_glass_filter.iplr',
          'packages/liquid_glass_kit/lib/assets/shaders/liquid_glass_final_render.iplr',
          'packages/liquid_glass_kit/lib/assets/shaders/liquid_glass_arbitrary.iplr',
        ],
      );
    });
  });

  group('加载：失败必须打日志（M0 的"静默不就绪"不许重演 ✗）', () {
    tearDown(() => debugPrint = debugPrintThrottled);

    test('成功分支打 loaded 日志、返回 program 替身', () async {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      // 用替身 loader 避免依赖引擎资产包（单测环境没有真 asset bundle）
      final program = await LiquidGlassRefractionAssets.loadShader<Object>(
        LiquidGlassRefractionShader.filter,
        loader: (key) async => Object(),
      );
      expect(program, isNotNull);
      expect(logs.join('\n'), contains('refraction shader loaded: filter'));
    });

    test('失败分支**一定**有日志，并带排查提示、返回 null（不抛给调用方）', () async {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      final program = await LiquidGlassRefractionAssets.loadShader<Object>(
        LiquidGlassRefractionShader.finalRender,
        loader: (key) async => throw StateError('asset not found: $key'),
      );
      expect(program, isNull);
      final out = logs.join('\n');
      expect(out, contains('refraction shader LOAD FAILED: finalRender'));
      expect(out, contains('asset not found'));
      expect(out, contains('排查提示')); // 键前缀这条提示必须在 ✓
      expect(out, contains('assetRoot='));
    });

    test('loadAll 汇总成功数：半套 shader 必须被显式指出（不许拿半套去画）', () async {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      var n = 0;
      final ok = await LiquidGlassRefractionAssets.loadAll<Object>(
        loader: (key) async {
          n++;
          if (n == 3) throw StateError('boom');
          return Object();
        },
      );
      expect(ok, 3);
      expect(logs.join('\n'), contains('3/4 加载成功'));
    });

    test('通道门禁可被替身覆盖（便于日后接页面时做降级测试）', () {
      final saved = isShaderFilterSupportedOnThisRuntime;
      isShaderFilterSupportedOnThisRuntime = false;
      expect(isRefractionShaderChannelAvailable, isFalse);
      isShaderFilterSupportedOnThisRuntime = true;
      expect(isRefractionShaderChannelAvailable, isTrue);
      isShaderFilterSupportedOnThisRuntime = saved;
    });
  });
}
