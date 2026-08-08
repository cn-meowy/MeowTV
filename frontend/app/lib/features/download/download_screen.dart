import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/download.dart';
import '../../shared/models/enums.dart';
import '../download/download_provider.dart';
import '../settings/douban_image_proxy_provider.dart';

class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  @override
  void initState() {
    super.initState();
    // 首次加载数据；startPolling 由 ref.onResume 自动管理，无需手动调用。
    Future.microtask(() {
      ref.read(doubanImageProxyProvider.notifier).init();
      ref.read(downloadProvider.notifier).loadDownloads();
    });
  }

  @override
  void dispose() {
    // stopPolling 由 ref.onCancel 自动管理，无需手动调用。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(downloadProvider);
    final colors = context.colors;

    // Filter tabs
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的下载'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }),
      ),
      body: Column(
        children: [
          // Status filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.md, vertical: AppTheme.sm),
            child: Row(
              children: [
                _FilterChip(label: '全部', isActive: state.filterStatus == null, onTap: () => ref.read(downloadProvider.notifier).loadDownloads()),
                const SizedBox(width: 8),
                _FilterChip(label: '下载中', isActive: state.filterStatus == DownloadStatus.downloading, onTap: () => ref.read(downloadProvider.notifier).loadDownloads(status: DownloadStatus.downloading)),
                const SizedBox(width: 8),
                _FilterChip(label: '已完成', isActive: state.filterStatus == DownloadStatus.completed, onTap: () => ref.read(downloadProvider.notifier).loadDownloads(status: DownloadStatus.completed)),
                const SizedBox(width: 8),
                _FilterChip(label: '失败', isActive: state.filterStatus == DownloadStatus.failed, onTap: () => ref.read(downloadProvider.notifier).loadDownloads(status: DownloadStatus.failed)),
              ],
            ),
          ),
          Expanded(
            child: state.isLoading && state.items.isEmpty
                ? Center(child: CircularProgressIndicator(color: colors.primary))
                : state.items.isEmpty
                    ? Center(child: Text('暂无下载任务', style: TextStyle(color: colors.textMuted)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppTheme.md),
                        itemCount: state.items.length,
                        separatorBuilder: (_, index) => const SizedBox(height: AppTheme.sm),
                        itemBuilder: (context, i) => _DownloadTaskCard(
                          key: ValueKey(state.items[i].id),
                          task: state.items[i],
                          onCancel: () => ref.read(downloadProvider.notifier).cancelTask(state.items[i].id),
                          onDelete: () => ref.read(downloadProvider.notifier).deleteTask(state.items[i].id),
                          onRetry: () => ref.read(downloadProvider.notifier).retryTask(state.items[i].id),
                          onPlay: state.items[i].status == DownloadStatus.completed
                              ? () {
                                  final task = state.items[i];
                                  context.push('/play', extra: {
                                    'resource_domain': task.resourceDomain,
                                    'vod_id': task.vodId,
                                    'source_index': task.sourceIndex,
                                    'ep_index': task.epIndex,
                                  });
                                }
                              : null,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.primary : colors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusTag),
        ),
        child: Text(label, style: TextStyle(color: isActive ? colors.textInverse : colors.textSecondary, fontSize: 13)),
      ),
    );
  }
}

class _DownloadTaskCard extends ConsumerWidget {
  final DownloadTaskItem task;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  final VoidCallback? onPlay;
  const _DownloadTaskCard({super.key, required this.task, required this.onCancel, required this.onDelete, required this.onRetry, this.onPlay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final proxyState = ref.watch(doubanImageProxyProvider);
    ref.read(doubanImageProxyProvider.notifier).checkAndRefresh();
    final baseUrl = ref.read(apiClientProvider).baseUrl;
    final imageUrl = proxyState.resolveImageUrl(task.vodPic, baseUrl) ?? '';
    final headers = proxyState.httpHeadersForUrl(task.vodPic);
    final statusLabel = _statusLabel(task.status);
    final statusColor = _statusColor(task.status, colors);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              httpHeaders: headers,
              width: 60,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: colors.elevated),
              errorWidget: (_, _, _) => Container(color: colors.elevated, child: Icon(Icons.movie, color: colors.textMuted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.vodName, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(task.epName, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12)),
                    if (task.status == DownloadStatus.downloading) ...[
                      const SizedBox(width: 8),
                      Expanded(child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          backgroundColor: colors.elevated,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                        ),
                      )),
                      const SizedBox(width: 4),
                      Text('${(task.progress * 100).round()}%', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
                      _SmallButton(label: '取消', color: colors.textMuted, onTap: onCancel),
                    if (task.status == DownloadStatus.failed)
                      _SmallButton(label: '重试', color: colors.primary, onTap: onRetry),
                    if (task.status == DownloadStatus.completed) ...[
                      if (onPlay != null) _SmallButton(label: '播放', color: colors.primary, onTap: onPlay!),
                      _SmallButton(label: '删除', color: colors.error, onTap: onDelete),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.queued: return '排队中';
      case DownloadStatus.parsing: return '解析中';
      case DownloadStatus.downloading: return '下载中';
      case DownloadStatus.merging: return '合并中';
      case DownloadStatus.completed: return '已完成';
      case DownloadStatus.failed: return '失败: ${task.errorMsg}';
      case DownloadStatus.cancelled: return '已取消';
    }
  }

  Color _statusColor(DownloadStatus s, AppColors colors) {
    switch (s) {
      case DownloadStatus.completed: return colors.success;
      case DownloadStatus.failed: return colors.error;
      case DownloadStatus.downloading: return colors.primary;
      default: return colors.textMuted;
    }
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
