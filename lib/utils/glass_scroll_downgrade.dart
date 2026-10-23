// SPDX-License-Identifier: GPL-3.0-or-later
//
// 滚动降档（立项 docs/立项-rcmd滚动成本优化-20261006.md 案 A）：
// 滚动活动期把"导航/顶栏功能层玻璃"从 regular 临时降到 solid（零背景采样），
// 静止后经滞回恢复。与"播放态=solid"同族的时机策略——敌人①（BackdropFilter
// 每帧重采样背景）只在运动窗口里付费。
//
// 触发口径偏离草案一处（如实记）：草案写"速度阈值"，实现用**任意滚动活动**——
// 成本驱动是"有滚动帧 ⇒ 玻璃每帧重采样"，与速度快慢无关，慢滚同样全价；
// 速度阈值只会减少降档生效时间而不省成本。滞回保留（300ms 防边界抖动）。
//
// 划界：纯 app 侧单例（view/policy 层），**零 kit 改动、零上游业务文件改动**；
// 触发器 = NotificationListener 冒泡（controller 零改动）。
import 'dart:async';

import 'package:flutter/foundation.dart';

class GlassScrollDowngrade {
  GlassScrollDowngrade._();

  static final GlassScrollDowngrade instance = GlassScrollDowngrade._();

  /// true = 滚动活动窗口内（功能层玻璃应降 solid）。
  final ValueNotifier<bool> scrolling = ValueNotifier<bool>(false);

  /// 静止滞回：最后一次滚动活动后该时长内仍视为滚动中（防边界抖动）。
  ///
  /// 首版 300ms 在**点划式驱动**下被间隙击穿（A1 实测 `[GlassScroll] on/off`
  /// 每 ~500ms 翻一次 ⇒ 每次翻 = 200ms 交叉淡入双图层 ✗）⇒ 取 700ms：
  /// 桥得住"划-停-划"的间隙（手指间歇 ~0.5s）、停手 0.7s 内恢复玻璃仍接近即时。
  static const Duration idleHysteresis = Duration(milliseconds: 700);

  Timer? _idleTimer;

  /// 滚动活动心跳（NotificationListener 每次 ScrollNotification 调一次）。
  void noteActivity() {
    _idleTimer?.cancel();
    if (!scrolling.value) {
      scrolling.value = true;
      // 只在跳变沿写一行（§103 族：取证截图里档位要可归属；低频沿写，不刷频 ✓）。
      debugPrint('[GlassScroll] downgrade=on');
    }
    _idleTimer = Timer(idleHysteresis, () {
      scrolling.value = false;
      debugPrint('[GlassScroll] downgrade=off');
    });
  }

  /// 测试接缝：清计时器与状态（否则 Timer 挂到用例结束 / 用例间串扰）。
  @visibleForTesting
  void debugReset() {
    _idleTimer?.cancel();
    _idleTimer = null;
    scrolling.value = false;
  }
}
