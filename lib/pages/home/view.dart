import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_rcmd_adapters.dart';
import 'package:PiliPlus/common/widgets/overlay_inset.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/home/glass_layout.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/glass_scroll_downgrade.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// 顶部玻璃区（搜索栏 + 频道行）的圆角：底栏贴屏幕顶边，只有下方两角可见。
const _kGlassHeaderRadius = BorderRadius.vertical(
  bottom: Radius.circular(18),
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  late ColorScheme _colorScheme;
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();

  @override
  bool get needsCorrection => _homeController.hideTopBar;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final glassEnabled = LiquidGlassRuntime.glassEnabled;
    final showAppBar =
        !_mainController.useSideBar && MediaQuery.sizeOf(context).isPortrait;
    // 折叠路径（hideTopBar）：顶栏自己滑走，而 CommonPageState.correctBy 会把内容顶住
    // —— 顶栏掠过的是内容顶部留白，即**内容不会从搜索栏底下穿过、只会从频道行底下穿过**。
    // 于是该模式下刻意不做漂浮式（保留上游占位式几何，避免凭空多/缺一段空白），
    // 并只给频道行挂玻璃：backdrop 区域恒为频道行大小、折叠期间只是平移、不逐帧缩放。
    final collapseMode = _homeController.hideTopBar;
    final content = onBuild(
      tabBarView(
        controller: _homeController.tabController,
        children: _homeController.tabs.map((e) => e.page).toList(),
      ),
    );

    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAppBar) customAppBar(),
        if (glassEnabled && collapseMode)
          _glass(_buildTabBar(glassEnabled: glassEnabled))
        else
          _buildTabBar(glassEnabled: glassEnabled),
      ],
    );

    if (!glassEnabled || collapseMode) {
      // 纯色档：header 里不含任何玻璃、内容也不注入顶部留白 → 与上游逐像素一致；
      // 折叠模式：几何同上游，只有频道行是玻璃。
      return Column(
        children: [
          header,
          Expanded(child: content),
        ],
      );
    }

    // 漂浮式（玻璃档 + 非折叠）：顶栏覆盖在内容之上，内容顶部留白 = 顶栏展开态高度。
    // 滚动时内容从玻璃底下穿过，backdrop 才真的在采样内容（而不是采样纯色底）。
    final overlayHeight = homeHeaderHeight(
      showAppBar: showAppBar,
      tabCount: _homeController.tabs.length,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: TopOverlayInset(
            // 同一个几何量只算一次：sliver 留白（HomeGlassInset）与共享组件的落点
            // （TopOverlayInset → 下拉刷新转圈）都取它，避免同一高度出现两份定义。
            value: overlayHeight,
            child: HomeGlassInset(value: overlayHeight, child: content),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _glass(header)),
      ],
    );
  }

  /// 频道行（直播/推荐/热门/分区/番剧…）。
  ///
  /// 条高与间距取自 [glass_layout.dart] 的共享常量：这样"内容顶部留白"与顶栏实际高度
  /// 用的是同一份定义，内边距不需要在页面侧写死。
  Widget _buildTabBar({required bool glassEnabled}) {
    if (_homeController.tabs.length <= 1) {
      return const SizedBox(height: kHomeChannelBarEmptyHeight);
    }
    Widget tabBar = Padding(
      padding: const EdgeInsets.only(top: kHomeChannelBarTopGap),
      // #24b：频道行 → LiquidPillBar（线框①），与 TabController 双向同步
      // （滑页→选中 pill 跟随；pill 点→切页＋回顶，语义同原 TabBar.onTap）。
      // 玻璃预算 P-24b-1 案 A：selectionGlass=false——home 已有 header＋底导两块
      // 真玻璃，选中片退 solid 高亮（零嵌套采样成本）。
      child: _LiquidChannelRow(
        controller: _homeController.tabController,
        labels: _homeController.tabs.map((e) => e.label).toList(),
        onSelected: (i) {
          final tc = _homeController.tabController;
          feedBack();
          if (!tc.indexIsChanging) {
            _homeController.animateToTop();
          }
          tc.animateTo(i);
        },
      ),
    );
    if (_homeController.hideTopBar &&
        _mainController.barHideType == .instant) {
      tabBar = Material(
        // 挂玻璃时不能再压一层实色 surface：那会把玻璃底色与背景采样一起盖掉，
        // 观感退化为「实色 tab 条」。纯色档（solid）保持上游原样。
        color: glassEnabled ? Colors.transparent : _colorScheme.surface,
        child: tabBar,
      );
    }
    return tabBar;
  }

  /// 顶部玻璃（glassRegular：素材文档 §8 的"控件/导航功能层"映射）。
  ///
  /// 滚动降档（案 A，docs/立项-rcmd滚动成本优化-20261006）：滚动活动期降 solid
  /// （零背景采样），静止滞回后回 regular；档位切换走 AnimatedSwitcher 交叉淡入
  /// （pill 选中片同款，时长过 motionDuration ⇒ 减弱动效阶跃）；key 随档位变 ⇒
  /// 交叉淡入而非原地换材质（观感跳变 ✗）。折叠/漂浮两路径共用本函数 ⇒ 一处生效。
  Widget _glass(Widget child) => ValueListenableBuilder<bool>(
    valueListenable: GlassScrollDowngrade.instance.scrolling,
    builder: (context, scrolling, _) => AnimatedSwitcher(
      duration: GlassAccessibility.motionDuration(
        const Duration(milliseconds: 200),
      ),
      child: LiquidGlassSurface(
        key: ValueKey<bool>(scrolling),
        material: scrolling
            ? LiquidGlassMaterial.solid
            : LiquidGlassMaterial.regular,
        borderRadius: _kGlassHeaderRadius,
        // 投影是这块玻璃"浮在内容之上"的主要观感来源之一。
        shadow: true,
        child: child,
      ),
    ),
  );

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(),
        const SizedBox(width: 4),
        msgBadge(_mainController),
        const SizedBox(width: 8),
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
      ],
    );
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(
          () {
            final offset = barOffset.value;
            return CustomHeightWidget(
              offset: Offset(0, -offset),
              height: Style.topBarHeight - offset,
              child: Padding(
                padding: padding,
                child: child,
              ),
            );
          },
        );
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(() {
          final showSearchBar = showTopBar.value;
          return AnimatedOpacity(
            opacity: showSearchBar ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              height: showSearchBar ? Style.topBarHeight : 0,
              padding: padding,
              child: child,
            ),
          );
        });
      }
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  Widget searchBar() {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: SizedBox(
        height: 44,
        child: Material(
          borderRadius: borderRadius,
          color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
          child: InkWell(
            borderRadius: borderRadius,
            splashColor: _colorScheme.primaryContainer.withValues(
              alpha: 0.3,
            ),
            onTap: () => Get.toNamed(
              '/search',
              parameters: _homeController.enableSearchWord
                  ? {'hintText': _homeController.defaultSearch.value}
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_outlined,
                  color: _colorScheme.onSecondaryContainer,
                  semanticLabel: '搜索',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Obx(
                    () => Text(
                      _homeController.defaultSearch.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget userAvatar({
  required ColorScheme colorScheme,
  required MainController mainController,
}) {
  return Semantics(
    label: "我的",
    child: Obx(
      () {
        if (mainController.accountService.isLogin.value) {
          return Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                type: .avatar,
                width: 34,
                height: 34,
                src: mainController.accountService.face.value,
              ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: mainController.toMinePage,
                    splashColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    customBorder: const CircleBorder(),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Obx(
                  () => MineController.anonymity.value
                      ? IgnorePointer(
                          child: Container(
                            padding: const .all(2),
                            decoration: BoxDecoration(
                              shape: .circle,
                              color: colorScheme.secondaryContainer,
                            ),
                            child: Icon(
                              size: 14,
                              MdiIcons.incognito,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: '点击登录',
            style: IconButton.styleFrom(
              padding: .zero,
              backgroundColor: colorScheme.onInverseSurface,
            ),
            onPressed: mainController.toMinePage,
            icon: Icon(
              Icons.person_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
          ),
        );
      },
    ),
  );
}

Widget msgBadge(MainController mainController) {
  return Obx(
    () {
      if (mainController.accountService.isLogin.value) {
        final count = mainController.msgUnReadCount.value;
        final isNumBadge = mainController.msgBadgeMode == .number;
        return IconButton(
          tooltip: '消息',
          onPressed: () {
            mainController
              ..clearUnreadMsg()
              ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
            Get.toNamed('/whisper');
          },
          icon: Badge(
            isLabelVisible:
                mainController.msgBadgeMode != .hidden && count != null,
            alignment: isNumBadge
                ? const Alignment(0.0, -0.85)
                : const Alignment(1.0, -0.85),
            label: isNumBadge && count != null ? Text(count) : null,
            child: const Icon(Icons.notifications_none),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );
}

/// #24b：频道行液态版——[TabController] 双向同步包装。
///
/// 滑页 → 选中 pill 跟随（controller listener）；pill 点 → 页面侧回调里
/// `TabController.animateTo`（见 `_buildTabBar` 的 onSelected 接线，语义同原
/// TabBar.onTap：feedBack＋回顶＋切页）。材质档位不由本 widget 决定：
/// 玻璃预算（P-24b-1 案 A）由页面侧 `selectionGlass: false` 给定。
class _LiquidChannelRow extends StatefulWidget {
  const _LiquidChannelRow({
    required this.controller,
    required this.labels,
    required this.onSelected,
  });

  final TabController controller;
  final List<String> labels;
  final ValueChanged<int> onSelected;

  @override
  State<_LiquidChannelRow> createState() => _LiquidChannelRowState();
}

class _LiquidChannelRowState extends State<_LiquidChannelRow> {
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
  void didUpdateWidget(_LiquidChannelRow oldWidget) {
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
    return SizedBox(
      height: kHomeChannelBarHeight,
      width: double.infinity,
      child: LiquidPillBar(
        items: liquidChannelItems(widget.labels),
        selectedIndex: _selected,
        onSelected: widget.onSelected,
        selectionGlass: false,
        height: kHomeChannelBarHeight,
      ),
    );
  }
}
