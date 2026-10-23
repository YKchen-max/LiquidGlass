// #11 / M1a 测试①（决策 4）：uniform 打包的**顺序与字节数**。
//
// 为什么必须有：上游按 float 索引紧凑打包，**错位不报错、只画面错乱** ✗（移植清单 §7）。
// 这里的断言对象是 `docs/liquid-glass-素材.md` §4 的索引表 —— 逐下标对照，而不是"跑通了就算" ✓。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('uniform 布局（对照素材 §4 索引表）', () {
    // ⚠ **M1b-22 防回归断言** ✓：`BackdropFilter` / `ImageFilter.shader` 路径里
    //   **引擎占住浮点 0-1**（第一个 vec2 = `uSize` ✓，上游 `setFloatUniforms(initialIndex: 2, …)` ✓）
    //   ⇒ 我们**必须从索引 2 开始写** ✓；Paint 路径没有引擎 ⇒ 从 0 开始写 ✓（含 `uSize` ✓）。
    //   实测定案依据（M1b-21）：直读 `uSize` 时写 84 与写 1080 **读出完全相同且 ≥1000** ✗。
    test('写入起点：页内 backdrop 路从 2 开始（0-1 留给引擎），Paint 路从 0 开始', () {
      expect(LiquidGlassFinalRenderPass.firstWrittenFloatIndex(engineOwnsFirstVec2: true), 2);
      expect(LiquidGlassFinalRenderPass.firstWrittenFloatIndex(engineOwnsFirstVec2: false), 0);
      // 默认（不传）必须是 Paint 路的 0 ✓（避免误伤 Paint 路径 ✓）
      expect(LiquidGlassFinalRenderPass.firstWrittenFloatIndex(), 0);
      // 起点 2 必须正好跳过 uSize 的两个 float ✓
      expect(LiquidGlassFinalRenderPass.firstWrittenFloatIndex(engineOwnsFirstVec2: true),
          LiquidGlassUniformLayout.sizeIndex + LiquidGlassUniformLayout.sizeFloats);
    });

    test('索引表本身就是 §4 的形状：0-1/2-5/6-9/10-12/13-15/16-17', () {
      expect(LiquidGlassUniformLayout.sizeIndex, 0);
      expect(LiquidGlassUniformLayout.sizeFloats, 2);
      expect(LiquidGlassUniformLayout.geometryIndex, 2);
      expect(LiquidGlassUniformLayout.geometryFloats, 4);
      expect(LiquidGlassUniformLayout.glassColorIndex, 6);
      expect(LiquidGlassUniformLayout.glassColorFloats, 4);
      expect(LiquidGlassUniformLayout.opticalPropsIndex, 10);
      expect(LiquidGlassUniformLayout.opticalPropsFloats, 3);
      expect(LiquidGlassUniformLayout.lightConfigIndex, 13);
      expect(LiquidGlassUniformLayout.lightConfigFloats, 3);
      expect(LiquidGlassUniformLayout.lightDirectionIndex, 16);
      expect(LiquidGlassUniformLayout.lightDirectionFloats, 2);
      // 上游 `setFloatUniforms(initialIndex: 6, …)` 的起点必须等于颜色起点 ✓
      expect(LiquidGlassUniformLayout.settingsFloatIndex, 6);
      expect(LiquidGlassUniformLayout.staticFloats, 18);
      expect(LiquidGlassUniformLayout.indexTable.length, 18);
    });

    test('形状数组 = MAX_SHAPES(16) × 6 floats（sdf.glsl:2-3）', () {
      expect(LiquidGlassUniformLayout.maxShapes, 16);
      expect(LiquidGlassUniformLayout.floatsPerShape, 6);
      expect(LiquidGlassUniformLayout.shapeDataFloats, 96);
    });

    test('打包：字节数 72、逐下标落位正确（"错位不报错"的防线）', () {
      final p = LiquidGlassRefractionParams(
        size: const ui.Size(390, 844),
        geometryOffset: const ui.Offset(3, 5),
        geometrySize: const ui.Size(384, 840),
        glassColor: const ui.Color(0x33FF8040),
        refractiveIndex: 1.21,
        chromaticAberration: 0.02,
        thickness: 30,
        lightIntensity: 0.6,
        ambientStrength: 0.1,
        saturation: 1.5,
        lightAngle: math.pi / 4,
      );
      final v = p.packStaticUniforms();
      expect(v.length, 18);
      expect(packedStaticByteCount(), 72);

      // 逐段对照 §4
      expect(v.sublist(0, 2), [390.0, 844.0]); // uSize
      expect(v.sublist(2, 6), [3.0, 5.0, 384.0, 840.0]); // uGeometryOffset/Size
      final c = const ui.Color(0x33FF8040);
      expect(v.sublist(6, 10), [c.r, c.g, c.b, c.a]); // uGlassColor
      expect(v.sublist(10, 13), [1.21, 0.02, 30]); // uOpticalProps
      expect(v.sublist(13, 16), [0.6, 0.1, 1.5]); // uLightConfig
      expect(v[16], closeTo(math.cos(math.pi / 4), 1e-12)); // uLightDirection
      expect(v[17], closeTo(math.sin(math.pi / 4), 1e-12));
    });

    test('顺序快照稳定（含下标名，便于人眼复核；改名/改序会立刻红）', () {
      final p = const LiquidGlassRefractionParams(
        size: ui.Size(10, 20),
        geometryOffset: ui.Offset(0, 0),
        geometrySize: ui.Size(10, 20),
        glassColor: ui.Color(0xFF000000),
        lightAngle: 0,
      );
      final snap = packOrderSnapshot(p.packStaticUniforms());
      expect(snap, contains('0:uSize.x=10.0000'));
      expect(snap, contains('1:uSize.y=20.0000'));
      expect(snap, contains('6:uGlassColor.r='));
      expect(snap, contains('10:uOpticalProps.refractiveIndex=1.2000'));
      expect(snap, contains('13:uLightConfig.lightIntensity=0.5000'));
      expect(snap, contains('16:uLightDirection.cos=1.0000'));
      expect(snap.split('|').length, 18);
    });

    test('默认参数与素材 §4 "官方默认"一致', () {
      const p = LiquidGlassRefractionParams(
        size: ui.Size(1, 1),
        geometryOffset: ui.Offset.zero,
        geometrySize: ui.Size(1, 1),
        glassColor: ui.Color(0x00000000),
      );
      expect(p.refractiveIndex, 1.2);
      expect(p.thickness, 20);
      expect(p.chromaticAberration, 0.01);
      expect(p.lightIntensity, 0.5);
      expect(p.ambientStrength, 0);
      expect(p.saturation, 1.5);
      expect(p.lightAngle, math.pi / 2);
    });
  });
}