// SPDX-License-Identifier: GPL-3.0-or-later
//
// #24b 接线适配器（数据层）：把 PiliPlus 既有模型/接口翻译成
// `lib/common/widgets/liquid/` 组件的契约类型。
//
// 划界（docs/UI重构方案.md §0 纪律 2）：**controller 零改动**——本文件只读模型、
// 只调既有 http 接口，不碰任何 GetX controller；view 树重排时由页面侧调用这里。
//
// 菜单口径（2026-10-05 定）：稍后再看 = `UserHttp.toViewLater`、不感兴趣 =
// 交互对齐上游 video_popup_menu.dart（web API 不支持 reason 精细选择，
// 先弹「web端暂不支持精细选择」确认框：点踩=移除卡片 / 撤销=取消踩）、
// 访问作者 = `/member` 路由（parameters 约定同 pages/music/view.dart:369-372）；
// **拉黑不入菜单**——
// PiliPlus 仅有黑名单列表接口（`Api.blackLst`），无"加黑"API，不造半吊子入口
// （暂存期预览里的"拉黑作者"是 mock，接线时以此文件为准）。
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

/// 推荐/热门流模型 → 视频卡片契约。
///
/// 计数文案走 [NumUtils.numFormat]（与存量卡片同一格式化口径，不新造）；
/// 时长走 [DurationUtils.formatDuration]（秒 → mm:ss / h:mm:ss；非正数给空串——
/// 基类 `duration` 缺省 -1，直播/特殊卡不该显示"-0:01"这类鬼值）。
/// 注意基类字段口径：弹幕数叫 [BaseStat.danmu]（json 键才是 "danmaku"）；
/// `title/owner/stat` 是 non-null late（fromJson 缺失即上游既有雷区，不在此新兜底）。
LiquidVideoCardData liquidCardData(BaseRcmdVideoItemModel item) {
  return LiquidVideoCardData(
    title: item.title,
    coverUrl: item.cover ?? '',
    author: item.owner.name ?? '',
    playText: item.stat.view == null ? '' : NumUtils.numFormat(item.stat.view),
    danmakuText:
        item.stat.danmu == null ? '' : NumUtils.numFormat(item.stat.danmu),
    durationText:
        item.duration > 0 ? DurationUtils.formatDuration(item.duration) : '',
  );
}

/// 视频卡长按/更多菜单（线框①注释的四项契约里可落地的三项）。
///
/// [context] 弹「不感兴趣」确认框优先用的页面 context；为 null（单测）时退
/// `Get.context`，两边都拿不到则该项点了无效果（守卫 return）。
/// [onRemoved]：不感兴趣点踩成功后由调用方把卡片移出列表（沿用 rcmd 控制器
/// 既有的 `onRemove` 语义——适配器不碰控制器，只回调）。
List<LiquidActionSheetItem> liquidVideoMenuItems(
  BuildContext? context,
  BaseRcmdVideoItemModel item, {
  VoidCallback? onRemoved,
}) {
  final bvid = item.bvid;
  return <LiquidActionSheetItem>[
    LiquidActionSheetItem(
      label: '稍后再看',
      icon: LiquidIcons.history,
      onTap: bvid == null
          ? null
          : () async {
              final res = await UserHttp.toViewLater(bvid: bvid);
              SmartDialog.showToast(
                res is Success ? '已加入稍后再看' : '操作失败',
              );
            },
    ),
    LiquidActionSheetItem(
      label: '不感兴趣',
      icon: LiquidIcons.close,
      onTap: bvid == null
          ? null
          : () {
              // 交互对齐上游 video_popup_menu.dart（"web端暂不支持精细选择"）：
              // web API 不支持 reason 精细选择，先弹确认框由用户拍板——
              // 「点踩」减少推荐并移除卡片；「撤销」取消踩。
              // type 取值照抄上游调用（点踩 true / 撤销 false），与 http 层
              // `dislike: type ? '0' : '1'` 的映射保持一致，不自行发挥。
              // context 优先用外层捕获的页面 context（本回调触发时操作弹层已
              // pop，确认框挂在页面 Navigator 上，与上游弹在卡片同层同构）；
              // 为 null（单测）时退 Get.context，仍非 null 由守卫挡住。
              final dialogContext = context ?? Get.context;
              if (dialogContext == null) return;
              showDialog(
                context: dialogContext,
                builder: (dialogContext) => SimpleDialog(
                  contentPadding: const EdgeInsets.all(24),
                  children: [
                    const Center(child: Text('web端暂不支持精细选择')),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.tonal(
                          onPressed: () async {
                            Get.back();
                            SmartDialog.showLoading(msg: '正在提交');
                            final res = await VideoHttp.dislikeVideo(
                              bvid: bvid,
                              type: true,
                            );
                            SmartDialog.dismiss();
                            if (res is Success) {
                              SmartDialog.showToast('点踩成功');
                              onRemoved?.call();
                            } else {
                              SmartDialog.showToast('操作失败');
                            }
                          },
                          child: const Text('点踩'),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            Get.back();
                            SmartDialog.showLoading(msg: '正在提交');
                            final res = await VideoHttp.dislikeVideo(
                              bvid: bvid,
                              type: false,
                            );
                            SmartDialog.dismiss();
                            SmartDialog.showToast(
                              res is Success ? '取消踩' : '操作失败',
                            );
                          },
                          child: const Text('撤销'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
    ),
    // 上游 VideoCardV 的长按原是"存封面"（imageSaveDialog）——换菜单后该功能
    // 不丢，收进菜单第四项（#24b 功能守恒）。
    LiquidActionSheetItem(
      label: '保存封面',
      icon: LiquidIcons.download,
      onTap: () => imageSaveDialog(
        title: item.title,
        cover: item.cover,
        bvid: item.bvid,
      ),
    ),
    LiquidActionSheetItem(
      label: '访问作者',
      icon: LiquidIcons.explore,
      onTap: item.owner.mid == null
          ? null
          : () => Get.toNamed(
                '/member',
                parameters: {'mid': item.owner.mid!.toString()},
              ),
    ),
  ];
}

/// 推荐流卡片导航：**与 `VideoCardV.onPushDetail`（video_card_v.dart:33-80）逐字同行为**
/// （goto 四分叉：bangumi/av/picture/默认 uri）。#24b 换卡后导航入口在这里；
/// 上游 VideoCardV 不动（他页仍在用），两处靠本注释同步——改一分叉须同改两处。
Future<void> pushRcmdVideoDetail(BaseRcmdVideoItemModel videoItem) async {
  switch (videoItem.goto) {
    case 'bangumi':
      PageUtils.viewPgc(epId: videoItem.param!);
      break;
    case 'av':
      var bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid!);
      var cid = videoItem.cid;
      bool isVertical = false;
      Dimension? dimension;
      if (videoItem is RcmdVideoItemAppModel) {
        if (videoItem.uri case final uri?) {
          isVertical = uri.isVerticalFromUri;
        }
      }
      if (cid == null) {
        if (await SearchHttp.ab2cWithDimension(aid: videoItem.aid, bvid: bvid)
            case final res?) {
          cid = res.cid;
          dimension = res.dimension;
        }
      }
      if (cid != null) {
        PageUtils.toVideoPage(
          aid: videoItem.aid,
          bvid: bvid,
          cid: cid,
          cover: videoItem.cover,
          title: videoItem.title,
          isVertical: isVertical,
          dimension: dimension,
        );
      }
      break;
    // 动态
    case 'picture':
      try {
        PiliScheme.routePushFromUrl(videoItem.uri!);
      } catch (err) {
        SmartDialog.showToast(err.toString());
      }
      break;
    default:
      if (videoItem.uri?.isNotEmpty == true) {
        PiliScheme.routePushFromUrl(videoItem.uri!);
      }
  }
}

/// 频道行 labels → 胶囊行契约（id 用下标字符串，选中态由页面侧 TabController 给）。
List<LiquidPillBarItem> liquidChannelItems(List<String> labels) => <LiquidPillBarItem>[
      for (int i = 0; i < labels.length; i++)
        LiquidPillBarItem(id: '$i', label: labels[i]),
    ];
