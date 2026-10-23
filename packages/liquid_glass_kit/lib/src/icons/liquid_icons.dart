// SPDX-License-Identifier: GPL-3.0-or-later
//
// 本文件由 tool/build_fonts.py 从 tool/icons.yaml 自动生成，请勿手改。
// 图标字体：Material Symbols Rounded（Apache-2.0）与 Lucide（ISC）的子集，
// 许可证原文见 packages/liquid_glass_kit/assets/fonts/LICENSES/。
//
// 用法：Icon(LiquidIcons.home, size: 20)  /  Icon(LucideIcons.home)
// 两个类用**同一套语义名**（清单左侧），便于在两种风格间切换而不改业务代码。
//
// 常量名刻意用 snake_case：与 icons.yaml 的键一一对应，跨文件搜索不会错位。
// ignore_for_file: constant_identifier_names

import 'package:flutter/widgets.dart';

/// Material Symbols Rounded 子集（UI 主图标集）
abstract final class LiquidIcons {
  static const String family = 'LiquidIcons';
  static const String fontPackage = 'liquid_glass_kit';
  static const IconData add = IconData(0xe145, fontFamily: family, fontPackage: fontPackage);
  static const IconData back = IconData(0xe5c4, fontFamily: family, fontPackage: fontPackage);
  static const IconData cast = IconData(0xe307, fontFamily: family, fontPackage: fontPackage);
  static const IconData check = IconData(0xe668, fontFamily: family, fontPackage: fontPackage);
  static const IconData chevron_right = IconData(0xe5cc, fontFamily: family, fontPackage: fontPackage);
  static const IconData close = IconData(0xe5cd, fontFamily: family, fontPackage: fontPackage);
  static const IconData danmaku = IconData(0xe048, fontFamily: family, fontPackage: fontPackage);
  static const IconData dark = IconData(0xe51c, fontFamily: family, fontPackage: fontPackage);
  static const IconData delete = IconData(0xe92e, fontFamily: family, fontPackage: fontPackage);
  static const IconData download = IconData(0xf090, fontFamily: family, fontPackage: fontPackage);
  static const IconData dynamic = IconData(0xea14, fontFamily: family, fontPackage: fontPackage);
  static const IconData edit = IconData(0xf097, fontFamily: family, fontPackage: fontPackage);
  static const IconData explore = IconData(0xe87a, fontFamily: family, fontPackage: fontPackage);
  static const IconData folder = IconData(0xe2c7, fontFamily: family, fontPackage: fontPackage);
  static const IconData forward = IconData(0xe5c8, fontFamily: family, fontPackage: fontPackage);
  static const IconData fullscreen = IconData(0xe5d0, fontFamily: family, fontPackage: fontPackage);
  static const IconData glass = IconData(0xe3a5, fontFamily: family, fontPackage: fontPackage);
  static const IconData history = IconData(0xe8b3, fontFamily: family, fontPackage: fontPackage);
  static const IconData home = IconData(0xe9b2, fontFamily: family, fontPackage: fontPackage);
  static const IconData light = IconData(0xe518, fontFamily: family, fontPackage: fontPackage);
  static const IconData like = IconData(0xf577, fontFamily: family, fontPackage: fontPackage);
  static const IconData list = IconData(0xe241, fontFamily: family, fontPackage: fontPackage);
  static const IconData live = IconData(0xe63a, fontFamily: family, fontPackage: fontPackage);
  static const IconData lock = IconData(0xe899, fontFamily: family, fontPackage: fontPackage);
  static const IconData message = IconData(0xe0cb, fontFamily: family, fontPackage: fontPackage);
  static const IconData more = IconData(0xe5d3, fontFamily: family, fontPackage: fontPackage);
  static const IconData notifications = IconData(0xe7f5, fontFamily: family, fontPackage: fontPackage);
  static const IconData pause = IconData(0xe034, fontFamily: family, fontPackage: fontPackage);
  static const IconData pip = IconData(0xe911, fontFamily: family, fontPackage: fontPackage);
  static const IconData play = IconData(0xe037, fontFamily: family, fontPackage: fontPackage);
  static const IconData profile = IconData(0xf0d3, fontFamily: family, fontPackage: fontPackage);
  static const IconData refresh = IconData(0xe5d5, fontFamily: family, fontPackage: fontPackage);
  static const IconData search = IconData(0xef7a, fontFamily: family, fontPackage: fontPackage);
  static const IconData settings = IconData(0xe8b8, fontFamily: family, fontPackage: fontPackage);
  static const IconData share = IconData(0xe80d, fontFamily: family, fontPackage: fontPackage);
  static const IconData speed = IconData(0xe9e4, fontFamily: family, fontPackage: fontPackage);
  static const IconData star = IconData(0xf09a, fontFamily: family, fontPackage: fontPackage);
  static const IconData visibility = IconData(0xe8f4, fontFamily: family, fontPackage: fontPackage);
  static const IconData volume = IconData(0xe050, fontFamily: family, fontPackage: fontPackage);
}

/// Lucide 子集（线性风格图标，用于强调/空状态等场景）
abstract final class LucideIcons {
  static const String family = 'LucideIcons';
  static const String fontPackage = 'liquid_glass_kit';
  static const IconData add = IconData(0xe13d, fontFamily: family, fontPackage: fontPackage);
  static const IconData back = IconData(0xe048, fontFamily: family, fontPackage: fontPackage);
  static const IconData cast = IconData(0xe066, fontFamily: family, fontPackage: fontPackage);
  static const IconData check = IconData(0xe06c, fontFamily: family, fontPackage: fontPackage);
  static const IconData chevron_right = IconData(0xe06f, fontFamily: family, fontPackage: fontPackage);
  static const IconData close = IconData(0xe1b2, fontFamily: family, fontPackage: fontPackage);
  static const IconData danmaku = IconData(0xe3a4, fontFamily: family, fontPackage: fontPackage);
  static const IconData dark = IconData(0xe11e, fontFamily: family, fontPackage: fontPackage);
  static const IconData delete = IconData(0xe18e, fontFamily: family, fontPackage: fontPackage);
  static const IconData download = IconData(0xe0b2, fontFamily: family, fontPackage: fontPackage);
  static const IconData dynamic = IconData(0xe348, fontFamily: family, fontPackage: fontPackage);
  static const IconData edit = IconData(0xe1f9, fontFamily: family, fontPackage: fontPackage);
  static const IconData explore = IconData(0xe09b, fontFamily: family, fontPackage: fontPackage);
  static const IconData folder = IconData(0xe0d7, fontFamily: family, fontPackage: fontPackage);
  static const IconData forward = IconData(0xe049, fontFamily: family, fontPackage: fontPackage);
  static const IconData fullscreen = IconData(0xe112, fontFamily: family, fontPackage: fontPackage);
  static const IconData glass = IconData(0xe529, fontFamily: family, fontPackage: fontPackage);
  static const IconData history = IconData(0xe1f5, fontFamily: family, fontPackage: fontPackage);
  static const IconData home = IconData(0xe0f5, fontFamily: family, fontPackage: fontPackage);
  static const IconData light = IconData(0xe178, fontFamily: family, fontPackage: fontPackage);
  static const IconData like = IconData(0xe18a, fontFamily: family, fontPackage: fontPackage);
  static const IconData list = IconData(0xe106, fontFamily: family, fontPackage: fontPackage);
  static const IconData live = IconData(0xe195, fontFamily: family, fontPackage: fontPackage);
  static const IconData lock = IconData(0xe10b, fontFamily: family, fontPackage: fontPackage);
  static const IconData message = IconData(0xe116, fontFamily: family, fontPackage: fontPackage);
  static const IconData more = IconData(0xe0b6, fontFamily: family, fontPackage: fontPackage);
  static const IconData notifications = IconData(0xe059, fontFamily: family, fontPackage: fontPackage);
  static const IconData pause = IconData(0xe12e, fontFamily: family, fontPackage: fontPackage);
  static const IconData pip = IconData(0xe3af, fontFamily: family, fontPackage: fontPackage);
  static const IconData play = IconData(0xe13c, fontFamily: family, fontPackage: fontPackage);
  static const IconData profile = IconData(0xe19f, fontFamily: family, fontPackage: fontPackage);
  static const IconData refresh = IconData(0xe145, fontFamily: family, fontPackage: fontPackage);
  static const IconData search = IconData(0xe151, fontFamily: family, fontPackage: fontPackage);
  static const IconData settings = IconData(0xe154, fontFamily: family, fontPackage: fontPackage);
  static const IconData share = IconData(0xe156, fontFamily: family, fontPackage: fontPackage);
  static const IconData speed = IconData(0xe1bf, fontFamily: family, fontPackage: fontPackage);
  static const IconData star = IconData(0xe176, fontFamily: family, fontPackage: fontPackage);
  static const IconData visibility = IconData(0xe0ba, fontFamily: family, fontPackage: fontPackage);
  static const IconData volume = IconData(0xe1ab, fontFamily: family, fontPackage: fontPackage);
}
