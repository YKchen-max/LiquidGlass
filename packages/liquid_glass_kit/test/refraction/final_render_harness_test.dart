// #11 / M1b-1 测试②：**预览 harness** —— 真实资产加载 + 离屏像素。
//
// 两件事分开报，避免"环境不支持"被误读成"管线接错了" ✗：
//   A. **真实 `fromAsset` 加载**：这是 **kit 的资产键在真实资产包里的首次端到端验证** ✓
//      （M1a 只断言了键的拼接，没真加载过）。四支都应加载成功；
//   B. **离屏像素**：把 `final_render` 的 `FragmentShader` 当**普通 2D paint** 画到
//      `PictureRecorder` 的离屏 canvas（这条**不依赖 `ImageFilter.shader`/backdrop**，
//      与真机路径不同 ✓）⇒ 读回像素看是否"非纯色、且随几何参数变化"。
//      注意：headless 测试引擎**可能不执行** `.iplr`（GPU 后端缺失）—— 若如此，
//      这里会**显式失败并说明原因**（下面的断言会给出区分性信息），**不硬凑** ✗。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  // harness 环境的关键事实（实测，非假设）：
  //   `flutter test` 把**被测包自己当成 app 根** ⇒ 资产在测试资产包里位于 `lib/assets/shaders/…`
  //   （`build/unit_test_assets/` 已列举确认 ✓），**没有** `packages/<name>/` 前缀 ✗；
  //   用默认根加载的报错原文就是：
  //   `Exception: Asset 'packages/liquid_glass_kit/lib/assets/shaders/…' not found` ✓
  //   ⇒ 这正是 M0 的根因规律（"被依赖的包 vs 当 app 根"）在测试环境的复现，
  //     也正是 M1a 把 assetRoot 做成**可注入**的原因 ✓。
  //   ⚠ 取值是"去掉包前缀、**保留目录**"= `lib/assets/shaders/`，**不是空串** ✗
  //     （空串 ⇒ `liquid_glass_filter.iplr` ⇒ 仍 not found ✓ 已实测）。
  setUp(() => LiquidGlassRefractionAssets.assetRoot =
      LiquidGlassRefractionAssets.appRootConsumptionRoot);
  tearDown(() => LiquidGlassRefractionAssets.assetRoot =
      'packages/liquid_glass_kit/lib/assets/shaders/');
  group('A. 真实资产加载（kit 键的端到端验证）', () {
    test('四支 .iplr 都能通过 kit 的默认键加载', () async {
      final logs = <String>[];
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = debugPrintThrottled);

      final ok = await LiquidGlassRefractionAssets.loadAll<ui.FragmentProgram>();
      final out = logs.join('\n');
      debugPrint('[harness] 四支加载成功数 = $ok / ${LiquidGlassRefractionShader.values.length}');
      // **环境事实（实测，已证明）**：`flutter test` 的引擎跑 **SkSL** 后端，
      // 而我们的 `.iplr` 按设计只带 gles/gles3/vulkan（SkSL 在 Windows 必失败 ✗，见 #8）
      // ⇒ 在这里**永远加载不成功** ✗，报错原文：
      //   `does not contain appropriate runtime stage data for current backend (SkSL).`
      // ⇒ 像素级验证**必须在真机（Impeller）上做 = M1b-2** ✓。
      //
      // 但这条测试仍然有硬价值：**它证明键解析到了** ✓ —— 若键写错，报错会是
      //   `Asset '…' not found` ✗（我在调这一步时**两种错都亲眼见过**：默认根 ⇒ not found；
      //   正确根 ⇒ backend ✗）。所以断言写成"**不许是 not found**"：
      // 这样无论未来环境是否支持加载，这条都能稳定守住"键与消费形态一致"这个 M0 教训 ✓。
      expect(out, isNot(contains('not found')),
          reason: '键解析不到 ⇒ 键前缀与消费形态不一致（M0 的根因）✗\n日志:\n$out');
      if (ok > 0) {
        expect(ok, LiquidGlassRefractionShader.values.length,
            reason: '要么全成功、要么全失败于后端；半套会让"折射档"状态含糊 ✗');
        expect(out, contains('refraction shader loaded: finalRender'));
      } else {
        expect(out, contains('current backend (SkSL)'),
            reason: '失败原因必须指向**后端**（否则就是别的问题，不要放过）✗\n日志:\n$out');
        debugPrint('[harness] 结论：键 ✓、后端 ✗（SkSL）⇒ 像素验证移交 M1b-2 真机');
      }
    });
  });

  group('B. 离屏像素（final_render 一趟）', () {
    test(
      '一个静态形状 ⇒ 输出非纯色，且随厚度/圆角变化',
      // headless 测试引擎是 **SkSL** 后端，而我们的 .iplr 按设计只带 gles+gles3+vulkan
      //（SkSL 在 Windows 必失败，见 #8）⇒ 该环境**不可能**加载：
      //   `does not contain appropriate runtime stage data for current backend (SkSL).`
      // ⇒ 像素级验证只能在**真机 Impeller** 上做 = M1b-2 ✓
      //（数据侧已由 final_render_data_test.dart 全覆盖 ✓；本文件 A 组证明键解析到了 ✓）。
      skip: 'headless 引擎只有 SkSL 后端；本管线 shader 不含 SkSL 阶段 ⇒ 移交 M1b-2 真机验证 ✓',
      () async {
      final program =
          await LiquidGlassRefractionAssets.loadShader<ui.FragmentProgram>(
        LiquidGlassRefractionShader.finalRender,
      );
      expect(program, isNotNull, reason: 'final_render 没加载到（见 A 组日志）');

      const w = 96, h = 96;
      final bg = await _gradientImage(w, h);
      final geo = await _shapeImage(w, h);
      addTearDown(() {
        bg.dispose();
        geo.dispose();
      });

      Future<Uint8List> renderWith(double thickness, double cornerRadius) async {
        final shader = program!.fragmentShader();
        LiquidGlassFinalRenderPass.writeUniforms(
          shader,
          LiquidGlassFinalRenderInput(
            params: LiquidGlassRefractionParams(
              size: ui.Size(w.toDouble(), h.toDouble()),
              geometryOffset: ui.Offset.zero,
              geometrySize: ui.Size(w.toDouble(), h.toDouble()),
              glassColor: const ui.Color(0x22FFFFFF),
              thickness: thickness,
              refractiveIndex: 1.3,
              chromaticAberration: 0.02,
              lightAngle: 0.8,
            ),
            shapes: [
              LiquidGlassRefractionShape(
                type: LiquidGlassShapeType.roundedRect,
                center: ui.Offset(w / 2, h / 2),
                size: const ui.Size(56, 56),
                cornerRadius: cornerRadius,
              ),
            ],
            backgroundTexture: bg,
            geometryTexture: geo,
          ),
        );
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..shader = shader,
        );
        final image = await recorder.endRecording().toImage(w, h);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return bytes!.buffer.asUint8List();
      }

      final a = await renderWith(20, 8);
      final b = await renderWith(60, 28);

      final statsA = _stats(a);
      final statsB = _stats(b);
      debugPrint('[harness] final_render 输出: '
          'A(厚度20/r8) 唯一色=${statsA.uniqueColors} std=${statsA.std.toStringAsFixed(2)}  '
          'B(厚度60/r28) 唯一色=${statsB.uniqueColors} std=${statsB.std.toStringAsFixed(2)}  '
          'A≠B 像素占比=${_diffRatio(a, b).toStringAsFixed(3)}');

      // 判据 1：不是纯色（纯色 ⇒ 唯一色 1、std 0 ⇒ 说明 shader 没跑或输出退化了 ✗）
      expect(statsA.uniqueColors, greaterThan(4),
          reason: '输出几乎是纯色 ⇒ shader 很可能没被 headless 引擎执行（见文件头说明）✗');
      expect(statsA.std, greaterThan(0.5));
      // 判据 2：与几何参数相关（改厚度/圆角 ⇒ 输出必须变）
      expect(_diffRatio(a, b), greaterThan(0.01),
          reason: '改厚度/圆角后输出没变 ⇒ uniform 没喂对（错位不报错的典型症状）✗');
    });
  });
}

class _Stats {
  _Stats(this.uniqueColors, this.std);
  final int uniqueColors;
  final double std;
}

_Stats _stats(Uint8List rgba) {
  final seen = <int>{};
  var sum = 0.0, sumSq = 0.0;
  final n = rgba.length ~/ 4;
  for (var i = 0; i < rgba.length; i += 4) {
    seen.add((rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2]);
    final l = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
    sum += l;
    sumSq += l * l;
  }
  final mean = sum / n;
  return _Stats(seen.length, ((sumSq / n) - mean * mean).clamp(0, 1e9).toDouble().abs().isNaN
      ? 0
      : _sqrt(((sumSq / n) - mean * mean).clamp(0, 1e9)));
}

double _sqrt(double v) {
  var x = v;
  for (var i = 0; i < 24; i++) {
    x = 0.5 * (x + v / (x == 0 ? 1e-9 : x));
  }
  return x;
}

double _diffRatio(Uint8List a, Uint8List b) {
  var changed = 0;
  final n = a.length ~/ 4;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > 4 ||
        (a[i + 1] - b[i + 1]).abs() > 4 ||
        (a[i + 2] - b[i + 2]).abs() > 4) {
      changed++;
    }
  }
  return changed / n;
}

Future<ui.Image> _gradientImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset.zero,
        ui.Offset(w.toDouble(), h.toDouble()),
        const [ui.Color(0xFF204060), ui.Color(0xFFE0A030), ui.Color(0xFF802040)],
        const [0.0, 0.5, 1.0], // 3 色必须给 stops（dart:ui 规则）
      ),
  );
  final image = await recorder.endRecording().toImage(w, h);
  return image;
}

Future<ui.Image> _shapeImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  canvas.drawCircle(
    ui.Offset(w / 2, h / 2),
    w * 0.3,
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  return image;
}