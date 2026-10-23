// task-125 单测：vendored `ProgressBar` 的 **local-patch 钩子**（`thumbPainter`）。
//
// 口径（照 task-125 ③）：
//   1) 钩子为 null ⇒ 走**上游默认路径**（圆圈 thumbRadius/thumbColor）✓ 行为不变 ✓；
//   2) 钩子非 null ⇒ 回调**确实被调用**（canvas/center/radius 三参到位 ✓）⇒ 我们的
//      `LiquidSliderThumbShape.paintThumbInto` 才有机会画 lens 手柄 ✓。
// 本文件只测"钩子语义"，不测 lens 的视觉（那由 liquid_player_skin_test.dart 覆盖 ✓）。
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/pages/video/widgets/liquid_slider_skin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, child: child)),
  ),
);

void main() {
  group('ProgressBar.thumbPainter 钩子（task-125 local patch ✓）', () {
    testWidgets('钩子为 null ⇒ 上游默认渲染路径不报错（行为不变 ✓）', (tester) async {
      await tester.pumpWidget(
        _host(
          ProgressBar(
            progress: 3 * 1000,
            total: 10 * 1000,
            thumbRadius: 7,
            thumbColor: const Color(0xFFFF6699),

            thumbGlowColor: const Color(0x80FF6699),
            baseBarColor: const Color(0x33FFFFFF),
            progressBarColor: const Color(0xFFFF6699),
            bufferedBarColor: const Color(0x55FFFFFF),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ProgressBar), findsOneWidget);
    });

    testWidgets('钩子非 null ⇒ 回调被调用，且 center/radius 参数到位 ✓', (tester) async {
      var calls = 0;
      Offset? seenCenter;
      double? seenRadius;
      Canvas? seenCanvas;
      await tester.pumpWidget(
        _host(
          ProgressBar(
            progress: 5 * 1000,
            total: 10 * 1000,
            thumbRadius: 7,
            thumbColor: const Color(0xFFFF6699),

            thumbGlowColor: const Color(0x80FF6699),
            baseBarColor: const Color(0x33FFFFFF),
            progressBarColor: const Color(0xFFFF6699),
            bufferedBarColor: const Color(0x55FFFFFF),
            thumbPainter: (canvas, center, radius) {
              calls++;
              seenCanvas = canvas;
              seenCenter = center;
              seenRadius = radius;
            },
          ),
        ),
      );
      expect(calls, greaterThanOrEqualTo(1), reason: 'paint 阶段应调用钩子 ✓');
      expect(seenCanvas, isNotNull);
      expect(seenRadius, 7.0);
      final size = tester.getSize(find.byType(ProgressBar));
      expect(seenCenter!.dx, inInclusiveRange(0, size.width));
      expect(seenCenter!.dy, inInclusiveRange(0, size.height));
    });

    testWidgets('接真实的 lens 画笔也画得出来（纯 Canvas ⇒ 无异常 ✓）', (tester) async {
      await tester.pumpWidget(
        _host(
          ProgressBar(
            progress: 5 * 1000,
            total: 10 * 1000,
            thumbRadius: 7,
            thumbColor: const Color(0xFFFF6699),

            thumbGlowColor: const Color(0x80FF6699),
            baseBarColor: const Color(0x33FFFFFF),
            progressBarColor: const Color(0xFFFF6699),
            bufferedBarColor: const Color(0x55FFFFFF),
            thumbPainter: (c, o, r) => LiquidSliderThumbShape.paintThumbInto(
              c,
              o,
              r,
              brightness: Brightness.dark,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
