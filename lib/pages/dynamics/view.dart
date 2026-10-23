import 'package:PiliPlus/common/widgets/liquid/liquid_floating_button.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_tab_pill_bar.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_create/view.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();

  @override
  bool get wantKeepAlive => true;

  // #27：发布入口 → 液态悬浮钮（线框⑤）。**位置语义不变**（仍占 appBar 的
  // actions/leading 原槽位）、**回调不变**（`CreateDynPanel.onCreateDyn`）、
  // tooltip 文案保留；材质 = solid 档圆片（本屏真玻璃预算＝主底导 1 处已占）。
  Widget _createDynamicBtn(ColorScheme colorScheme, {bool isRight = true}) =>
      Padding(
        padding: isRight
            ? const EdgeInsets.only(right: 12)
            : const EdgeInsets.only(left: 12),
        child: LiquidFloatingButton(
          icon: Icons.add,
          tooltip: '发布动态',
          onPressed: () => CreateDynPanel.onCreateDyn(context),
        ),
      );

  Widget upPanelPart(ColorScheme colorScheme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(
            () => _buildUpPanel(_dynamicsController.loadingState.value),
          ),
        ),
      ),
    );
  }

  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
        upData: response,
        dynamicsController: _dynamicsController,
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _dynamicsController.onReload,
        ),
      ),
    };
  }

  bool get checkPage =>
      _mainController.navigationBars[0] != .dynamics &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    Widget child = tabBarView(
      controller: _dynamicsController.tabController,
      children: DynamicsTabType.values
          .map((e) => DynamicsTabPage(dynamicsType: e))
          .toList(),
    );

    switch (upPanelPosition) {
      case .top:
        child = Column(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftFixed:
        child = Row(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .rightFixed:
        child = Row(
          children: [
            Expanded(child: child),
            upPanelPart(colorScheme),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftDrawer:
        drawer = upPanelPart(colorScheme);
        actions = _createDynamicBtn(colorScheme);
        leading = const DrawerButton();
      case .rightDrawer:
        endDrawer = upPanelPart(colorScheme);
        leading = _createDynamicBtn(colorScheme, isRight: false);
        actions = const EndDrawerButton();
    }

    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const .fromHeight(50),
        child: Row(
          children: [
            ?leading,
            Expanded(
              // #27：tab 行 → LiquidPillBar（线框⑤顶部胶囊），与 TabController
              // **双向同步**（滑页→选中 pill 跟随 via listener；pill 点→animateTo；
              // listener 生命周期 initState/didUpdateWidget/dispose 三处齐——
              // 照抄 #24b 首页 `_LiquidChannelRow` 成功模式，公共化为
              // LiquidTabPillBar）。onTap 语义同原 TabBar.onTap（回顶）。
              // 玻璃预算案 A：selectionGlass=false——本屏真玻璃＝主底导 1 处已占，
              // 选中片退 solid 高亮（与首页同口径）。
              child: LiquidTabPillBar(
                controller: _dynamicsController.tabController,
                labels: DynamicsTabType.values.map((e) => e.label).toList(),
                selectionGlass: false,
                onSelected: (index) {
                  if (!_dynamicsController.tabController.indexIsChanging) {
                    _dynamicsController.animateToTop();
                  }
                },
              ),
            ),
            actions,
          ],
        ),
      ),
      drawer: drawer,
      endDrawer: endDrawer,
      body: onBuild(child),
    );
  }
}
