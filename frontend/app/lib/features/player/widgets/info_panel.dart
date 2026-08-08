import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/widgets/cache_icons.dart';

import '../../../core/theme/app_theme.dart' show AppColors, BuildContextThemeX;
import '../../../shared/models/enums.dart';
import '../../../shared/models/resource_detail.dart';
import '../../../shared/widgets/favorite_star_button.dart';
import '../../settings/douban_image_proxy_provider.dart';

/// Max height for the expanded info section (scrollable when exceeded).
const _infoExpandedMaxHeight = 200.0;

class InfoPanel extends StatefulWidget {
  final ResourceDetailResponse detail;
  final DoubanImageProxyState proxyState;
  final String baseUrl;
  final VoidCallback? onDownload;
  final VoidCallback? onCache;
  const InfoPanel({super.key, required this.detail, required this.proxyState, required this.baseUrl, this.onDownload, this.onCache});
  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  bool _infoExpanded = false;
  bool _descExpanded = false;
  bool _imgError = false;

  // 封面 URL / headers 缓存，避免随父组件高频重建反复调用 resolveImageUrl（该方法含日志与字符串拼接）。
  String _coverUrl = '';
  Map<String, String>? _coverHeaders;
  // 上次解析封面所用的输入指纹，用于 didUpdateWidget 判断是否需要重新解析。
  // DoubanImageProxyState 未重写 ==/hashCode，故手动比较其关键字段。
  String? _lastVodPic;
  String? _lastBaseUrl;
  DoubanImageProxyMode? _lastProxyMode;
  String? _lastTempToken;
  DateTime? _lastTokenExpiresAt;

  /// 解析封面 URL 与 HTTP headers 并缓存到字段。
  /// 仅在 vodPic / baseUrl / proxyState 关键字段变化时重新调用。
  void _resolveCover() {
    final vodPic = widget.detail.vodPic ?? '';
    _coverUrl = widget.proxyState.resolveImageUrl(vodPic, widget.baseUrl) ?? '';
    _coverHeaders = widget.proxyState.httpHeadersForUrl(vodPic);
    _lastVodPic = vodPic;
    _lastBaseUrl = widget.baseUrl;
    _lastProxyMode = widget.proxyState.mode;
    _lastTempToken = widget.proxyState.tempToken;
    _lastTokenExpiresAt = widget.proxyState.tokenExpiresAt;
  }

  /// 封面相关输入是否发生变化（需重新解析）。
  bool _coverInputsChanged() {
    final vodPic = widget.detail.vodPic ?? '';
    return vodPic != _lastVodPic ||
        widget.baseUrl != _lastBaseUrl ||
        widget.proxyState.mode != _lastProxyMode ||
        widget.proxyState.tempToken != _lastTempToken ||
        widget.proxyState.tokenExpiresAt != _lastTokenExpiresAt;
  }

  @override
  void initState() {
    super.initState();
    _resolveCover();
  }

  @override
  void didUpdateWidget(covariant InfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_coverInputsChanged()) {
      _resolveCover();
      // 封面 URL 变化时重置图片加载错误状态，避免新 URL 仍显示占位图
      _imgError = false;
    }
  }

  String _stripHtml(String html) => html.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  Widget _coverPlaceholder(AppColors colors) => Container(
    color: colors.elevated,
    child: Center(child: Icon(Icons.play_circle_outline, color: colors.textMuted, size: 28)),
  );

  Widget _metaChip(IconData icon, String text, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: color),
    const SizedBox(width: 2),
    Text(text, style: TextStyle(color: color, fontSize: 11)),
  ]);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = widget.detail;
    final blurb = d.vodBlurb ?? (d.vodContent != null ? _stripHtml(d.vodContent!) : '');
    final isLongDesc = blurb.length > 120;
    final displayDesc = _descExpanded ? blurb : (isLongDesc ? '${blurb.substring(0, 120)}…' : blurb);
    // 使用 initState/didUpdateWidget 中缓存的封面 URL/headers，避免每次 build 重复解析与打日志
    final coverUrl = _coverUrl;
    final coverHeaders = _coverHeaders;
    final doubanScore = d.vodDoubanScore;
    final vodScore = d.vodScore;
    final hasScore = (doubanScore != null && doubanScore.isNotEmpty) || (vodScore != null && vodScore.isNotEmpty);

    return Container(
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.border)),
      child: Column(children: [
        // 头部：封面 + 基本信息
        Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 封面
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 72, height: 108, child: coverUrl.isNotEmpty && !_imgError
            ? CachedNetworkImage(imageUrl: coverUrl, httpHeaders: coverHeaders, fit: BoxFit.cover, errorWidget: (context, url, error) { if (!_imgError) setState(() => _imgError = true); return _coverPlaceholder(colors); })
            : _coverPlaceholder(colors))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 标题 + 下载 + 收藏
            Row(children: [
              Expanded(child: Text(d.vodName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800))),
              if (widget.onDownload != null)
                GestureDetector(
                  onTap: widget.onDownload,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border),
                    ),
                    child: Center(
                      child: Icon(Icons.download_outlined, size: 18, color: colors.textSecondary),
                    ),
                  ),
                ),
              if (widget.onCache != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onCache,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border),
                    ),
                    // 缓存入口图标缩小至 80%（16），居中显示
                    child: Center(
                      child: CacheIcons.cache(size: 16, color: colors.textSecondary),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              FavoriteStarButton(vodId: d.vodId, vodName: d.vodName, vodPic: d.vodPic, resourceDomain: d.resourceDomain, resourceName: d.resourceName, groupKey: '', mode: FavoriteStarMode.iconOnly),
            ]),
            if (d.vodSub != null && d.vodSub!.isNotEmpty) ...[ const SizedBox(height: 2), Text(d.vodSub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textSecondary, fontSize: 12)) ],
            const SizedBox(height: 6),
            // 元信息
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (d.vodYear != null && d.vodYear!.isNotEmpty) _metaChip(Icons.calendar_today, d.vodYear!, colors.textMuted),
              if (d.typeName != null && d.typeName!.isNotEmpty) _metaChip(Icons.movie, d.typeName!, colors.primary),
              if (d.vodArea != null && d.vodArea!.isNotEmpty) _metaChip(Icons.place, d.vodArea!, colors.textMuted),
              if (d.vodLang != null && d.vodLang!.isNotEmpty) _metaChip(Icons.language, d.vodLang!, colors.textMuted),
              _metaChip(Icons.public, d.resourceName, colors.primary),
            ]),
            // 评分
            if (hasScore) ...[ const SizedBox(height: 6), Row(children: [
              Icon(Icons.star, size: 14, color: colors.warning),
              const SizedBox(width: 4),
              if (doubanScore != null && doubanScore.isNotEmpty) ...[
                Text('豆瓣 ', style: TextStyle(color: colors.textMuted, fontSize: 10)),
                Text(double.tryParse(doubanScore)?.toStringAsFixed(1) ?? doubanScore, style: TextStyle(color: colors.warning, fontSize: 12, fontWeight: FontWeight.w700)),
                if (vodScore != null && vodScore != doubanScore) ...[
                  const SizedBox(width: 12), Icon(Icons.star, size: 14, color: colors.primary), const SizedBox(width: 4),
                  Text('资源站 ', style: TextStyle(color: colors.textMuted, fontSize: 10)),
                  Text(double.tryParse(vodScore)?.toStringAsFixed(1) ?? vodScore, style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ] else if (vodScore != null && vodScore.isNotEmpty)
                Text(double.tryParse(vodScore)?.toStringAsFixed(1) ?? vodScore, style: TextStyle(color: colors.warning, fontSize: 12, fontWeight: FontWeight.w700)),
            ])],
            // 类型标签
            if (d.vodClass != null && d.vodClass!.isNotEmpty) ...[ const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 4, children: d.vodClass!.split(',').map((g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: colors.elevated, borderRadius: BorderRadius.circular(4)),
              child: Text(g.trim(), style: TextStyle(color: colors.textMuted, fontSize: 10)),
            )).toList())],
            // 备注
            if (d.vodRemarks != null && d.vodRemarks!.isNotEmpty) ...[ const SizedBox(height: 4), Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(d.vodRemarks!, style: TextStyle(color: colors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
            )],
          ])),
        ])),
        // 折叠触发器
        GestureDetector(onTap: () => setState(() => _infoExpanded = !_infoExpanded), child: Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.divider))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_infoExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 14, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(_infoExpanded ? '收起详情' : '展开详情', style: TextStyle(color: colors.textMuted, fontSize: 10)),
          ]),
        )),
        // 可折叠内容 — constrained max height with internal scrolling
        if (_infoExpanded) ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _infoExpandedMaxHeight),
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (d.vodDirector != null && d.vodDirector!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text.rich(TextSpan(children: [
                  TextSpan(text: '导演: ', style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                  TextSpan(text: d.vodDirector, style: TextStyle(color: colors.textMuted, fontSize: 11)),
                ]))),
                if (d.vodActor != null && d.vodActor!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text.rich(TextSpan(children: [
                  TextSpan(text: '演员: ', style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                  TextSpan(text: d.vodActor, style: TextStyle(color: colors.textMuted, fontSize: 11)),
                ]))),
                if (blurb.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayDesc, style: TextStyle(color: colors.textMuted, fontSize: 11, height: 1.5)),
                  if (isLongDesc) GestureDetector(onTap: () => setState(() => _descExpanded = !_descExpanded), child: Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_descExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 12, color: colors.primary),
                    const SizedBox(width: 2),
                    Text(_descExpanded ? '收起简介' : '展开简介', style: TextStyle(color: colors.primary, fontSize: 10)),
                  ]))),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}