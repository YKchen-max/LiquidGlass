// SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================================
// UI 重构暂存组件（排期 #23）
//
// 本目录（lib/ui_liquidglass/）为暂存代码，当前不参与编译、不接入主工程。
// 主任务完成后，本文件将迁移到 lib/common/widgets/liquid/ 并完成接线
// （长按视频卡片/评论弹出：稍后再看、不感兴趣、拉黑、访问作者等）。
//
// 组件：showLiquidActionSheet —— 长按操作弹层（线框①注释）
// 玻璃纪律：弹层属浮层容器，套 LiquidGlassPanel(thick)。
// ============================================================================

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

/// 操作弹层的单个条目。
class LiquidActionSheetItem {
  const LiquidActionSheetItem({
    required this.label,
    this.icon,
    this.onTap,
    this.destructive = false,
  });

  /// 条目文本，如 "稍后再看" / "不感兴趣" / "拉黑" / "访问作者"。
  final String label;

  /// 条目前置图标，可为 null（为 null 时不留图标空位，直接文字）。
  final IconData? icon;

  /// 点击回调；点击后先关闭弹层再触发。
  final VoidCallback? onTap;

  /// 是否为破坏性操作（拉黑类），红色文字。
  final bool destructive;
}

/// 防重入守卫：**同一时刻只允许一个操作弹层**。
///
/// 为什么用模块级布尔而不是 State/InheritedWidget：调用点是长按列表卡片这种
/// "到处都可能有"的位置，拿不到可靠的宿主状态；而弹层本身是**全屏模态**，
/// 两个 sheet 叠起来既不合法也会让第二次点击落到已死的旧层上。
/// 复位时机 = route 真正关闭（`whenComplete`，含 pop 与抛错两条路）。
bool _sheetOpen = false;

/// 测试接缝：复位防重入守卫（用例之间不串味；**生产不要调**）。
@visibleForTesting
void resetLiquidActionSheetGuard() => _sheetOpen = false;

/// 当前是否有操作弹层挂着（调试/接线自检用）。
bool get isLiquidActionSheetOpen => _sheetOpen;

/// 弹出液态玻璃风格的底部操作弹层。
///
/// 使用方式：
/// ```dart
/// showLiquidActionSheet(
///   context,
///   title: '视频操作',
///   items: const [
///     LiquidActionSheetItem(label: '稍后再看', icon: LiquidIcons.history),
///     LiquidActionSheetItem(label: '拉黑', icon: LiquidIcons.lock, destructive: true),
///   ],
/// );
/// ```
///
/// 审视 P2 修复三条：
///   1. **防重入**：已有 sheet 挂着时再次调用直接返回**已完成**的 Future（不叠第二层）；
///   2. **[useRootNavigator]**：默认 false（贴在调用方所在 Navigator，嵌套路由里不会盖到
///      整台设备上）。播放器/直播这类"自己起 Navigator"的页面若想让弹层压住全屏，
///      接线时显式传 true——**这条就是留给接线阶段评估的口子**（纪律 7 记录过）。
///   3. **键盘避让**：底部 padding 叠加 `MediaQuery.viewInsetsOf(context).bottom`，
///      弹层里将来挂"跳转到…"这类输入框时不会被软键盘顶掉。
Future<void> showLiquidActionSheet(
  BuildContext context, {
  required List<LiquidActionSheetItem> items,
  String? title,
  bool useRootNavigator = false,
}) {
  if (_sheetOpen) {
    // 重入：直接给一个已完成的 Future ⇒ 调用方的 await/then 语义不变（不会永远挂着）。
    return Future<void>.value();
  }
  _sheetOpen = true;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      // 审视 A3 修复：路由滑入/滑出期间 BackdropFilter 会每帧重采样背景
      // （Windows v1 走 Skia = 滑动区域每帧全量模糊，低端机必卡）。
      // 过渡期用 solid 档（零背景采样），route 动画走到 85% 后再挂真玻璃。
      final animation = ModalRoute.of(sheetContext)?.animation;
      // 审视 P2 修复（键盘）：viewInsets.bottom = 软键盘占用的高度。
      // 读它会在 sheet 的 Element 上挂住 MediaQuery 依赖 ⇒ 键盘升起/落下时这里重建。
      final viewInsetBottom = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + viewInsetBottom),
        child: AnimatedBuilder(
          animation: animation ?? kAlwaysCompleteAnimation,
          builder: (context, _) {
            final settled = (animation?.value ?? 1.0) > 0.85;
            return ConstrainedBox(
              // 审视 P1 修复：条目超一屏不得溢出（接线后菜单可达 6-8 项）
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: LiquidGlassPanel(
                material: settled ? LiquidGlassMaterial.thick : LiquidGlassMaterial.solid,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                  bottom: Radius.circular(28),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 拖拽条（视觉提示，无手势逻辑）。
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 标题（可选）。
                      if (title != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              // 同 _row：暗色档提亮（onSurfaceVariant 更暗）。
                              color: scheme.brightness == Brightness.dark
                                  ? Color.lerp(
                                      scheme.onSurfaceVariant,
                                      Colors.white,
                                      0.5,
                                    )!
                                  : scheme.onSurfaceVariant,
                              fontFamily: LiquidFontFamily.text,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 4),
                      const SizedBox(height: 8),
                      ...items.map((item) => _row(sheetContext, item)),
                      const SizedBox(height: 8),
                      // 取消行。
                      Center(
                        child: Semantics(
                          button: true,
                          label: '取消',
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text(
                              '取消',
                              style: TextStyle(fontFamily: LiquidFontFamily.text),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
    // 审视 P2 修复（防重入复位）：route 无论走哪条路关闭（点条目 pop、点遮罩、
    // 下滑拖关、builder 抛错）都放开守卫 ⇒ 下一次长按能正常弹。
    // `whenComplete` 对"正常完成"与"异常完成"都执行 ⇒ 守卫不会被一个崩掉的
    // builder 永久钉死（那会变成"以后再也弹不出来"的更难查的 bug）。
  ).whenComplete(() => _sheetOpen = false);
}

/// 构建单个操作行：图标（可选）+ 文本。
///
/// 点击后先关闭弹层（Navigator.pop），再触发条目自身的 onTap。
Widget _row(BuildContext context, LiquidActionSheetItem item) {
  final scheme = Theme.of(context).colorScheme;
  // 暗色主题 onSurface 被全局压暗 0.15（theme_utils.dart:212，纯黑底设计），
  // 贴深色玻璃后可读性差（验收③委托人目视确认"偏暗为真"）⇒ 菜单文字提一档。
  final color = item.destructive
      ? scheme.error
      : scheme.brightness == Brightness.dark
          ? Color.lerp(scheme.onSurface, Colors.white, 0.35)!
          : scheme.onSurface;

  return Semantics(
    button: true,
    label: item.label,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pop(context);
        item.onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            // icon 为空时不留空位，直接文字。
            if (item.icon != null) ...[
              Icon(item.icon, size: 20, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 15,
                  color: color,
                  fontFamily: LiquidFontFamily.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
