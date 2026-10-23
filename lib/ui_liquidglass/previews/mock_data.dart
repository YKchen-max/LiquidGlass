// SPDX-License-Identifier: GPL-3.0-or-later
// =============================================================
// UI 重构暂存（排期 #23）
// 暂不编译不接入，接线方案见 docs/UI重构方案.md
// -------------------------------------------------------------
// 预览/草案共用的 const mock 数据，类型逐字消费组件契约。
// =============================================================

import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_floating_nav.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_comment_tile.dart';

/// 频道胶囊栏 mock：直播 / 推荐 / 热门 / 分区 / 番剧 / 影视。
/// 频道 icon 可省，仅给前两项示意性图标。
const List<LiquidPillBarItem> mockChannels = [
  LiquidPillBarItem(id: 'live', label: '直播', icon: LiquidIcons.live),
  LiquidPillBarItem(id: 'recommend', label: '推荐', icon: LiquidIcons.home),
  LiquidPillBarItem(id: 'hot', label: '热门'),
  LiquidPillBarItem(id: 'region', label: '分区'),
  LiquidPillBarItem(id: 'bangumi', label: '番剧'),
  LiquidPillBarItem(id: 'movie', label: '影视'),
];

/// 视频卡片 mock（6 条），标题/作者/播放量/弹幕数/时长为真实感中文内容。
/// coverUrl 一律空串 ⇒ 渲染内置 explore 占位（**不发任何网络请求**）。
/// 为什么不用假 URL：#24b 起卡片对非空 coverUrl 走真 NetworkImgLayer——
/// CachedNetworkImage（ce fork）在 widget test 的 fake-async 区会留下永久挂起
/// 操作、把 `flutter test` 吊死在 isolate 收尾（最小复现 + 15s 排水均实证）。
/// 预览页要演示真图加载时，临时换可达 URL 即可（勿提交进单测会跑的路径）。
const List<LiquidVideoCardData> mockVideos = [
  LiquidVideoCardData(
    title: '重启大脑前额叶，2小时让你轻松爱上学习！',
    coverUrl: '',
    author: '好蛙TV',
    playText: '37.4万',
    danmakuText: '914',
    durationText: '02:00:27',
  ),
  LiquidVideoCardData(
    title: '【4K修复】经典国漫高燃混剪，爷青回！',
    coverUrl: '',
    author: '剪辑师老张',
    playText: '128.6万',
    danmakuText: '3204',
    durationText: '12:36',
  ),
  LiquidVideoCardData(
    title: '花200元买了台"游戏掌机"，到手我直接愣住了',
    coverUrl: '',
    author: '数码评测君',
    playText: '89.2万',
    danmakuText: '1.2万',
    durationText: '18:42',
  ),
  LiquidVideoCardData(
    title: '挑战100元在日本吃一天，结局意想不到',
    coverUrl: '',
    author: '浪浪环游日记',
    playText: '56.1万',
    danmakuText: '2317',
    durationText: '22:08',
  ),
  LiquidVideoCardData(
    title: '程序员辞职转行卖煎饼果子，月入五万的真相',
    coverUrl: '',
    author: '阿凯说事儿',
    playText: '41.8万',
    danmakuText: '866',
    durationText: '15:20',
  ),
  LiquidVideoCardData(
    title: '猫咪第一次见到扫地机器人，反应太真实了哈哈哈',
    coverUrl: '',
    author: '毛孩子的日常',
    playText: '203.4万',
    danmakuText: '4521',
    durationText: '03:47',
  ),
];

/// 评论 mock（3 条）：第一条为 UP 主置顶（isUp: true、level: 6）。
const List<LiquidCommentData> mockComments = [
  LiquidCommentData(
    userName: '好蛙TV',
    content: '感谢大家的支持！完整版课件已经在动态里置顶，记得三连哦～',
    avatarUrl: 'https://placeholder.local/avatar_up.jpg',
    level: 6,
    isUp: true,
    likeCount: 12843,
    replyCount: 356,
    timeText: '3天前',
    isLiked: false,
  ),
  LiquidCommentData(
    userName: '学习五分钟',
    content: '看到第40分钟突然就坐不住了，起来背了二十个单词，有效！',
    avatarUrl: 'https://placeholder.local/avatar_02.jpg',
    level: 5,
    likeCount: 892,
    replyCount: 24,
    timeText: '2天前',
  ),
  LiquidCommentData(
    userName: '路过的咸鱼',
    content: '前排提示：01:12:35 有彩蛋，别问我怎么知道的。',
    level: 3,
    likeCount: 145,
    replyCount: 7,
    timeText: '昨天',
    isLiked: true,
  ),
];

/// 底部浮动导航 mock：首页 / 动态 / 我的。
const List<LiquidFloatingNavItem> mockNavItems = [
  LiquidFloatingNavItem(id: 'home', icon: LiquidIcons.home, label: '首页'),
  LiquidFloatingNavItem(id: 'dynamic', icon: LiquidIcons.dynamic, label: '动态'),
  LiquidFloatingNavItem(id: 'profile', icon: LiquidIcons.profile, label: '我的'),
];
