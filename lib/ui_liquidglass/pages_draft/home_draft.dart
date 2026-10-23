// SPDX-License-Identifier: GPL-3.0-or-later
// =============================================================
// UI 重构暂存（排期 #23）
// 暂不编译不接入，接线方案见 docs/UI重构方案.md
// -------------------------------------------------------------
// 首页草案（UIdraft 线框①）：纯 mock 组装，无 controller，
// 顶栏 + 频道胶囊栏 + 双列视频流 + 底部浮动导航。
// =============================================================

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_top_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_floating_nav.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/ui_liquidglass/previews/mock_data.dart';

/// 首页草案：按线框①组装的暂存页面，暂不接入路由与状态管理。
///
/// 审视 A1 修复：草案固定亮色，LiquidGlassTheme 包根只会带来
/// "AnimatedBuilder 每帧重建整棵子树"的代价而无收益（Surface 无 Theme 祖先时
/// 回退的同值默认 token）——故移除；接线时按 README「动画纪律」第 1 条，
/// 以**每屏局部**的 Theme 作用域接入全局深浅主题。
class LiquidHomeDraft extends StatelessWidget {
  const LiquidHomeDraft({super.key});

  /// 视频卡片长按弹出的操作弹层（四项契约菜单）。
  Future<void> _showVideoSheet(BuildContext context) {
    return showLiquidActionSheet(
      context,
      title: '视频操作',
      items: const [
        LiquidActionSheetItem(label: '稍后再看', icon: LiquidIcons.history),
        LiquidActionSheetItem(label: '不感兴趣', icon: LiquidIcons.close),
        LiquidActionSheetItem(
          label: '拉黑作者',
          icon: LiquidIcons.delete,
          destructive: true,
        ),
        LiquidActionSheetItem(label: '访问作者', icon: LiquidIcons.explore),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 背景透明，交由页面容器/壁纸透出玻璃质感
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 主体：顶栏 → 频道胶囊栏 → 双列视频流
          Column(
            children: [
              const SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    LiquidTopBar(),
                    SizedBox(height: 4),
                    LiquidPillBar(items: mockChannels, selectedIndex: 1),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 96),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: mockVideos.length,
                    itemBuilder: (context, index) {
                      return LiquidVideoCard(
                        data: mockVideos[index],
                        onLongPress: () => _showVideoSheet(context),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          // 底部浮动导航（组件自带 bottomCenter 对齐 + 安全区留白）
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidFloatingNav(items: mockNavItems, selectedIndex: 0),
          ),
        ],
      ),
    );
  }
}
