// #11 / M1b-4 测试：**filter 趟的 uniform 契约**（113 floats，取自 GLSL 原文 ✓）。
//
// 为什么必须单独测这一趟：三趟的 uniform 块**结构不同** ✗（合成 18 / 几何 103 / filter 113），
// 而"错位不报错、只画面错乱"是这条链的老毛病 ⇒ 每趟都要有自己的逐下标断言 ✓。
//
// 另一个易漏点（Lead 点名）：**filter 趟自带 `uShapeData`（17-112）** ✓ ⇒
// "形状数组只属几何趟"**不能外推** ✗（那句话只在 `final_render` 的 18-float 语境下成立 ✓）。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('filter 趟 uniform 契约（对照 GLSL 原文 location 0-6）', () {
    test('索引表形状：size2 / color4 / optical4 / light4 / dir2 / numShapes1 / shapes96 = 113', () {
      expect(LiquidGlassFilterUniformLayout.sizeIndex, 0);
      expect(LiquidGlassFilterUniformLayout.glassColorIndex, 2);
      expect(LiquidGlassFilterUniformLayout.opticalPropsIndex, 6);
      expect(LiquidGlassFilterUniformLayout.lightConfigIndex, 10);
      expect(LiquidGlassFilterUniformLayout.lightDirectionIndex, 14);
      expect(LiquidGlassFilterUniformLayout.numShapesIndex, 16);
      expect(LiquidGlassFilterUniformLayout.shapeDataIndex, 17);
      expect(LiquidGlassFilterUniformLayout.shapeDataFloats, 96);
      expect(LiquidGlassFilterUniformLayout.totalFloats, 113);
      expect(LiquidGlassFilterUniformLayout.indexTable.length, 17);
    });

    test('打包：逐段落位正确 + 长度 113', () {
      final input = LiquidGlassFilterInput(
        physicalSize: const ui.Size(120, 80),
        shapes: const <LiquidGlassRefractionShape>[
          LiquidGlassRefractionShape(
            type: LiquidGlassShapeType.roundedRect,
            center: ui.Offset(60, 40),
            size: ui.Size(40, 40),
            cornerRadius: 10,
          ),
        ],
        glassColor: const ui.Color(0x33FFFFFF),
        refractiveIndex: 1.25,
        chromaticAberration: 0.03,
        thickness: 28,
        blend: 0.5,
        lightAngle: 0,
        lightIntensity: 0.6,
        ambientStrength: 0.1,
        saturation: 1.4,
      );
      final v = input.pack();
      expect(v.length, 113);
      expect(v.sublist(0, 2), [120.0, 80.0]); // uSize
      final c = const ui.Color(0x33FFFFFF);
      expect(v.sublist(2, 6), [c.r, c.g, c.b, c.a]); // uGlassColor
      expect(v.sublist(6, 10), [1.25, 0.03, 28.0, 0.5]); // uOpticalProps
      expect(v.sublist(10, 14), [0.0, 0.6, 0.1, 1.4]); // uLightConfig
      expect(v[14], closeTo(math.cos(0), 1e-12)); // uLightDirection
      expect(v[15], closeTo(math.sin(0), 1e-12));
      expect(v[16], 1.0); // uNumShapes
      expect(v.sublist(17, 23), [3.0, 60.0, 40.0, 40.0, 40.0, 10.0]); // 形状段落位 ✓
      expect(v.sublist(23).every((x) => x == 0), isTrue);
    });

    test('uNumShapes 与截断一致（>16 个 ⇒ 报 16，且必须有日志 ✗ 不许静默）', () {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = debugPrintThrottled);
      final many = List<LiquidGlassRefractionShape>.generate(
        18,
        (i) => LiquidGlassRefractionShape(
          type: LiquidGlassShapeType.ellipse,
          center: ui.Offset(i.toDouble(), 0),
          size: const ui.Size(8, 8),
        ),
      );
      final v = LiquidGlassFilterInput(
        physicalSize: const ui.Size(64, 64),
        shapes: many,
        glassColor: const ui.Color(0x22000000),
      ).pack();
      expect(v[16], LiquidGlassUniformLayout.maxShapes.toDouble());
      expect(logs.join('\n'), contains('超过 MAX_SHAPES'));
    });

    test('光照方向随角度变化（cos/sin 精确落位）', () {
      final a = LiquidGlassFilterInput(
        physicalSize: const ui.Size(10, 10),
        shapes: const <LiquidGlassRefractionShape>[],
        glassColor: const ui.Color(0x00000000),
        lightAngle: math.pi / 2,
      ).pack();
      expect(a[14], closeTo(0, 1e-9));
      expect(a[15], closeTo(1, 1e-9));
    });
  });

  group('三趟契约**各不相同**（接线时别搞混 ✗）', () {
    test('合成 18 / 几何 103 / filter 113', () {
      expect(LiquidGlassUniformLayout.staticFloats, 18); // final_render
      expect(LiquidGlassGeometryUniformLayout.totalFloats, 103);
      expect(LiquidGlassFilterUniformLayout.totalFloats, 113);
    });

    test('形状数组：几何趟 7-102、filter 趟 17-112（两趟都要 ✅）', () {
      expect(LiquidGlassGeometryUniformLayout.shapeDataIndex, 7);
      expect(LiquidGlassGeometryUniformLayout.shapeDataIndex +
              LiquidGlassGeometryUniformLayout.shapeDataFloats,
          103);
      expect(LiquidGlassFilterUniformLayout.shapeDataIndex, 17);
      expect(LiquidGlassFilterUniformLayout.shapeDataIndex +
              LiquidGlassFilterUniformLayout.shapeDataFloats,
          113);
    });
  });

  group('纹理所有权（M1b-3 标的缺口 ✗ → 规则写死 ✓）', () {
    test('put 替换同一槽位时先释放旧的（否则稳定泄漏 ✗）', () async {
      final cache = LiquidGlassRefractionTextureCache();
      final a = await _solid(8, 8, const ui.Color(0xFFFF0000));
      final b = await _solid(8, 8, const ui.Color(0xFF00FF00));
      cache.put('geo', a);
      expect(cache.ownedCount, 1);
      cache.put('geo', b); // 旧 a 应被释放 ✓
      expect(cache.ownedCount, 1);
      expect(identical(cache.get('geo'), b), isTrue);
      // ⚠ **不要**再去 dispose `a` ✗ —— 实测 double-dispose **会抛**（我第一版就写了这句、测试红了 ✓）。
      // 这正是"谁建谁 release"的另一面：**缓存接管的纹理，调用方不得再释放** ✓。
      cache.releaseAll();
      expect(cache.ownedCount, 0);
    });

    test('releaseKey 后不再持有', () async {
      final cache = LiquidGlassRefractionTextureCache();
      cache.put('x', await _solid(4, 4, const ui.Color(0xFF0000FF)));
      cache.releaseKey('x');
      expect(cache.get('x'), isNull);
      expect(cache.ownedCount, 0);
    });
  });
}

Future<ui.Image> _solid(int w, int h, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}