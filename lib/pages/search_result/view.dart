import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_rcmd_adapters.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/debug/glass_frame_timing.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/pages/search/controller.dart';
import 'package:PiliPlus/pages/search_panel/all/view.dart';
import 'package:PiliPlus/pages/search_panel/article/view.dart';
import 'package:PiliPlus/pages/search_panel/live/view.dart';
import 'package:PiliPlus/pages/search_panel/pgc/view.dart';
import 'package:PiliPlus/pages/search_panel/user/view.dart';
import 'package:PiliPlus/pages/search_panel/video/view.dart';
import 'package:PiliPlus/pages/search_result/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage>
    with SingleTickerProviderStateMixin {
  late SearchResultController _searchResultController;
  late TabController _tabController;
  final String _tag = DateTime.now().millisecondsSinceEpoch.toString();
  final bool _isFromSearch = Get.arguments?['fromSearch'] ?? false;
  SSearchController? sSearchController;

  @override
  void initState() {
    super.initState();
    _searchResultController = Get.put(
      SearchResultController(),
      tag: _tag,
    );

    _tabController = TabController(
      vsync: this,
      initialIndex: Get.arguments?['initIndex'] ?? 0,
      length: SearchType.values.length,
    );

    if (_isFromSearch) {
      try {
        sSearchController = Get.find<SSearchController>(
          tag: Get.parameters['tag'],
        );
        _tabController.addListener(listener);
      } catch (_) {}
    }
  }

  void listener() {
    sSearchController?.initIndex = _tabController.index;
  }

  // A1（#25 帧延迟对照验收）FT 接缝：与 rcmd/view.dart 同构——仅在
  // GLASS_FRAME_TIMING 计时包里有行为（编译期常量 ⇒ 常规构建零行为）。
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
      label: 'search-result-scroll',
      note: 'A1 成对窗（#25 验收）：列表滚动帧延迟；arm=search-result-scroll',
      scenarioProbe: () =>
          DateTime.now().microsecondsSinceEpoch - _ftLastScrollUs < 800000,
    );
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(listener)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        shape: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        title: GestureDetector(
          onTap: () {
            if (_isFromSearch) {
              Get.back(result: true);
            } else {
              Get.offNamed(
                '/search',
                parameters: {'text': _searchResultController.keyword},
              );
            }
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: double.infinity,
            child: Text(
              _searchResultController.keyword,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
            ),
          ),
        ),
      ),
      body: ViewSafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _ftOnScroll();
            return false;
          },
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // #25：原生 TabBar → LiquidPillBar（与首页频道行同族收口，
            // _LiquidChannelRow 同构）。保留：① 计数角标（label 内插，
            // 单 Obx 读整列）；② 点当前 tab 回顶（toTopIndex 语义逐字照抄
            // 原 onTap，含 indexIsChanging 守卫）；③ TabBarView/控制器不动。
            // selectionGlass:false 与首页案 A 同族（跨页选中片观感一致；
            // 本页玻璃预算本有富余，想翻真玻璃只改这一个参数）。
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Obx(
                () {
                  final counts = _searchResultController.count;
                  return _LiquidSearchTypeRow(
                    controller: _tabController,
                    labels: <String>[
                      for (final item in SearchType.values)
                        () {
                          final count = counts[item.index];
                          return '${item.label}${count != -1 ? ' ${count > 99 ? '99+' : count}' : ''}';
                        }(),
                    ],
                    onSelected: (i) {
                      if (!_tabController.indexIsChanging) {
                        if (_searchResultController.toTopIndex.value == i) {
                          _searchResultController.toTopIndex.refresh();
                        } else {
                          _searchResultController.toTopIndex.value = i;
                        }
                      }
                      _tabController.animateTo(i);
                    },
                  );
                },
              ),
            ),
            Expanded(
              child: tabBarView(
                controller: _tabController,
                children: SearchType.values
                    .map(
                      (item) => switch (item) {
                        .all => SearchAllPanel(
                          tag: _tag,
                          searchType: item,
                          keyword: _searchResultController.keyword,
                        ),
                        .video => SearchVideoPanel(
                          tag: _tag,
                          searchType: item,
                          keyword: _searchResultController.keyword,
                        ),
                        .media_bangumi || .media_ft => SearchPgcPanel(
                          tag: _tag,
                          searchType: item,
                          keyword: _searchResultController.keyword,
                        ),
                        .live_room => SearchLivePanel(
                          tag: _tag,
                          searchType: item,
                          keyword: _searchResultController.keyword,
                        ),
                        .bili_user => SearchUserPanel(
                          tag: _tag,
                          searchType: item,
                          keyword: _searchResultController.keyword,
                        ),
                        .article => SearchArticlePanel(
                          tag: _tag,
                          searchType: item,
                          keyword: _searchResultController.keyword,
                        ),
                      },
                    )
                    .toList(),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// #25：搜索结果页分类胶囊行——与首页 `_LiquidChannelRow`（home/view.dart）
/// 同构：TabController 双向同步（滑动→选中跟随 via listener；点 pill→
/// animateTo 由 onSelected 回调侧做）。listener 生命周期 initState/
/// didUpdateWidget/dispose 三处齐（S15 绊线教训：删监听 = 整条失能）。
class _LiquidSearchTypeRow extends StatefulWidget {
  const _LiquidSearchTypeRow({
    required this.controller,
    required this.labels,
    required this.onSelected,
  });

  final TabController controller;
  final List<String> labels;
  final ValueChanged<int> onSelected;

  @override
  State<_LiquidSearchTypeRow> createState() => _LiquidSearchTypeRowState();
}

class _LiquidSearchTypeRowState extends State<_LiquidSearchTypeRow> {
  late int _selected = widget.controller.index;

  void _sync() {
    final index = widget.controller.index;
    if (_selected != index) {
      setState(() => _selected = index);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void didUpdateWidget(_LiquidSearchTypeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _selected = widget.controller.index;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidPillBar(
      items: liquidChannelItems(widget.labels),
      selectedIndex: _selected,
      onSelected: widget.onSelected,
      selectionGlass: false,
    );
  }
}
