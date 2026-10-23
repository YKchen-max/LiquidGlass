import 'package:PiliPlus/common/widgets/flutter/vertical_tabs.dart';
import 'package:PiliPlus/models/common/rank_type.dart';
import 'package:PiliPlus/pages/rank/controller.dart';
import 'package:PiliPlus/pages/rank/zone/view.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage>
    with AutomaticKeepAliveClientMixin {
  final RankController _rankController = Get.put(RankController());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        _buildTab(theme),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _rankController.tabController,
            children: RankType.values
                .map(
                  (item) => ZonePage(
                    rid: item.rid,
                    seasonType: item.seasonType,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(ThemeData theme) {
    final tabBar = VerticalTabBar(
      dividerWidth: 0,
      isScrollable: true,
      indicatorWeight: 3,
      indicatorSize: .tab,
      controller: _rankController.tabController,
      padding: .only(bottom: MediaQuery.paddingOf(context).bottom + 105),
      tabs: RankType.values.map((e) => VerticalTab(text: e.label)).toList(),
      onTap: (index) {
        if (!_rankController.tabController.indexIsChanging) {
          _rankController.animateToTop();
        } else {
          _rankController
            ..tabIndex.value = index
            ..tabController.animateTo(index);
        }
      },
    );
    // 分区页左侧竖向 tab 条 = **导航/功能层**（能上/不上清单：功能层可上、列表项/卡片永久禁止）。
    // 纯色档直接返回上游控件（不套壳 ⇒ 控件树逐节点相同 ⇒ 逐像素一致）。
    if (!LiquidGlassRuntime.glassEnabled) return tabBar;
    return LiquidGlassSurface(
      material: LiquidGlassMaterial.regular,
      // 贴内容区左缘：只有右缘可见（与侧栏同一形态）。
      borderRadius: BorderRadius.zero,
      // 与内容并排、不是悬浮层 ⇒ 投影只会压暗相邻内容，不加。
      shadow: false,
      child: tabBar,
    );
  }
}
