// SPDX-License-Identifier: GPL-3.0-or-later
//
// #27 U5 功能守恒绊线（源码文本扫描式，照 u26a_reply_kernel_conservation_test 范本）：
// 动态卡换装（外壳 liquid 化）**只许动 chrome**、我的页菜单搬家**只许搬不许丢**——
// 不渲染 widget（动态卡内核 20 个 panel + GetX 控制器跑不动也没必要 ✓），
// 只钉「这些符号/回调/入口还在源文件里」✓。
//
// 钉五面：
//   (a) 动态卡内核面：author/dispute/content/interaction/action/fold 六段装配
//       与长按/右键/点卡回调逐个 contains（外壳换成 LiquidSolidCard 后仍在全）；
//   (b) 互动面：action_panel 的 点赞/转发/评论 三回调 ＋ interaction 的 @ 跳转识别器；
//   (c) 内部 panel 零动：12 件 panel 文件在位 + 3 件 sentinel 符号在；
//   (d) 我的页功能清单：菜单组 A/B + 资料卡 + 收藏横滑的每个入口/回调逐个在
//       （以 PiliPlus 现有功能清单为验收基准，线框⑥只画了一半）；
//   (e) controller 三件零改动 sentinel + 新 liquid 文件 import 纪律
//       （零 flutter/material，S16 教训；目录级扫描另由 u25 组⑤兜）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relative) {
  final candidates = <String>[relative, 'app/$relative'];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('找不到 $relative（cwd=${Directory.current.path}）');
}

void _expectAll(String source, List<String> needles, String what) {
  final missing = needles.where((n) => !source.contains(n)).toList();
  expect(
    missing,
    isEmpty,
    reason: '$what：以下符号在源文件里找不到了 ⇒ 换装/搬家吃掉了功能面 ✗：$missing',
  );
}

void main() {
  final dynamicPanel = _read('lib/pages/dynamics/widgets/dynamic_panel.dart');
  final actionPanel = _read('lib/pages/dynamics/widgets/action_panel.dart');
  final interaction = _read('lib/pages/dynamics/widgets/interaction.dart');
  final modulePanel = _read('lib/pages/dynamics/widgets/module_panel.dart');
  final videoPanel = _read('lib/pages/dynamics/widgets/video_panel.dart');
  final authorPanel = _read('lib/pages/dynamics/widgets/author_panel.dart');
  final dynView = _read('lib/pages/dynamics/view.dart');
  final mineView = _read('lib/pages/mine/view.dart');
  final dynController = _read('lib/pages/dynamics/controller.dart');
  final tabController = _read('lib/pages/dynamics_tab/controller.dart');
  final mineController = _read('lib/pages/mine/controller.dart');

  group('#27 守恒绊线①：动态卡内核面不得被换装切掉', () {
    test('六段装配 + 点卡/长按/右键回调全在', () {
      _expectAll(dynamicPanel, [
        'AuthorPanel(', // 作者行（含 more panel 入口）
        '_buildDispute(theme, moduleDispute)', // 争议条
        'dynContent(', // 内容 panel 分发（20 件内部 panel 的总入口）
        'dynInteraction(', // 互动提示行
        'ActionPanel(item: item)', // 点赞/转发/评论行
        '_buildFoldItem(theme, moduleFold)', // 折叠展开行
        'onLongPress: showMore', // 长按更多
        'onSecondaryTap:', // 桌面右键更多
        'PageUtils.pushDynDetail(item)', // 点卡进详情
        'LiquidSolidCard(', // 新壳在位（chrome 换装本体）
        'LiquidPressable', // 壳内按压由 LiquidSolidCard 挂（经其源码间接钉）
      ], 'dynamic_panel.dart 内核面');
      // 内核段数量提示：dynContent 调用仅 1 处（装配点唯一，未被复制/搬走）
      expect(RegExp(r'dynContent\(').allMatches(dynamicPanel).length, 1);
    });

    test('互动面：点赞/转发/评论三回调 + @ 跳转识别器在', () {
      _expectAll(actionPanel, [
        'RequestUtils.onLikeDynamic', // 点赞
        'RepostPanel(', // 转发弹层
        'viewComment: true', // 评论跳转
        'semanticLabel: "转发"',
        'semanticLabel: "评论"',
      ], 'action_panel.dart 互动面');
      _expectAll(interaction, [
        'NoDeadlineTapGestureRecognizer', // @ 用户跳转识别器
        "Get.toNamed('/member?mid=", // @ 跳转路由
      ], 'interaction.dart @ 面');
    });

    test('内部 20 panel 零动：文件在位 + sentinel 符号在', () {
      const panels = [
        'lib/pages/dynamics/widgets/video_panel.dart',
        'lib/pages/dynamics/widgets/author_panel.dart',
        'lib/pages/dynamics/widgets/vote.dart',
        'lib/pages/dynamics/widgets/vote_decoration.dart',
        'lib/pages/dynamics/widgets/rich_node_panel.dart',
        'lib/pages/dynamics/widgets/forward_panel.dart',
        'lib/pages/dynamics/widgets/live_panel.dart',
        'lib/pages/dynamics/widgets/live_panel_sub.dart',
        'lib/pages/dynamics/widgets/live_rcmd_panel.dart',
        'lib/pages/dynamics/widgets/up_panel.dart',
        'lib/pages/dynamics/widgets/content_panel.dart',
        'lib/pages/dynamics/widgets/additional_panel.dart',
        'lib/pages/dynamics/widgets/blocked_item.dart',
        'lib/pages/dynamics/widgets/dyn_content.dart',
        'lib/pages/dynamics/widgets/module_panel.dart',
        'lib/pages/dynamics/widgets/interaction.dart',
        'lib/pages/dynamics/widgets/action_panel.dart',
      ];
      for (final p in panels) {
        expect(File(p).existsSync() || File('app/$p').existsSync(), isTrue,
            reason: '内部 panel 文件消失 ⇒ 换装越界 ✗：$p');
      }
      _expectAll(modulePanel, ['Widget module('], 'module_panel sentinel');
      _expectAll(videoPanel, ['videoSeasonWidget('], 'video_panel sentinel');
      _expectAll(authorPanel, ['class AuthorPanel'], 'author_panel sentinel');
    });
  });

  group('#27 守恒绊线②：动态页 tab/发布入口', () {
    test('pill 行双向同步 + 发布回调 + 玻璃预算案 A 在', () {
      _expectAll(dynView, [
        'DynamicsTabType.values', // tab 数据源未硬编码
        'tabBarView(', // 页视图仍接同一 TabController
        'LiquidTabPillBar(', // 新 pill 行在位
        'selectionGlass: false', // 案 A：选中片退 solid（本屏预算＝主底导 1）
        '_dynamicsController.tabController', // 控制器零改动接线
        'animateToTop', // 原 TabBar.onTap 回顶语义保留
        'CreateDynPanel.onCreateDyn(context)', // 发布回调零改
        "tooltip: '发布动态'", // 发布钮语义保留
      ], 'dynamics/view.dart');
    });
  });

  group('#27 守恒绊线③：我的页功能清单逐项（线框⑥半图 ⇒ 以现有清单为基准）', () {
    test('菜单组 A：controller.list 四条 + 收藏行全语义在', () {
      _expectAll(mineView, [
        'for (final e in controller.list)', // 四条入口遍历零硬编码
        'LiquidMenuTile(icon: e.icon, label: e.title, onTap: e.onTap)',
        "Get.toNamed('/fav')", // 收藏行跳转
        '_autoRefresh', // 收藏跳回刷新语义
        "tooltip: '刷新'", // 收藏行 trailing 刷新钮
        'controller.onRefresh', // 刷新回调零改
        'controller.favFolderCount', // 文件夹计数
        'FavFolderItem(', // 收藏横滑列表零改
        'controller.scrollController', // 横滑控制器零改
      ], 'mine/view.dart 菜单组 A + 收藏');
    });

    test('菜单组 B：评论记录/无痕/切换账号/主题/设置五入口在（回调零改）', () {
      _expectAll(mineView, [
        "Get.toNamed('/myReply')", // 评论记录
        'MineController.onChangeAnonymity', // 无痕开关
        'MineController.anonymity.value', // 无痕状态反应式
        'LoginPageController.switchAccountDialog(context)', // 切换账号
        'controller.onChangeTheme', // 主题切换
        'controller.nextThemeType.label', // 主题 tooltip 语义
        "Get.toNamed('/setting', preventDuplicates: false)", // 设置
        'GStorage.reply != null', // 评论记录条件门保留
      ], 'mine/view.dart 菜单组 B');
    });

    test('资料卡：NetworkImgLayer 头像 + 昵称/等级/VIP/硬币经验/三统计在', () {
      _expectAll(mineView, [
        'NetworkImgLayer(', // T8 口径：不直连 cached_network_image
        "userInfo.uname ?? '点击登录'",
        'BiliUtils.levelPicture(', // 等级徽标
        'Assets.vipIcon', // 大会员挂件
        'controller.onLogin', // 点/长按登录契约
        "controller.push('memberDynamics')", // 动态统计
        "controller.push('follow')", // 关注统计
        "controller.push('fan')", // 粉丝统计
        'LiquidSolidCard(', // 资料卡 liquid 壳在位
      ], 'mine/view.dart 资料卡');
    });

    test('顶栏瘦身后搜索/消息徽标仍在（wireframe ⑥ slim top bar）', () {
      _expectAll(mineView, [
        "Get.toNamed('/search')",
        'msgBadge(_mainController)',
        '_mainController.hasHome',
      ], 'mine/view.dart 顶栏');
    });
  });

  group('#27 守恒绊线④：controller 三件零改动 sentinel', () {
    test('dynamics / dynamics_tab / mine controller 业务面在', () {
      _expectAll(dynController, [
        'tabController',
        'animateToTop',
        'upPanelPosition',
        'singleRefresh',
      ], 'dynamics/controller.dart');
      _expectAll(tabController, [
        'class DynamicsTabController',
        'onRefresh',
        'onRemove',
        'onBlock',
        'onUnfold',
      ], 'dynamics_tab/controller.dart');
      _expectAll(mineController, [
        'late final list', // 菜单数据源（4 条）未动
        'static void onChangeAnonymity',
        'void onChangeTheme',
        'void push(String name)',
        'void onLogin',
        'favFolderCount',
      ], 'mine/controller.dart');
    });
  });

  group('#27 守恒绊线⑤：新 liquid 文件 import 纪律（S16 教训）', () {
    test('四件新组件零 flutter/material 引用且引 material_ui', () {
      const files = [
        'lib/common/widgets/liquid/liquid_tab_pill_bar.dart',
        'lib/common/widgets/liquid/liquid_solid_card.dart',
        'lib/common/widgets/liquid/liquid_menu_tile.dart',
        'lib/common/widgets/liquid/liquid_floating_button.dart',
      ];
      for (final f in files) {
        final src = _read(f);
        expect(src.contains('package:flutter/material.dart'), isFalse,
            reason: '$f 引了 flutter/material ⇒ S16 黑字糊黑卡雷 ✗');
        expect(src.contains('package:material_ui/material_ui.dart'), isTrue,
            reason: '$f 未引 fork material_ui ✗');
      }
      // 目录级零 flutter/material 另由 u25_search_wiring_test 组⑤ 全目录扫兜底。
    });
  });
}
