import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_solid_card.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class SearchActivityItem extends StatelessWidget {
  const SearchActivityItem({
    super.key,
    required this.item,
  });

  final SearchActivity item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    void onLongPress() => imageSaveDialog(title: item.title, cover: item.cover);
    // C1 综合混排换卡：液态 solid 卡壳（列表卡永不真玻璃）；InkWell 三手势与
    // routePushFromUrl 契约零动；Divider 分隔语义由 margin 承接（动态卡同款）。
    return LiquidSolidCard(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: InkWell(
        onTap: () => PiliScheme.routePushFromUrl(item.url),
        onLongPress: PlatformUtils.isMobile ? onLongPress : null,
        onSecondaryTap: PlatformUtils.isDesktop ? onLongPress : null,
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 5),
          child: Row(
            spacing: 10,
            crossAxisAlignment: .start,
            children: [
              Stack(
                clipBehavior: .none,
                children: [
                  NetworkImgLayer(
                    src: item.cover,
                    width: 160,
                    height: 100,
                  ),
                  if (item.status == 1)
                    const PBadge(text: '直播', top: 6.0, right: 6.0),
                ],
              ),
              Expanded(
                child: Column(
                  spacing: 4,
                  crossAxisAlignment: .start,
                  children: [
                    Text(item.title!),
                    if (item.desc != null)
                      Text(
                        item.desc!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
