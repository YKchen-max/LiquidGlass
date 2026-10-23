// SPDX-License-Identifier: GPL-3.0-or-later
//
// #24b 封面接线绊线（2026-10-05）：钉 LiquidVideoCard 封面走 NetworkImgLayer。
//
// 背景：#24b 验收实测发现封面停留在暂存期"不发请求的占位"（`coverUrl` 收了
// 不渲染）⇒ 首页推荐流全卡无图。widget test 里挂载真 CachedNetworkImage 会把
// `flutter test` 吊死在 isolate 收尾（进程不退出 ⇒ 门禁超时；已实证：最小复现
// + 15s 真实循环排水均无效 ⇒ 永久挂起操作），故按 S15 同款**源码文本绊线**钉
// 住接线口径（审查 T8：视频卡封面 = NetworkImgLayer，不新增依赖）：
//   ① import 存在（换渲染组件时绊线红 ⇒ 必须人来读这份背景再改）；
//   ② NetworkImgLayer 的 src 绑定 data.coverUrl（占位回归 ⇒ 红）；
//   ③ 空 coverUrl 不发请求的内置占位分支仍在（兜 upstream 模型缺图字段）。
// 组件行为（布局/按压/手势）由 liquid_ui_components_test.dart 覆盖；
// 真实出图由 #24b 双端目视验收的截图证据兜底。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('#24b 封面接线绊线：LiquidVideoCard 封面 = NetworkImgLayer(src: data.coverUrl)', () {
    final src = File(
      'lib/common/widgets/liquid/liquid_video_card.dart',
    ).readAsStringSync();

    expect(
      src.contains("import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';"),
      isTrue,
      reason: '封面必须走 NetworkImgLayer（上游 VideoCardV 同一渲染口径，审查 T8）——'
          '缺 import ⇒ 封面又退回不发请求的占位（#24b 验收实测翻过一次车：'
          '首页推荐流全卡无图）。若有意更换渲染组件：先读本文件头注释，并同步改绊线。',
    );

    expect(
      src.contains('NetworkImgLayer(') && src.contains('src: data.coverUrl'),
      isTrue,
      reason: 'coverUrl 收了必须渲染：src 必须绑定 data.coverUrl。'
          '删占位回归（占位不读 coverUrl）会在这里被抓住。',
    );

    expect(
      src.contains('data.coverUrl.isNotEmpty'),
      isTrue,
      reason: '空 coverUrl（上游模型缺图字段）必须走内置占位、连请求都不发——'
          '这个守卫分支不许删。',
    );
  });
}
