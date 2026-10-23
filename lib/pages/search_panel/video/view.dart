import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_search_adapters.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/search_panel/video/controller.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SearchVideoPanel extends CommonSearchPanel {
  const SearchVideoPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchVideoPanel> createState() => _SearchVideoPanelState();
}

class _SearchVideoPanelState
    extends
        CommonSearchPanelState<
          SearchVideoPanel,
          SearchVideoData,
          SearchVideoItemModel
        >
    with GridMixin, SearchVideoPanelMixin<SearchVideoPanel> {
  @override
  late final SearchVideoController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchVideoController(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );
  }
}

mixin SearchVideoPanelMixin<S extends SearchVideoPanel>
    on
        CommonSearchPanelState<S, SearchVideoData, SearchVideoItemModel>,
        GridMixin {
  @override
  SearchVideoController get controller;

  @override
  Widget buildHeader() {
    return SliverFloatingHeaderWidget(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  children: [
                    for (final e in ArchiveFilterType.values)
                      Obx(
                        () => SearchText(
                          fontSize: 13,
                          text: e.desc,
                          bgColor: Colors.transparent,
                          textColor: controller.selectedType.value == e
                              ? colorScheme.primary
                              : colorScheme.outline,
                          onTap: (_) => controller
                            ..order = e == .totalrank ? '' : e.name
                            ..selectedType.value = e
                            ..onSortSearch(getBack: false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(indent: 7, endIndent: 8),
            const SizedBox(width: 3),
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                tooltip: '筛选',
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(EdgeInsets.zero),
                ),
                onPressed: () => controller.onShowFilterDialog(context),
                icon: Icon(
                  Icons.filter_list_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// #25 换卡：横版 VideoCardH（固定 110 高）→ 竖版 LiquidVideoCard ⇒
  /// delegate 换 rcmd 同式（16:10 封面 + 文本块；卡片根本身 Align 顶对齐，
  /// 估大的余量落玻璃外透明区，见 rcmd/view.dart 的 P-24b-2 注释）；卡片宽度
  /// 档位沿用用户可调的 recommendCardWidth（与首页推荐流同一密度设置）。
  /// 不改名覆盖 GridMixin.gridDelegate（类型族不同，覆盖会触发字段覆盖 lint）——
  /// 本面板走此字段，mixin 原 delegate 仅骨架遗留、本面板已不消费。
  /// extent 100（非 rcmd 的 98）：#25 真机验证抓到"首行两卡 BOTTOM OVERFLOWED
  /// BY 1.00 PIXELS"（debug 构建条纹，error 通道收编）——MiSans 真实字度量的
  /// 尾部分布能摸到 99（98+3 余量被尾例吃穿）；余量落到玻璃外零观感成本，
  /// 故取 100 压住整个尾部（若超 2px 的结构问题仍会露头，不掩盖）。
  late final liquidGridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Pref.recommendCardWidth,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(100),
  );

  @override
  Widget get buildLoading => SliverGrid(
    gridDelegate: liquidGridDelegate,
    delegate: const SliverSingleChildDelegate(
      count: 10,
      child: VideoCardVSkeleton(),
    ),
  );

  @override
  Widget buildList(List<SearchVideoItemModel> list) {
    return SliverGrid.builder(
      gridDelegate: liquidGridDelegate,
      itemBuilder: (context, index) {
        if (index == list.length - 1) {
          controller.onLoadMore();
        }
        final item = list[index];
        // #25 换卡：LiquidVideoCard＋适配器菜单（契约同 #24b rcmd）。
        // 导航 = pushSearchVideoDetail（薄壳委派 pushVideoH，单一真相）；
        // 长按/更多 = 操作弹层四项（稍后再看/不感兴趣/保存封面/访问作者——
        // 上游卡的长按存图功能守恒进菜单）；onRemoved 沿用既有移除语义。
        return LiquidVideoCard(
          data: liquidSearchCardData(item),
          onTap: () => pushSearchVideoDetail(item),
          onLongPress: () => showLiquidActionSheet(
            context,
            title: '视频操作',
            items: liquidSearchMenuItems(
              context,
              item,
              onRemoved: () => controller.loadingState
                ..value.data!.removeAt(index)
                ..refresh(),
            ),
          ),
        );
      },
      itemCount: list.length,
    );
  }
}
