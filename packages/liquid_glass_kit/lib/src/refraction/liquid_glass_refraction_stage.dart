// #11 / M1b-3：三趟的**共享类型**（趟名 + 可用性）——刻意单独成文件，
// 避免 `geometry_pass` 与 `refraction_pass` 互相 import 造成环 ✓。
library;

import 'package:flutter/foundation.dart';

/// 三趟的名字（日志/测试/报告共用同一套词，避免各写一套 ✓）。
enum LiquidGlassRefractionPass {
  /// 第一趟：形状树 → 几何位移纹理（`geometry_blended`）。
  geometryBake('geometryTap'),

  /// 第二趟：模糊 + 位移采样（`filter`）——可多块共享同一 backdrop。
  filter('filterTap'),

  /// 第三趟：合成（`final_render`）。
  finalRender('finalRenderTap');

  const LiquidGlassRefractionPass(this.logTag);

  final String logTag;
}

/// 一趟的可用性：就位与否 + **原因**（人可读，且**必须随事实更新** ✓）。
@immutable
class LiquidGlassPassAvailability {
  const LiquidGlassPassAvailability({
    required this.pass,
    required this.ready,
    required this.reason,
  });

  final LiquidGlassRefractionPass pass;
  final bool ready;
  final String reason;

  @override
  String toString() =>
      '${pass.logTag}: ${ready ? 'ready' : 'NOT ready'}（$reason）';
}