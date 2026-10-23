// SPDX-License-Identifier: GPL-3.0-or-later
//
// 排期 #9 的可执行验收：材质 token（深浅双套）、三级降级矩阵、能力探测与落盘 latch。
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('材质 token（深浅双套）', () {
    test('暗色按台账要求：模糊更大、光强更低、底色更暗', () {
      expect(LiquidGlassTokens.dark.blur, greaterThan(LiquidGlassTokens.light.blur));
      expect(LiquidGlassTokens.dark.lightIntensity,
          lessThan(LiquidGlassTokens.light.lightIntensity));
      expect(LiquidGlassTokens.dark.tintOpacity,
          greaterThan(LiquidGlassTokens.light.tintOpacity));
      // 光角全 App 统一（素材文档 §8 建议 π/4）
      expect(LiquidGlassTokens.dark.lightAngle, closeTo(LiquidGlassTokens.light.lightAngle, 1e-9));
    });

    test('lerp 在中点为两端均值，且端点不漂移', () {
      const a = LiquidGlassTokens.light;
      const b = LiquidGlassTokens.dark;
      final mid = LiquidGlassTokens.lerp(a, b, 0.5);
      expect(mid.blur, closeTo((a.blur + b.blur) / 2, 1e-9));
      expect(mid.tintOpacity, closeTo((a.tintOpacity + b.tintOpacity) / 2, 1e-9));
      expect(LiquidGlassTokens.lerp(a, b, 0).blur, a.blur);
      expect(LiquidGlassTokens.lerp(a, b, 1).blur, b.blur);
      // 越界参数要夹紧，避免动画控制器的浮点误差把 token 拉飞
      expect(LiquidGlassTokens.lerp(a, b, -1).blur, a.blur);
      expect(LiquidGlassTokens.lerp(a, b, 2).blur, b.blur);
    });

    test('具名材质：regular 原样、thick 更厚更模糊、lens 更薄、solid 不采样背景', () {
      const base = LiquidGlassTokens.light;
      expect(base.forMaterial(LiquidGlassMaterial.regular), base);
      expect(base.forMaterial(LiquidGlassMaterial.thick).blur, greaterThan(base.blur));
      expect(base.forMaterial(LiquidGlassMaterial.thick).tintOpacity,
          greaterThan(base.tintOpacity));
      expect(base.forMaterial(LiquidGlassMaterial.lens).thickness, lessThan(10));
      expect(base.forMaterial(LiquidGlassMaterial.lens).refractiveIndex,
          greaterThan(base.refractiveIndex));
      final solid = base.forMaterial(LiquidGlassMaterial.solid);
      expect(solid.blur, 0);
      expect(solid.highlightOpacity, 0);
      expect(solid.saturation, 1);
    });

    test('饱和度矩阵：1.0 为恒等，0.0 退化为 Rec.709 亮度', () {
      final identity = saturationMatrix(1);
      expect(identity[0], closeTo(1, 1e-9));
      expect(identity[1], closeTo(0, 1e-9));

      final gray = saturationMatrix(0);
      const lr = 0.2126, lg = 0.7152, lb = 0.0722;
      expect(gray[0], closeTo(lr, 1e-9)); // R 行
      expect(gray[1], closeTo(lg, 1e-9));
      expect(gray[2], closeTo(lb, 1e-9));
      expect(gray[5], closeTo(lr, 1e-9)); // G 行
      expect(gray[10], closeTo(lr, 1e-9)); // B 行
      expect(gray.length, 20); // 4x5 矩阵
    });
  });

  // M1-B（task-2）：真机 ZTE A2023 深色模式下"玻璃在深色背景上几乎看不出来"。
  // 下面这组断言把调优后的暗色档钉在"深色背景仍可读"的量化标准上，防止将来又被调回去：
  //   * 边缘高光：WCAG 2.1 SC 1.4.11 非文本对比度 ≥3:1（描边是唯一 normal-blend 的边沿线索）；
  //   * 玻璃板 vs 背景：≥1.12（参照 Apple 暗色材质 #1C1C1E 压在纯黑上 ≈1.21）；
  //   * 有效 rim alpha / 中段 ambient 不得被双重衰减压回不可见。
  // 证据：2026-10-02 用 poc/glass_poc main_kit_bench（KIT_BENCH_BG=dark，Skia）截图 +
  // .probe/dt-bench/metrics.py 像素统计；调优前实测暗背景下 edge CR≈2.0、pane CR≈1.04。
  group('暗色档可读性（M1-B 调优后的验收线）', () {
    // 深色背景取样值：真机截图底部导航周边 ≈ #1A1D21（luma≈0.10）。
    const darkBackdrop = Color(0xFF1A1D21);

    // task-7 起 painter 的派生量与 kit 共用同一实现（LiquidGlassTokens.rimAlpha /
    // midStopAlpha），测试不再各自复制公式，避免两边漂移。
    double rimAlpha(LiquidGlassTokens t) => t.rimAlpha;
    double midStopAlpha(LiquidGlassTokens t) => t.midStopAlpha;

    test('边缘高光不得被双重衰减压到不可见，但仍比亮色档克制', () {
      expect(rimAlpha(LiquidGlassTokens.dark), greaterThanOrEqualTo(0.38),
          reason: '暗色档 rim 有效 alpha 低于此值时，深色背景上描边读不出来（实测 0.214 → edge CR 2.0）');
      expect(rimAlpha(LiquidGlassTokens.dark), lessThan(rimAlpha(LiquidGlassTokens.light)),
          reason: '暗色档仍应比亮色档弱，不能为了可读性把暗色做得比亮色还亮');
    });

    test('暗色档 rim 中段余晖可见，且不高于亮色档', () {
      expect(midStopAlpha(LiquidGlassTokens.dark), greaterThanOrEqualTo(0.09),
          reason: '低于此值时边框中段几乎全是背景色（实测 0.026 → 中段 CR 1.07，玻璃只剩两个角在发光）');
      expect(midStopAlpha(LiquidGlassTokens.dark), lessThan(midStopAlpha(LiquidGlassTokens.light)),
          reason: '暗色档的中段余晖不应超过亮色档（否则暗色会发灰）');
    });

    test('暗色档描边：深色背景上达到 WCAG 1.4.11 的 3:1，线宽不低于上游下限 1.0', () {
      final border = Color.alphaBlend(LiquidGlassTokens.dark.borderColor, darkBackdrop);
      expect(_contrastRatio(border.computeLuminance(), darkBackdrop.computeLuminance()),
          greaterThanOrEqualTo(3.0),
          reason: '底色描边是唯一 normal-blend 的边沿线索，深色背景上必须 ≥3:1');
      // 上游 fake_glass.dart:419 的描边线宽下限是 lerp(1, 2, lightIntensity) → 1.0。
      expect(LiquidGlassTokens.dark.borderWidth, greaterThanOrEqualTo(1.0),
          reason: '本包旧值 0.8 低于上游下限，DPR 3 的真机上只有 2.4px 且抗锯齿后覆盖率不足');
    });

    test('暗色档玻璃板本身要能与深色背景区分（不是一片黑）', () {
      final pane = Color.alphaBlend(
        LiquidGlassTokens.dark.tint.withValues(alpha: LiquidGlassTokens.dark.tintOpacity),
        darkBackdrop,
      );
      expect(_contrastRatio(pane.computeLuminance(), darkBackdrop.computeLuminance()),
          greaterThanOrEqualTo(1.12),
          reason: '旧值（#0B0F14 @0.42）实测 pane CR≈1.04：玻璃板比背景还暗一点，等于看不见');
      // 防回归：tint 不许再退回接近纯黑（#0B0F14 的 computeLuminance ≈ 0.0057）。
      expect(LiquidGlassTokens.dark.tint.computeLuminance(), greaterThan(0.03),
          reason: '暗色档 tint 需要比纯黑明显高一档，否则在深色背景上没有"抬起"的余量（台账 §1.1：暗背景→浅 tint）');
    });
  });

  // task-7（D）：painter 的 ambientStrength 语义与上游对齐——mid stop 直接取 ambientStrength，
  // 不再乘 rim alpha。下面既钉住语义，也把"这次改写是逐位不变的"这件事变成可执行断言。
  group('painter 派生量（task-7：ambient 与上游对齐）', () {
    test('mid stop alpha 就是 ambientStrength，不随 rim alpha 衰减', () {
      for (final base in <LiquidGlassTokens>[LiquidGlassTokens.light, LiquidGlassTokens.dark]) {
        for (final material in LiquidGlassMaterial.values) {
          final t = base.forMaterial(material);
          expect(t.midStopAlpha, closeTo(t.ambientStrength, 1e-12),
              reason: '$material：mid stop 必须等于 ambientStrength（上游 fake_glass.dart:398-404）');
        }
      }
    });

    test('把 rim 压到 0，中段余晖也不归零（旧实现会归零 = 双重衰减）', () {
      final noRim = LiquidGlassTokens.dark.copyWith(lightIntensity: 0, highlightOpacity: 0);
      expect(noRim.rimAlpha, 0);
      expect(noRim.midStopAlpha, closeTo(LiquidGlassTokens.dark.ambientStrength, 1e-12));
      expect(noRim.midStopAlpha, greaterThan(0.09),
          reason: '旧实现下这里必然是 0（ambient 被 rim alpha 乘掉了），这正是 M1-B 根因之一');
    });

    test('语义对齐是等价改写：token 值 == 旧实现（color.a × 旧 ambient）的精确 double', () {
      // 旧实现（task-7 之前）：mid = clamp(easeOut(lightIntensity) × highlightOpacity × 1.6) × 旧 ambient。
      // 这条断言是"浅色档截图逐字节不变"的代码侧锚点：若它失败，说明 token 值已经与
      // 那份位级基线脱钩，必须重跑截图 sha256 比对（见 task-7 报告），不能只改数字了事。
      double legacyMid(double lightIntensity, double highlightOpacity, double ambientOld) {
        final a = (Curves.easeOut.transform(lightIntensity) * highlightOpacity * 1.6).clamp(0.0, 1.0);
        return Colors.white.withValues(alpha: a).a * ambientOld;
      }

      expect(LiquidGlassTokens.light.ambientStrength, equals(legacyMid(0.50, 0.55, 0.30)));
      expect(LiquidGlassTokens.dark.ambientStrength, equals(legacyMid(0.35, 0.50, 0.28)));
    });

    test('forMaterial 的 thick/lens 把 mid stop 按同一系数折算（否则浅色档会变）', () {
      const base = LiquidGlassTokens.light;
      // 旧语义下 mid = rim alpha × ambient，而 thick 的 highlightOpacity 被 ×0.85、lens ×1.15，
      // 所以 mid 也被连带缩放；新语义下 mid 只认 ambientStrength，必须同步折算。
      expect(base.forMaterial(LiquidGlassMaterial.thick).ambientStrength,
          closeTo(base.ambientStrength * 0.85, 1e-15));
      expect(base.forMaterial(LiquidGlassMaterial.lens).ambientStrength,
          closeTo(base.ambientStrength * 1.15, 1e-15));
      expect(LiquidGlassTokens.dark.forMaterial(LiquidGlassMaterial.thick).ambientStrength,
          closeTo(LiquidGlassTokens.dark.ambientStrength * 0.85, 1e-15));
      expect(LiquidGlassTokens.dark.forMaterial(LiquidGlassMaterial.lens).ambientStrength,
          closeTo(LiquidGlassTokens.dark.ambientStrength * 1.15, 1e-15));
    });
  });

  // task-9（#12）：自适应对比度保护。判据沿用 M1-B/task-7 的口径：
  //   * 文字：**主题自己的文字色** vs 玻璃板的对比度 ≥4.5（WCAG AA 正文）；
  //   * 边缘：暗背景下 rim/描边 vs 背景 ≥3:1（WCAG 1.4.11；该项由 task-7 的描边/高光决定，
  //     本次改动不碰，实测仍为 4.23）。
  // 关键点：期望值不是"在四个采样点上成立"，而是**跨整个背景亮度区间**成立
  // （含纯黑 0 与纯白 1.0 两个端点），合成式与 painter 共用同一实现
  // （LiquidGlassTokens.glassLumaOver / adaptiveBackdropLuma），所以测试不会与实现漂移。
  //
  // ── 视觉基线（task-12 重新取证；哈希与【采集前提】必须一起读）──────────────────
  // 采集口径：poc/glass_poc main_kit_bench，1920×1080，Skia（POC_IMPELLER=0），
  //   背景动画冻结（KIT_BENCH_STATIC=1），抓图走 tools/ui-probe/shot.ps1 -PinForeground
  //   （必须钉前台：Windows 标题栏前台/非前台是蓝/灰两态，PrintWindow 会一起抓进去；
  //   task-9b 实测整图哈希对不上时 diff bbox 恰好只有那 45px 标题栏、客户区 0 像素差异）。
  //   语义判据用**客户端区域**哈希（y≥45）——标题栏是 OS 装饰，不属于我们的渲染。
  // 文件（scratch）：.probe/dt-bench/shots/q-pinned-<象限>.png（默认臂）／
  //   q-pinned-noadaptive-<象限>.png（关掉 #12 的参照臂）。
  // ① 默认臂（adaptive ON）·整图 → ②同象限客户端区域：
  //   light×亮背景 ①302ae1d03b2921aebe697e59ef39f7d2dd914b2bf7fd2e04dc1b3ca388e66a0f
  //                 ②656c1ab54ab4065d3e27f7cab745621427a7a634ff242009370f92b140543d8d
  //   light×暗背景 ①b35994e441bbb7963ed0c2aa5eefc0127eef74c2b2e8e800fd1e33d93425e7f5
  //                 ②133982e57178362bdcdc9bb1cf7119e2dae4632cb227fdeee8ddaf868e5280c5
  //   dark ×亮背景 ①3d584d5574e117ed17b228ea052c86825988a75fe11af77befae1fea6dc5e2e1
  //                 ②55db65d1e0d312d1c6b738a5d0015d576cb274496842d2fe070ab965a222b5ce
  //   dark ×暗背景 ①6a87cd67139cf2f94d5e078eda71552b3ad433354a0abb8c49c3c783d5ea4201
  //                 ②ea15bc07f717ab814bb61727df98ef0d7b98e489ef20c83d8db76b15d33c9fba
  // ③ 参照臂（KIT_BENCH_NOADAPTIVE=1）·客户端区域：
  //   light×亮 63c8522d385d75f2f6a94340ac3d64c3a55d7e74efde2c9af184c2c0ec3b05fb
  //   light×暗 f9cfb868ab842c042f87a07366dcd61eeb1899b9b1951b946cebd42f6de83637
  //   dark ×亮 a85162bcd83d1eae95c94ff35afe3296ca6fd0a397f2d33975f5c98b39980375
  //   dark ×暗 78f4a629b368ead225fac6ed1cbd09312ab04fd6b3e7c65ef30f07846f29b78f
  // ④ task-12 变更说明（不是放宽判据，而是「改视觉必须重新取证」）：
  //   * light 两象限的 ①②③ 全变了 —— 因为改了 light 档的 adaptiveLift/adaptiveDarken
  //     （自适应项：① 与 ③ 的差就是它）**以及静态的 borderColor/borderWidth**
  //     （深色发丝：③ 也随它变，因为静态值不受 NOADAPTIVE 开关管辖）。
  //   * light 的 ①② 是最终定值（adaptiveDarken 0.371）跑出来的；③ 只受**静态**改动影响，
  //     所以调 darken 不改变 ③（实测两次采集的 ③ 完全相同）。
  //   * dark 两象限的 ①②③ **与 task-9b 的登记值逐字节相同** —— 暗侧一个 token 都没动，
  //     这是「没把 task-9 成果打回去」的位级证据。
  group('自适应对比度保护（task-9 / task-12 / #12，四象限）', () {
    // 实测背景亮度：亮背景（mint 壁纸）≈0.73~0.83，压暗档 ≈0.12~0.13；端点 0/1.0 用于兜底。
    const backdrops = <double>[0.0, 0.13, 0.5, 0.826, 1.0];
    const whiteTextLuma = 1.0;
    const darkTextLuma = 18 / 255; // 浅色主题的深色字（与 bench 探针 #121212 同色）

    double srgbToLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    double cr(double srgbA, double srgbB) => _contrastRatio(srgbToLinear(srgbA), srgbToLinear(srgbB));

    test('暗色档：白字对玻璃 ≥4.5，覆盖整个背景亮度区间（含纯白背景）', () {
      for (final d in backdrops) {
        final pane = LiquidGlassTokens.dark.glassLumaOver(d);
        expect(cr(pane, whiteTextLuma), greaterThanOrEqualTo(4.5),
            reason: '背景亮度 $d 下白字对比度不足（glassLumaOver=$pane）');
      }
      // 最坏点就是纯白背景：留余量，别刚好压线。
      expect(cr(LiquidGlassTokens.dark.glassLumaOver(1.0), whiteTextLuma), greaterThan(4.8));
    });

    test('浅色档：深字对玻璃 ≥4.5，覆盖整个背景亮度区间（含纯黑背景）', () {
      for (final d in backdrops) {
        final pane = LiquidGlassTokens.light.glassLumaOver(d);
        expect(cr(pane, darkTextLuma), greaterThanOrEqualTo(4.5),
            reason: '背景亮度 $d 下深字对比度不足（glassLumaOver=$pane）');
      }
      // 纯黑页面上深字只留 4.5 余量（实测 4.59）：light 的 adaptiveLift 必须压低才换得到
      // 「近白页面上玻璃与页面拉开 ≥20/255」——这是 task-12 的取舍，不是回归（见报告）。
      expect(cr(LiquidGlassTokens.light.glassLumaOver(0.0), darkTextLuma), greaterThan(4.5));
    });

    test('机制确实随背景变：暗端抬起 + 动态范围压缩；关掉时与旧实现恒等', () {
      for (final t in <LiquidGlassTokens>[LiquidGlassTokens.light, LiquidGlassTokens.dark]) {
        // 暗端被抬起 —— 这正是 M1-B 要的「玻璃板比背景亮」。
        expect(t.adaptiveBackdropLuma(0.10) - 0.10, greaterThan(0.03), reason: '暗背景必须被抬起');
        // 动态范围被压缩（斜率 < 1）。两侧都成立，但方向可以不同：
        //   暗色档在亮端额外往下压（白字对比度靠它），亮色档只需要抬暗端、亮端保持中性。
        final range = t.adaptiveBackdropLuma(1.0) - t.adaptiveBackdropLuma(0.0);
        expect(range, lessThan(1.0), reason: '不压缩动态范围就等于没做事');
        expect(t.adaptiveBackdropLuma(0.9), greaterThan(t.adaptiveBackdropLuma(0.1)),
            reason: '映射必须单调（否则玻璃里会出现负片式层次）');
      }
      expect(LiquidGlassTokens.dark.adaptiveBackdropLuma(0.85), lessThan(0.85),
          reason: '暗色档亮端必须下压');
      // task-12：亮色档亮端必须**明显下压**。旧断言是「只允许轻微变化」，但近白页面上
      // 玻璃与页面同亮 ⇒ 隐身（task-11 实测 max Δ8）；下压是这一档可见性的来源。
      expect(LiquidGlassTokens.light.adaptiveBackdropLuma(0.85), lessThan(0.80),
          reason: '亮色档亮端不够下压时，近白页面上玻璃与页面拉不开');
      // 关闭（两个旋钮都为 0）= 恒等 ⇒ 老 token / 宿主自定义 token 行为不变。
      for (final t in <LiquidGlassTokens>[LiquidGlassTokens.light, LiquidGlassTokens.dark]) {
        final off = t.copyWith(adaptiveLift: 0, adaptiveDarken: 0);
        expect(off.adaptiveBackdropLuma(0.37), 0.37);
        expect(off.glassLumaOver(0.5), lessThanOrEqualTo(1.0));
      }
    });

    test('为什么必须自适应：关掉它，两侧必然有一侧不达标（M1-B/task-9 实测根因）', () {
      final darkStatic = LiquidGlassTokens.dark.copyWith(adaptiveLift: 0, adaptiveDarken: 0);
      final lightStatic = LiquidGlassTokens.light.copyWith(adaptiveLift: 0, adaptiveDarken: 0);
      // 暗色档：白字在亮背景（1.0）下不达标 —— task-9 要解决的问题。
      expect(cr(darkStatic.glassLumaOver(1.0), whiteTextLuma), lessThan(4.5));
      // 浅色档：深字在暗背景（0.13）下不达标（截图实测 2.01:1）。
      expect(cr(lightStatic.glassLumaOver(0.13), darkTextLuma), lessThan(4.5));
      // 但同一套静态 token 在另一侧是够用的 —— 这就是"固定参数必翻车一边"。
      expect(cr(darkStatic.glassLumaOver(0.13), whiteTextLuma), greaterThan(4.5));
      expect(cr(lightStatic.glassLumaOver(0.83), darkTextLuma), greaterThan(4.5));
    });

    test('task-12：近白页面上玻璃板必须与页面拉开 ≥20/255（task-11 的 8/255 噪声阈值 ×2.5）', () {
      for (final d in <double>[0.85, 0.90, 0.95, 1.0]) {
        final pane = LiquidGlassTokens.light.glassLumaOver(d);
        expect((pane - d).abs() * 255, greaterThanOrEqualTo(20),
            reason: '近白页面 d=$d 上玻璃板与页面只差 ${((pane - d).abs() * 255).toStringAsFixed(1)}/255 ⇒ 近乎隐身');
      }
    });

    test('task-12：浅色侧的深色发丝描边对浅色页面 ≥3:1（WCAG 1.4.11，与暗侧口径对称）', () {
      final t = LiquidGlassTokens.light;
      // 白描边铺在白页上物理上不可见 ⇒ 浅色侧的边沿只能靠深色发丝；黑描边 srcOver 在玻璃板上的
      // 合成亮度 = pane·(1-α)。
      double edgeLuma(double pageLuma) {
        final pane = t.glassLumaOver(pageLuma);
        return pane * (1 - t.borderColor.a);
      }

      for (final d in <double>[0.80, 0.90, 1.0]) {
        expect(cr(edgeLuma(d), d), greaterThanOrEqualTo(3.0),
            reason: '浅色页面 d=$d 上深色发丝的可辨度不足（合成亮度 ${edgeLuma(d).toStringAsFixed(3)}）');
      }
      // 这两条是「深线索够得着 3:1」的前提，别被悄悄调浅。
      expect(t.borderColor.a, greaterThanOrEqualTo(0.45), reason: '深色发丝太浅就撑不起 3:1');
      expect(t.borderWidth, greaterThanOrEqualTo(1.0), reason: '0.8 线宽抗锯齿后覆盖率不足，实测吃掉约 0.4 CR');
    });

    test('不牺牲本来可用的象限：浅色档亮背景只允许微调，暗色档仍保持玻璃板抬起', () {
      // task-9 之前实测：light 在亮背景下玻璃板 ≈0.790（压暗档 ≈0.277，深字只有 2.01:1。
      final pane = LiquidGlassTokens.light.glassLumaOver(0.744);
      expect((pane - 0.790).abs(), lessThan(0.10),
          reason: '亮背景下浅色玻璃的「本体亮度」只允许小幅变化（task-9 实测 0.790→0.843、task-12 最终 0.730）；'
              '容差从 0.06 放宽到 0.10：task-12 为可见性主动把该象限本体压暗 0.060（0.790→0.730）；真正的守护由新增的「近白页面 ≥20/255」判据承担');
      // 暗色档在暗背景下必须仍满足 M1-B 的"玻璃板比背景亮"（基线 +5.3/255）。
      expect(LiquidGlassTokens.dark.glassLumaOver(0.13) - 0.13, greaterThanOrEqualTo(5.3 / 255));
    });
  });

  group('能力探测与三级降级矩阵', () {
    test('Windows → FakeGlass（真折射在 Windows 实测崩溃，v1 固定降档）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'windows',
        osVersionOverride: 'Windows 11 Pro 10.0.26100',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
      expect(capability.reason, contains('FakeGlass'));
    });

    test('远程/虚拟显示会话再降一档（Windows → 纯色兜底）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'windows',
        osVersionOverride: 'Windows 11 Pro 10.0.26100',
        shaderFilterSupportedOverride: true,
        remoteSessionOverride: true,
      );
      expect(capability.tier, LiquidGlassTier.solid);
      expect(capability.reason, contains('远程'));
    });

    test('远程会话判定读 SESSIONNAME（RDP-Tcp#N）', () {
      expect(LiquidGlassProbe.detectRemoteSession(environment: {'SESSIONNAME': 'RDP-Tcp#12'}), isTrue);
      expect(LiquidGlassProbe.detectRemoteSession(environment: {'SESSIONNAME': 'Console'}), isFalse);
      expect(LiquidGlassProbe.detectRemoteSession(environment: {}), isFalse);
    });

    test('黑名单命中即钉死档位（默认清单为空，靠注入验证机制）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 12 (SDK 31)',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
        blacklist: const <LiquidGlassBlacklistEntry>[
          LiquidGlassBlacklistEntry(
            platform: 'android',
            osVersionContains: 'SDK 31',
            tier: LiquidGlassTier.solid,
            reason: '某老驱动必崩（示例条目）',
          ),
        ],
      );
      expect(capability.tier, LiquidGlassTier.solid);
      expect(capability.matchedBlacklist?.reason, contains('示例条目'));
    });

    test('Android 且 shader filter 可用 + 折射 shader 就位 → 真折射', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 15 (SDK 35)',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.refraction);
      expect(capability.refractionUsable, isTrue);
    });

    test('Android 但 shader filter 不可用 → FakeGlass（硬门禁）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: false,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
    });

    test('未知平台 → 纯色兜底', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'fuchsia',
        osVersionOverride: '0',
        shaderFilterSupportedOverride: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.solid);
    });

    // task-13（#11 前置）：选档阶段的 refraction 守卫。渲染侧 Glassify 在
    // !isShaderFilterSupported 时是 assert+return child（debug 崩 / release 静默没玻璃），
    // 所以强制档也必须过守卫，不能指望渲染器兜底。
    test('强制 refraction + shader filter 不支持 ⇒ 回落 fakeGlass（reason 写明）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        forcedTier: LiquidGlassTier.refraction,
        platformOverride: 'windows',
        osVersionOverride: 'Windows 11',
        shaderFilterSupportedOverride: false,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
      expect(capability.reason, contains('设备不支持 shader filter，已回落'));
      expect(capability.reason, contains('强制'), reason: '降档了，但仍是「宿主强制」这一支');
      expect(capability.forced, isTrue);
      expect(capability.refractionUsable, isFalse);
    });

    test('强制 refraction + shader filter 可用 ⇒ 仍是 refraction（守卫不误降）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        forcedTier: LiquidGlassTier.refraction,
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.refraction);
      expect(capability.reason, contains('强制'));
      expect(capability.refractionUsable, isTrue);
    });

    test('守卫不误降其它组合：强制 fakeGlass/solid 原样保留（也不被升级）', () async {
      for (final forced in <LiquidGlassTier>[LiquidGlassTier.fakeGlass, LiquidGlassTier.solid]) {
        final capability = await LiquidGlassProbe.resolve(
          store: LiquidGlassMemoryProbeStore(),
          forcedTier: forced,
          platformOverride: 'android',
          osVersionOverride: 'Android 15',
          shaderFilterSupportedOverride: true,
          refractionShaderAvailable: true,
          remoteSessionOverride: false,
        );
        expect(capability.tier, forced, reason: '强制档必须原样生效，不能因为「本可以更高」被改判');
        expect(capability.forced, isTrue);
      }
    });

    test('latchFailure 被传入 fallbackTier=refraction 时，也不会返回不可用的 refraction', () async {
      final capability = await LiquidGlassProbe.latchFailure(
        reason: '测试：误传 fallbackTier',
        store: LiquidGlassMemoryProbeStore(),
        fallbackTier: LiquidGlassTier.refraction,
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
      expect(capability.reason, contains('设备不支持 shader filter，已回落'));
      expect(capability.latched, isTrue);
    });

    test('黑名单若被误配成 refraction，也过同一道守卫', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 15 (SDK 35)',
        shaderFilterSupportedOverride: false,
        remoteSessionOverride: false,
        blacklist: const <LiquidGlassBlacklistEntry>[
          LiquidGlassBlacklistEntry(
            platform: 'android',
            osVersionContains: '*',
            tier: LiquidGlassTier.refraction,
            reason: '配置误写（示例）',
          ),
        ],
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
      expect(capability.reason, contains('设备不支持 shader filter，已回落'));
      expect(capability.matchedBlacklist, isNotNull, reason: '命中的黑名单条目仍要保留，便于排查');
    });

    test('宿主强制档位优先于一切（含黑名单）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        forcedTier: LiquidGlassTier.fakeGlass,
        platformOverride: 'windows',
        osVersionOverride: 'Windows 11',
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
      expect(capability.forced, isTrue);
    });

    test('运行期失败 latch 会落盘，并在下次启动直接降档', () async {
      final store = LiquidGlassMemoryProbeStore();
      final latched = await LiquidGlassProbe.latchFailure(
        reason: 'd3dcompiler_47.dll 0xC0000005',
        store: store,
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
      );
      expect(latched.tier, LiquidGlassTier.fakeGlass, reason: '真折射降一档 = FakeGlass');
      expect(latched.latched, isTrue);

      final persisted = await store.read();
      expect(persisted['latchedTier'], 'fakeGlass');
      expect(persisted['latchedReason'], contains('0xC0000005'));

      final next = await LiquidGlassProbe.resolve(
        store: store,
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(next.tier, LiquidGlassTier.fakeGlass, reason: 'latch 生效：不再尝试真折射');
      expect(next.latched, isTrue);
    });

    test('latch 可被清除（用户在设置里手动重试真折射）', () async {
      final store = LiquidGlassMemoryProbeStore();
      await LiquidGlassProbe.latchFailure(
        reason: '测试',
        store: store,
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
      );
      await store.clear();
      final next = await LiquidGlassProbe.resolve(
        store: store,
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(next.tier, LiquidGlassTier.refraction);
    });

    test('文件 store 能落盘并读回（坏文件不影响启动）', () async {
      final dir = await Directory.systemTemp.createTemp('liquid_glass_probe');
      final file = File('${dir.path}/probe.json');
      final store = LiquidGlassFileProbeStore(file);

      await LiquidGlassProbe.latchFailure(reason: '磁盘写入测试', store: store);
      expect(await file.exists(), isTrue);
      final readBack = await store.read();
      expect(readBack['latchedReason'], '磁盘写入测试');

      await file.writeAsString('{ 这不是 JSON');
      expect(await store.read(), isEmpty, reason: '坏文件按"无记录"处理，不抛异常');

      await dir.delete(recursive: true);
    });
  });

  // task-18（#11 接线）：渲染层的第二道闸。能力侧（task-13 的 _guardRefraction）保证
  // "不支持 shader filter 就不会选 refraction"；这里保证"shader 不在手上也不会去渲染"
  // ——否则会撞上游渲染器的 assert（debug 崩 / release 静默没玻璃，glassify.dart:58-67）。
  group('渲染层折射守卫（task-18 / #11 接线）', () {
    test('缺 shader 或缺 shader filter ⇒ 渲染层回落 fakeGlass（不允许静默走 refraction）', () {
      expect(
        resolveRenderTier(
          tier: LiquidGlassTier.refraction, shaderFilterSupported: true, shaderAvailable: false),
        LiquidGlassTier.fakeGlass,
      );
      expect(
        resolveRenderTier(
          tier: LiquidGlassTier.refraction, shaderFilterSupported: false, shaderAvailable: true),
        LiquidGlassTier.fakeGlass,
      );
    });

    test('shader 就位 + 能力支持 ⇒ 选中 refraction（守卫不误降）', () {
      expect(
        resolveRenderTier(
          tier: LiquidGlassTier.refraction, shaderFilterSupported: true, shaderAvailable: true),
        LiquidGlassTier.refraction,
      );
    });

    test('非 refraction 档不受渲染守卫影响', () {
      for (final t in <LiquidGlassTier>[LiquidGlassTier.fakeGlass, LiquidGlassTier.solid]) {
        for (final sf in <bool>[true, false]) {
          for (final sa in <bool>[true, false]) {
            expect(resolveRenderTier(tier: t, shaderFilterSupported: sf, shaderAvailable: sa), t);
          }
        }
      }
    });

    test('能力侧：Android + shaderFilter 可用但未提供 shader ⇒ 不选 refraction（reason 可分辨）', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: false,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.fakeGlass);
      expect(capability.reason, contains('未提供折射 shader'), reason: '真机日志要能分辨是缺哪一环');
      expect(capability.refractionUsable, isFalse);
    });

    test('能力侧：提供 shader 且 shaderFilter 可用 ⇒ 选中 refraction', () async {
      final capability = await LiquidGlassProbe.resolve(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
        refractionShaderAvailable: true,
        remoteSessionOverride: false,
      );
      expect(capability.tier, LiquidGlassTier.refraction);
      expect(capability.refractionUsable, isTrue);
    });

    test('注册 provider ⇒ initialize 默认认 shader 已就位；但 Windows 仍必须 FakeGlass（平台门）', () async {
      LiquidGlassRuntime.refractionShaderProvider = _NullShaderProvider();
      addTearDown(() => LiquidGlassRuntime.refractionShaderProvider = null);

      final win = await LiquidGlassRuntime.initialize(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'windows',
        osVersionOverride: 'Windows 11',
        shaderFilterSupportedOverride: false,
        remoteSessionOverride: false,
      );
      expect(win.tier, LiquidGlassTier.fakeGlass, reason: 'Windows 受 #8 的 SkSL/d3dcompiler 限制，必须继续 FakeGlass');

      final android = await LiquidGlassRuntime.initialize(
        store: LiquidGlassMemoryProbeStore(),
        platformOverride: 'android',
        osVersionOverride: 'Android 15',
        shaderFilterSupportedOverride: true,
        remoteSessionOverride: false,
      );
      expect(android.tier, LiquidGlassTier.refraction, reason: 'provider 注册 + shaderFilter 支持 ⇒ 选 refraction');
    });
  });

  group('玻璃表面与主题过渡', () {


    Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
      return MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: child)),
      );
    }

    testWidgets('FakeGlass 档确实挂了 BackdropFilter（模糊背景）', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassSurface(
          capability: LiquidGlassCapability(
            tier: LiquidGlassTier.fakeGlass,
            platform: 'windows',
            osVersion: 'Windows 11',
            shaderFilterSupported: true,
            reason: '测试',
          ),
          child: SizedBox(width: 100, height: 40),
        ),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('纯色档不采样背景（无 BackdropFilter）', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassSurface(
          capability: LiquidGlassCapability(
            tier: LiquidGlassTier.solid,
            platform: 'windows',
            osVersion: 'Windows 11',
            shaderFilterSupported: false,
            reason: '测试',
          ),
          child: SizedBox(width: 100, height: 40),
        ),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('深浅切换走 200ms 插值：中途的模糊值位于两端之间（不闪变）', (tester) async {
      // 显式传 brightness：MaterialApp 的 theme 变化自带 200ms AnimatedTheme，
      // 而 ThemeData.brightness 在中点才翻转，靠它驱动会让玻璃过渡晚 ~100ms 才开始
      // （这个坑在实测中真实踩到，见 liquid_glass_surface.dart 的 brightness 注释）。
      Widget tree(Brightness brightness) => wrap(
            LiquidGlassTheme(
              brightness: brightness,
              child: const LiquidGlassSurface(child: SizedBox(width: 100, height: 40)),
            ),
          );

      await tester.pumpWidget(tree(Brightness.light));
      final lightSigma = _sigmaOf(tester);

      await tester.pumpWidget(tree(Brightness.dark));
      // 动画刚开始的那一帧 elapsed 恒为 0（ticker 语义），所以再推进一帧才算进入过渡
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // 过渡中点（总时长 200ms）
      final midSigma = _sigmaOf(tester);

      await tester.pumpAndSettle();
      final darkSigma = _sigmaOf(tester);

      expect(lightSigma, closeTo(LiquidGlassTokens.light.blur, 1e-6));
      expect(darkSigma, closeTo(LiquidGlassTokens.dark.blur, 1e-6));
      expect(midSigma, greaterThan(lightSigma));
      expect(midSigma, lessThan(darkSigma));
    });
  });

  group('版本与素材约束', () {
    test('包版本常量与 pubspec 一致', () {
      expect(liquidGlassKitVersion, '0.1.0');
    });

    test('字体族名不加包前缀（Flutter 包内字体的实际行为）', () {
      expect(LiquidFontFamily.text, 'LiquidText');
      expect(LiquidFontFamily.icons, 'LiquidIcons');
      expect(LiquidFontFamily.lucide, 'LucideIcons');
    });
  });
}

/// WCAG 2.1 对比度：(L1+0.05)/(L2+0.05)，输入为相对亮度（computeLuminance 的结果）。
double _contrastRatio(double l1, double l2) {
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// 从渲染树里取出当前 BackdropFilter 的模糊 sigma。
///
/// ImageFilter 没有公开的 sigma getter，这里走它的 toString（形如
/// `ImageFilter.blur(8.0, 8.0, TileMode.mirror)`），只取第一个数值。
double _sigmaOf(WidgetTester tester) {
  final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;
  final text = filter.toString();
  final match = RegExp(r'blur\(([0-9.]+)').firstMatch(text);
  expect(match, isNotNull, reason: '期望是 blur 类型的 ImageFilter，实际：$text');
  return double.parse(match!.group(1)!);
}

/// 保留一个 ui 引用，避免分析器把 dart:ui 导入判为未使用（ImageFilter 类型断言用）。
// ignore: unused_element
ui.ImageFilter? _typeAnchor;

/// 测试用 provider：不返回真 shader（单测里造不出 FragmentShader），只验证"注册/选择"逻辑。
class _NullShaderProvider implements LiquidGlassRefractionShaderProvider {
  @override
  ui.FragmentShader? createShader() => null;

  @override
  int get uniformCount => 0;
}
