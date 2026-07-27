import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'tabs/subscribe_tab.dart';
import 'tabs/resource_group_tab.dart';
import 'tabs/user_tab.dart';
import 'tabs/download_config_tab.dart';
import 'tabs/douban_config_tab.dart';
import 'tabs/stream_config_tab.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    Tab(icon: Icon(Icons.cloud_download_outlined), text: '订阅'),
    Tab(icon: Icon(Icons.folder_outlined), text: '资源组'),
    Tab(icon: Icon(Icons.people_outlined), text: '用户'),
    Tab(icon: Icon(Icons.download_outlined), text: '下载'),
    Tab(icon: Icon(Icons.movie_outlined), text: '豆瓣'),
    Tab(icon: Icon(Icons.stream_outlined), text: '流代理'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('后台管理',
            style: TextStyle(color: colors.textPrimary, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          labelColor: colors.primary,
          unselectedLabelColor: colors.textSecondary,
          indicatorColor: colors.primary,
          indicatorSize: TabBarIndicatorSize.label,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SubscribeTab(),
          ResourceGroupTab(),
          UserTab(),
          DownloadConfigTab(),
          DoubanConfigTab(),
          StreamConfigTab(),
        ],
      ),
    );
  }
}
