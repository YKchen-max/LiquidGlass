import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_rcmd_adapters.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/debug/glass_frame_timing.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/home/glass_layout.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final controller = Get.put(RcmdController());

  @override
  bool get wantKeepAlive => true;

  // A1（#25 帧延迟对照验收）FT 接缝：仅在 GLASS_FRAME_TIMING 计时包里有行为
  //（glassFrameTimingEnabled 是编译期常量 ⇒ 常规构建零行为、树形状两臂一致）。
  // 首滚起 35 s 窗口；探针 = "近 800 ms 内有滚动通知"（NotificationListener
  // 冒泡捕获 ⇒ controller 零改动）；单例"已在采样"守卫 ⇒ 一进程一窗 ✓。
  int _ftLastScrollUs = 0;
  bool _ftStarted = false;

  void _ftOnScroll() {
    if (!glassFrameTimingEnabled) {
      return;
    }
    _ftLastScrollUs = DateTime.now().microsecondsSinceEpoch;
    if (_ftStarted) {
      return;
    }
    _ftStarted = true;
    GlassFrameTiming.instance.start(
      window: const Duration(seconds: 35),
      label: 'rcmd-scroll',
      note: 'A1 成对窗（#25 验收）：列表滚动帧延迟；arm=rcmd-scroll',
      scenarioProbe: () =>
          DateTime.now().microsecondsSinceEpoch - _ftLastScrollUs < 800000,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);
    return Container(
      clipBehavior: .hardEdge,
      margin: const .symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _ftOnScroll();
          return false;
        },
        child: refreshIndicator(
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 漂浮式（U2）：顶栏覆盖在内容之上，这里留出顶栏展开态高度的空白，
            // 滚动时卡片从玻璃底下穿过。纯色档 / 折叠模式返回 null → 控件树与上游一致。
            ?HomeGlassInset.sliverSpacer(context),
            SliverPadding(
              padding: const .only(top: Style.cardSpace, bottom: 100),
              sliver: Obx(
                () => _buildBody(colorScheme, controller.loadingState.value),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Pref.recommendCardWidth,
    // #24b：LiquidVideoCard 封面同为 16:10 ⇒ ratio 不变；extent = 文本块高度
    // （实测 ≈95 逻辑 px：padding16 + 标题两行 33.8 + 间距 6 + 统计行 ~15 +
    // 间距 4 + 作者行(更多钮 20) + 字体度量余量）⇒ 原取 98；**#25 真机在搜索
    // 结果页抓到尾例 1px 溢出（MiSans 真实字度量尾部摸 99）⇒ 两处同步取 100**
    // （同类同治；余量本就落玻璃外，零观感成本）。卡片根已 Align 顶对齐，
    // 估大的余量落在玻璃外（透明），不会出空缝（P-24b-2 案）。
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(100),
  );

  /// #24b 换卡：LiquidVideoCard＋适配器菜单。
  /// 导航 = [pushRcmdVideoDetail]（与 VideoCardV.onPushDetail 逐字同行为）；
  /// 长按/更多 = 操作弹层（稍后再看/不感兴趣/保存封面/访问作者——上游长按存图
  /// 功能守恒进菜单第四项）；[onRemoved] 沿用本页既有移除语义（含 lastRefreshAt 修正）。
  Widget _liquidCard(
    BuildContext context,
    BaseRcmdVideoItemModel item, {
    required VoidCallback onRemoved,
  }) {
    return LiquidVideoCard(
      data: liquidCardData(item),
      onTap: () => pushRcmdVideoDetail(item),
      onLongPress: () => showLiquidActionSheet(
        context,
        title: '视频操作',
        items: liquidVideoMenuItems(context, item, onRemoved: onRemoved),
      ),
      // onMoreTap 缺省回退 onLongPress（契约 C1），不重复传。
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => _buildSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  if (index == response.length - 1) {
                    controller.onLoadMore();
                  }
                  if (controller.lastRefreshAt != null) {
                    if (controller.lastRefreshAt == index) {
                      return GestureDetector(
                        onTap: () => controller
                          ..animateToTop()
                          ..onRefresh(),
                        child: Card(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const .symmetric(horizontal: 10),
                            child: Text(
                              '上次看到这里\n点击刷新',
                              textAlign: .center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final actualIndex = index > controller.lastRefreshAt!
                        ? index - 1
                        : index;
                    final item =
                        response[actualIndex] as BaseRcmdVideoItemModel;
                    return _liquidCard(
                      context,
                      item,
                      onRemoved: () {
                        if (controller.lastRefreshAt != null &&
                            actualIndex < controller.lastRefreshAt!) {
                          controller.lastRefreshAt =
                              controller.lastRefreshAt! - 1;
                        }
                        controller.loadingState
                          ..value.data!.removeAt(actualIndex)
                          ..refresh();
                      },
                    );
                  } else {
                    return _liquidCard(
                      context,
                      response[index] as BaseRcmdVideoItemModel,
                      onRemoved: () => controller.loadingState
                        ..value.data!.removeAt(index)
                        ..refresh(),
                    );
                  }
                },
                itemCount: controller.lastRefreshAt != null
                    ? response.length + 1
                    : response.length,
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget get _buildSkeleton => SliverGrid(
    gridDelegate: gridDelegate,
    delegate: const SliverSingleChildDelegate(
      count: 10,
      child: VideoCardVSkeleton(),
    ),
  );
}
