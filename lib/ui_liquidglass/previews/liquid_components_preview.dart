// SPDX-License-Identifier: GPL-3.0-or-later
// =============================================================
// UI 重构暂存（排期 #23）
// 暂不编译不接入，接线方案见 docs/UI重构方案.md
// -------------------------------------------------------------
// Liquid Glass 组件全家桶预览页：顶栏 / 胶囊栏 / 视频卡片 /
// 评论 / 操作弹层 / 浮动导航，附明暗切换与玻璃折射装饰背景。
// =============================================================

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_top_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_floating_nav.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_comment_tile.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';
import 'package:PiliPlus/ui_liquidglass/previews/mock_data.dart';

/// 浮动导航的"占位高度"（组件默认 height 64 + 自带底部留白 12 + 安全区），
/// 预览页用它把切换按钮顶到导航上方，避免热区重叠。
const double _kFloatingNavBodyHeight = 64;

/// 组件预览页：滚动浏览全部暂存组件，右下角浮动钮可切换明暗
/// （刻意避开顶栏头像与底部导航的热区，见 build 里第 4 条注释）。
class LiquidComponentsPreviewPage extends StatefulWidget {
  const LiquidComponentsPreviewPage({super.key});

  @override
  State<LiquidComponentsPreviewPage> createState() =>
      _LiquidComponentsPreviewPageState();
}

class _LiquidComponentsPreviewPageState
    extends State<LiquidComponentsPreviewPage> {
  /// 当前主题亮度（显式传给 LiquidGlassTheme 以启用 200ms 插值）。
  Brightness _brightness = Brightness.light;

  /// 胶囊栏当前选中频道。
  int _channelIndex = 1;

  /// 浮动导航当前选中项。
  int _navIndex = 0;

  /// 动效小节里最后一次被点到的示例（用来验证"包了按压反馈后 child 的 onTap 仍生效"）。
  String? _lastPress;

  /// 视频卡片长按 / 按钮弹出的操作弹层（四项契约菜单）。
  Future<void> _showVideoSheet() {
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

  /// 区块小标题（12 号、onSurfaceVariant）。
  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 装饰背景：双色渐变 + 三个彩色圆形，制造明暗混排内容，
  /// 用于观察玻璃材质的折射与模糊效果。
  Widget _buildBackdrop() {
    // 全 const 子树（DecoratedBox 代替"只有 decoration 的 Container"，lint 同款要求）。
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B3A67), Color(0xFFB7D3E8)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 90,
              left: -50,
              child: _BackdropCircle(size: 190, color: Color(0xFFFF7AB8)),
            ),
            Positioned(
              top: 320,
              right: -60,
              child: _BackdropCircle(size: 220, color: Color(0xFFFFC46B)),
            ),
            Positioned(
              bottom: 120,
              left: 40,
              child: _BackdropCircle(size: 160, color: Color(0xFF6BE3C2)),
            ),
          ],
        ),
      ),
    );
  }

  /// 双列视频卡片网格（不可滚动，交由外层 SingleChildScrollView）。
  Widget _buildVideoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
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
          onLongPress: _showVideoSheet,
        );
      },
    );
  }

  /// 三条 mock 评论。
  Widget _buildComments() {
    return Column(
      children: [
        for (final comment in mockComments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LiquidCommentTile(data: comment),
          ),
      ],
    );
  }

  /// 动效小节：三块不同 `pressedScale` 的按压示例。
  ///
  /// 目视要点（[LiquidPressable] 的手感参数）：
  ///   * 按下 90ms `Curves.easeOut` 缩到底、抬手 380ms 走 [kLiquidSpringCurve]
  ///     —— 过冲段会**弹过静止值**再落回，这就是"果冻"；
  ///   * 目标越小要缩得越狠（0.90 明显 / 0.99 几乎无感），别一刀切；
  ///   * 下面那行文字用来验证 child 的 `onTap` **仍然工作**：
  ///     LiquidPressable 用 Listener 旁路收指针、不进手势竞技场，
  ///     所以包一层不会抢走卡片自己的点击/长按（接线时的关键前提）。
  /// 减弱动效开关打开时，这里会**直接阶跃**到位（无过冲），也在此页可对照观察。
  Widget _buildPressDemo(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const entries = <(String, double)>[
      ('微 0.99', 0.99),
      ('标准 0.96', 0.96),
      ('强 0.90', 0.90),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (int i = 0; i < entries.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == entries.length - 1 ? 0 : 10),
                  child: LiquidPressable(
                    pressedScale: entries[i].$2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _lastPress = entries[i].$1),
                      child: Container(
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          entries[i].$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: LiquidFontFamily.text,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _lastPress == null ? '按任意一块：会缩一下再弹回来' : '最近按压：$_lastPress',
          style: TextStyle(
            fontSize: 11,
            fontFamily: LiquidFontFamily.text,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LiquidGlassTheme(
        // 预览页故意把 Theme 包到整页：本页就是用来观察 200ms 插值的。
        // ⚠️ 接线纪律（审视 A1）：真实页面里 LiquidGlassTheme 只允许包"玻璃组件群"
        // 或单屏局部——AnimatedBuilder 每帧重建的是它的整棵 child 子树，包根 = 换肤时全页重建。
        brightness: _brightness,
        child: Stack(
          children: [
            // 1. 装饰背景（渐变 + 彩色圆形）
            _buildBackdrop(),
            // 2. 内容滚动区
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(context, '顶栏 LiquidTopBar'),
                    const LiquidTopBar(),
                    _sectionTitle(context, '频道胶囊栏 LiquidPillBar'),
                    LiquidPillBar(
                      items: mockChannels,
                      selectedIndex: _channelIndex,
                      onSelected: (index) {
                        setState(() => _channelIndex = index);
                      },
                    ),
                    _sectionTitle(context, '视频卡片 LiquidVideoCard（长按弹菜单）'),
                    _buildVideoGrid(),
                    _sectionTitle(context, '评论 LiquidCommentTile'),
                    _buildComments(),
                    _sectionTitle(context, '操作弹层 showLiquidActionSheet'),
                    ElevatedButton(
                      onPressed: _showVideoSheet,
                      child: const Text('打开操作弹层'),
                    ),
                    _sectionTitle(context, '动效 LiquidPressable（按住看回弹）'),
                    _buildPressDemo(context),
                    // 底部留白，避免内容被浮动导航遮挡
                    const SizedBox(height: 110),
                  ],
                ),
              ),
            ),
            // 3. 底部浮动导航（组件自带 bottomCenter 对齐与底部间距）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LiquidFloatingNav(
                items: mockNavItems,
                selectedIndex: _navIndex,
                onSelected: (index) {
                  setState(() => _navIndex = index);
                },
              ),
            ),
            // 4. 明暗切换浮动按钮
            //    审视 P2 修复（"右上角明暗钮与 TopBar 头像热区重叠"）：
            //    原来挂在 top:48 / right:16 —— 那个位置正是顶栏玻璃条右端的头像命中区，
            //    两个可点热区叠在一起（后放的在上），点头像会点成切主题。
            //    现在挪到**右下角、浮动导航正上方**：顶栏热区与导航条热区都不碰，
            //    底部留白也让开安全区（12 + viewPadding + 导航本体高 + 12 呼吸位）。
            Positioned(
              right: 16,
              bottom:
                  12 +
                  MediaQuery.viewPaddingOf(context).bottom +
                  _kFloatingNavBodyHeight +
                  12,
              child: LiquidPressable(
                pressedScale: 0.92,
                child: Semantics(
                  button: true,
                  // hint 用"切换明暗主题。"（句号 + 连接词，标点纪律）；
                  // label 保持短语。
                  label: '明暗切换',
                  hint: '切换明暗主题。',
                  child: GestureDetector(
                    key: const ValueKey<String>('preview-theme-toggle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _brightness = _brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark;
                      });
                    },
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        _brightness == Brightness.dark
                            ? LiquidIcons.light
                            : LiquidIcons.dark,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 背景装饰圆形（纯 const 绘制，不依赖图片资源）。
class _BackdropCircle extends StatelessWidget {
  const _BackdropCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.75),
      ),
    );
  }
}

/// 预览页路由入口（MaterialPageRoute）。
Route<void> liquidComponentsPreviewRoute() {
  return MaterialPageRoute<void>(
    builder: (context) => const LiquidComponentsPreviewPage(),
  );
}
