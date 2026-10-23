// #11 / M1b-1 测试①：`final_render` 一趟的**数据侧闭环**（纯 Dart，不依赖设备/GPU）。
//
// 判据（task-39 原文）："输出不是纯色、且与几何参数相关" ✓ —— 在这一层能严格证到的是
//   * uniform 块**完整且分量正确**（静态 0-17 复用 M1a layout + 形状 18..113）；
//   * **几何参数相关性**：改尺寸/中心/圆角/厚度/折射率/光角 ⇒ 对应下标**精确**变化 ✓
//     （这比"看起来变了"强：错位不报错是上游 §7 明确警告的坑 ✗）；
//   * MAX_SHAPES 超限 ⇒ **显式截断 + 日志** ✓（不许静默 ✗）。
// 像素侧能否在 headless 引擎里跑，由 `final_render_harness_test.dart` 单独报告 ✓。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('形状数组打包（6 floats/形状，复用 M1a layout）', () {
    test('逐分量落位：type/centerX/centerY/sizeW/sizeH/cornerRadius', () {
      final data = packShapeData(const [
        LiquidGlassRefractionShape(
          type: LiquidGlassShapeType.roundedRect,
          center: ui.Offset(30, 40),
          size: ui.Size(100, 60),
          cornerRadius: 12,
        ),
        LiquidGlassRefractionShape(
          type: LiquidGlassShapeType.squircle,
          center: ui.Offset(1, 2),
          size: ui.Size(3, 4),
          cornerRadius: 5,
        ),
      ]);
      expect(data.packedCount, 2);
      expect(data.droppedCount, 0);
      expect(data.truncated, isFalse);
      expect(data.floats.length, LiquidGlassUniformLayout.shapeDataFloats); // 96 ✓
      expect(data.floats.sublist(0, 6), [3.0, 30.0, 40.0, 100.0, 60.0, 12.0]);
      expect(data.floats.sublist(6, 12), [1.0, 1.0, 2.0, 3.0, 4.0, 5.0]);
      // 其余必须全 0（否则 shader 会把它当成"存在的形状"✗）
      expect(data.floats.sublist(12).every((v) => v == 0), isTrue);
    });

    test('type 值与 sdf.glsl 一致：1=squircle / 2=ellipse / 3=rrect', () {
      expect(LiquidGlassShapeType.squircle.shaderValue, 1.0);
      expect(LiquidGlassShapeType.ellipse.shaderValue, 2.0);
      expect(LiquidGlassShapeType.roundedRect.shaderValue, 3.0);
    });

    test('MAX_SHAPES 超限 ⇒ 截断到 16 + **有日志**（不许静默 ✗）', () {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = debugPrintThrottled);

      final many = List.generate(
        19,
        (i) => LiquidGlassRefractionShape(
          type: LiquidGlassShapeType.ellipse,
          center: ui.Offset(i.toDouble(), 0),
          size: const ui.Size(10, 10),
        ),
      );
      final data = packShapeData(many);
      expect(data.packedCount, LiquidGlassUniformLayout.maxShapes); // 16 ✓
      expect(data.droppedCount, 3);
      expect(data.truncated, isTrue);

      final out = logs.join('\n');
      expect(out, contains('超过 MAX_SHAPES=16'));
      expect(out, contains('显式截断'));
      expect(out, contains('拆层')); // 排查提示必须在 ✓
      // 被丢的 3 个要能点名（便于定位"少了几块玻璃"✗）
      expect(out, contains('center=Offset(16.0, 0.0)'));
      expect(out, contains('center=Offset(18.0, 0.0)'));
    });

    test('恰好 16 个不触发截断日志（边界）', () {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = debugPrintThrottled);
      final data = packShapeData(
        List.generate(
          16,
          (i) => LiquidGlassRefractionShape(
            type: LiquidGlassShapeType.ellipse,
            center: ui.Offset(i.toDouble(), 0),
            size: const ui.Size(10, 10),
          ),
        ),
      );
      expect(data.packedCount, 16);
      expect(data.droppedCount, 0);
      expect(logs, isEmpty);
    });

    test('uniform 总长度 = 静态 18 + 形状 96 = 114（形状数组起点 = 18）', () {
      expect(shapeDataFloatIndex, LiquidGlassUniformLayout.staticFloats);
      expect(shapeDataFloatIndex, 18);
      expect(refractionUniformFloatCount, 114);
    });
  });

  group('几何参数相关性（错位不报错的防线）', () {
    test('改形状/光学/光照 ⇒ **精确**落到对应下标', () {
      const base = LiquidGlassRefractionParams(
        size: ui.Size(200, 100),
        geometryOffset: ui.Offset(0, 0),
        geometrySize: ui.Size(200, 100),
        glassColor: ui.Color(0x22FFFFFF),
        thickness: 20,
        refractiveIndex: 1.2,
        lightAngle: 0,
      );
      final a = base.packStaticUniforms();
      final b = base.copyWith(thickness: 30).packStaticUniforms();
      expect(a[12], 20.0);
      expect(b[12], 30.0); // uOpticalProps.thickness ✓
      expect(a.sublist(0, 12), b.sublist(0, 12)); // 其它下标**不受影响** ✓

      final c = base.copyWith(lightAngle: 3.141592653589793 / 2).packStaticUniforms();
      expect(a[16], 1.0); // cos(0) ✓
      expect(c[16], closeTo(0, 1e-9)); // cos(π/2) ✓
      expect(c[17], closeTo(1, 1e-9)); // sin(π/2) ✓

      // 形状侧同样逐分量相关 ✓
      final s1 = packShapeData(const [
        LiquidGlassRefractionShape(
          type: LiquidGlassShapeType.roundedRect,
          center: ui.Offset(10, 10),
          size: ui.Size(50, 50),
          cornerRadius: 8,
        ),
      ]).floats;
      final s2 = packShapeData(const [
        LiquidGlassRefractionShape(
          type: LiquidGlassShapeType.roundedRect,
          center: ui.Offset(10, 10),
          size: ui.Size(50, 50),
          cornerRadius: 20,
        ),
      ]).floats;
      expect(s1[5], 8.0);
      expect(s2[5], 20.0);
      expect(s1.sublist(0, 5), s2.sublist(0, 5));
    });
  });

  group('三趟编排（结构就位 + 显式原因）', () {
    test('顺序固定：几何烘焙 → filter → 合成（合成必须最后 ✓）', () {
      expect(LiquidGlassRefractionPipeline.order, [
        LiquidGlassRefractionPass.geometryBake,
        LiquidGlassRefractionPass.filter,
        LiquidGlassRefractionPass.finalRender,
      ]);
    });
    test('M1b-4 状态：三趟 reason 都随事实更新（未加载时各有明确原因 ✓）', () {
      final list = LiquidGlassRefractionPipeline.availability(
        finalRenderProgramLoaded: false, // 未加载
        geometryProgramLoaded: false, // 未加载
        filterProgramLoaded: false, // 未加载
        shaderFilterSupported: true,
      );
      expect(list, hasLength(3));
      expect(list[0].ready, isFalse);
      expect(list[0].reason, contains('还没拿到 geometry_blended'));
      // M1b-4 起 filter 趟已落地 ⇒ reason 换成"program 未加载"口径 ✓（不是 M1b-3 的旧理由 ✗）
      expect(list[1].ready, isFalse);
      expect(list[1].reason, contains('还没拿到 liquid_glass_filter'));
      expect(list[2].ready, isFalse);
      expect(list[2].reason, contains('还没拿到'));
      expect(LiquidGlassRefractionPipeline.describe(finalRenderProgramLoaded: false),
          contains('geometryTap=pending'));

      // program 全就位 ⇒ 前两趟 ready，reason 变成各自的真实输入要求 ✓
      final ready = LiquidGlassRefractionPipeline.availability(
        finalRenderProgramLoaded: true,
        geometryProgramLoaded: true,
        filterProgramLoaded: true,
        shaderFilterSupported: true,
      );
      expect(ready[0].ready, isTrue);
      expect(ready[0].reason, contains('离屏烘焙'));
      expect(ready[1].ready, isTrue);
      expect(ready[1].reason, contains('模糊'));
      for (final a in ready) {
        expect(a.reason, isNot(contains('M1b-')));
      }
      expect(LiquidGlassRefractionPipeline.describe(
              finalRenderProgramLoaded: true,
              geometryProgramLoaded: true,
              filterProgramLoaded: true),
          contains('geometryTap=ready'));
    });


    test('无 shader filter（Skia）时**不许**假装能渲染 ✗', () {
      final availability = LiquidGlassFinalRenderPass.availability(
        programLoaded: true,
        shaderFilterSupported: false,
      );
      expect(availability.ready, isFalse);
      expect(availability.reason, contains('isShaderFilterSupported=false'));
      expect(availability.reason, contains('FakeGlass'));
    });

    test('program 就位 + filter 可用 ⇒ 第 3 趟 ready', () {
      final availability = LiquidGlassFinalRenderPass.availability(
        programLoaded: true,
        shaderFilterSupported: true,
      );
      expect(availability.ready, isTrue);
    });
  });
}
