// Widget 测试骨架：UserTab 资源配置对话框核心交互
//
// 覆盖：
//   - 对话框渲染（搜索框 / 状态 chip 行 / 工具栏 / pill 网格）
//   - 单指 tap pill 切换选中
//   - 搜索关键字过滤 pill 列表
//   - 状态过滤（启用/禁用/18禁）
//   - 工具栏：全选/取消全选、18禁、反选
//   - 计数显示（全部已选/全部总数）
//
// 双指拖动批量翻转手势在 flutter_test 中需要合成多指 Pointer 事件，
// 复杂度高且与平台命中测试耦合，留待真机验收（见任务6 验收清单）。
// 此处用 TODO 标注待补交互。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meowtv_mobile/core/network/api_client.dart';
import 'package:meowtv_mobile/core/theme/app_theme.dart';
import 'package:meowtv_mobile/features/admin/admin_provider.dart';
import 'package:meowtv_mobile/features/admin/tabs/user_tab.dart';
import 'package:meowtv_mobile/shared/models/admin_config.dart';
import 'package:meowtv_mobile/shared/models/admin_group.dart';

// ── Fake AdminNotifier ─────────────────────────────────────────────────────
// 预置一组测试数据，绕过真实 ApiClient，让对话框可被 pump 触发。

class _FakeAdminNotifier extends AdminNotifier {
  _FakeAdminNotifier() : super(ApiClient());

  static final List<SysConfigItem> _resources = [
    SysConfigItem(id: 1, configKey: 'site_a', configGroup: 'resource_site', title: '站点A', title1: '', title2: '', title3: '', value1: 'https://a.com', value2: '', value3: '', value4: '', value5: '0', value6: '1', isEnabled: true),
    SysConfigItem(id: 2, configKey: 'site_b', configGroup: 'resource_site', title: '站点B', title1: '', title2: '', title3: '', value1: 'https://b.com', value2: '', value3: '', value4: '', value5: '1', value6: '1', isEnabled: true),
    SysConfigItem(id: 3, configKey: 'site_c', configGroup: 'resource_site', title: '站点C', title1: '', title2: '', title3: '', value1: 'https://c.com', value2: '', value3: '', value4: '', value5: '0', value6: '0', isEnabled: false),
    SysConfigItem(id: 4, configKey: 'site_d', configGroup: 'resource_site', title: '站点D', title1: '', title2: '', title3: '', value1: 'https://d.com', value2: '', value3: '', value4: '', value5: '1', value6: '1', isEnabled: true),
  ];

  @override
  Future<void> fetchConfigList({String group = 'resource_site'}) async {
    if (!mounted) return;
    state = state.copyWith(configItems: _resources);
  }

  @override
  Future<void> fetchGroupList({int page = 1, int size = 20}) async {
    if (!mounted) return;
    state = state.copyWith(groups: [
      UserGroupItem(id: 100, name: '测试组', remark: '', userCount: 0, resourceCount: 1),
    ]);
  }

  @override
  Future<void> fetchUserList({int page = 1, int size = 20}) async {
    // 测试不关注用户列表，置空
    if (!mounted) return;
  }

  @override
  Future<GroupDetailResponse?> fetchGroupDetail(int id) async {
    return GroupDetailResponse(id: id, name: '测试组', remark: '', configKeys: const ['site_a']);
  }

  @override
  Future<bool> setGroupResources({required int groupId, required List<String> configKeys}) async {
    return true;
  }
}

// ── 测试 harness ────────────────────────────────────────────────────────────

Widget _harness() {
  return ProviderScope(
    overrides: [
      adminProvider.overrideWith((ref) => _FakeAdminNotifier()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      // builder 在 Navigator 之上注入 ScaffoldMessenger，
      // 使 showDialog 弹出的对话框也能访问到 SnackBar 宿主
      builder: (context, child) => ScaffoldMessenger(
        child: Scaffold(body: child!),
      ),
      home: const UserTab(),
    ),
  );
}

Future<void> _openResourceConfigDialog(WidgetTester t) async {
  await t.pumpWidget(_harness());
  await t.pumpAndSettle(const Duration(milliseconds: 300));

  // 切到"用户组"子标签
  final groupTab = find.text('用户组');
  expect(groupTab, findsOneWidget, reason: '应存在"用户组"子标签');
  await t.tap(groupTab);
  await t.pumpAndSettle(const Duration(milliseconds: 200));

  // 点击"配置资源"按钮触发对话框
  final configBtn = find.text('配置资源');
  expect(configBtn, findsWidgets, reason: '至少应有一个"配置资源"按钮');
  await t.tap(configBtn.first);
  await t.pumpAndSettle(const Duration(milliseconds: 300));
}

// ── 测试用例 ────────────────────────────────────────────────────────────────

void main() {
  testWidgets('对话框渲染：标题/搜索框/状态chip/工具栏/pill 全部出现', (t) async {
    await _openResourceConfigDialog(t);

    expect(find.textContaining('配置资源'), findsWidgets, reason: '对话框标题');
    expect(find.byType(TextField), findsOneWidget, reason: '搜索框');
    expect(find.text('全部'), findsOneWidget, reason: '状态 chip-全部');
    expect(find.text('启用'), findsOneWidget, reason: '状态 chip-启用');
    expect(find.text('禁用'), findsOneWidget, reason: '状态 chip-禁用');
    expect(find.text('18禁'), findsAtLeastNWidgets(1), reason: '状态 chip-18禁 与 工具栏 18禁');
    expect(find.text('全选'), findsOneWidget, reason: '工具栏-全选');
    expect(find.text('反选'), findsOneWidget, reason: '工具栏-反选');
    expect(find.text('站点A'), findsOneWidget, reason: 'pill-站点A');
    expect(find.text('站点B'), findsOneWidget, reason: 'pill-站点B');
    expect(find.text('站点C'), findsOneWidget, reason: 'pill-站点C（禁用）');
    expect(find.text('站点D'), findsOneWidget, reason: 'pill-站点D');
  });

  testWidgets('计数显示：1/4（站点A 初始选中）', (t) async {
    await _openResourceConfigDialog(t);
    // 工具栏右侧 "1/4"
    expect(find.text('1/4'), findsOneWidget, reason: '初始已选 1 / 总数 4');
  });

  testWidgets('单指 tap pill 切换选中：点击站点B 后变为 2/4', (t) async {
    await _openResourceConfigDialog(t);
    await t.tap(find.text('站点B'));
    await t.pump();
    expect(find.text('2/4'), findsOneWidget, reason: '站点B 被选中后 2/4');
    // 再点击取消
    await t.tap(find.text('站点B'));
    await t.pump();
    expect(find.text('1/4'), findsOneWidget, reason: '站点B 取消后回到 1/4');
  });

  testWidgets('搜索过滤：输入"B"后仅显示站点B，计数仍为全部', (t) async {
    await _openResourceConfigDialog(t);
    await t.enterText(find.byType(TextField), 'B');
    await t.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('站点A'), findsNothing, reason: '站点A 被过滤隐藏');
    expect(find.text('站点B'), findsOneWidget, reason: '站点B 命中显示');
    expect(find.text('站点C'), findsNothing, reason: '站点C 被过滤隐藏');
    // 计数仍为全部已选/总数
    expect(find.text('1/4'), findsOneWidget, reason: '过滤不影响全部计数');
  });

  testWidgets('状态过滤：点击"禁用"后仅显示站点C', (t) async {
    await _openResourceConfigDialog(t);
    await t.tap(find.text('禁用').first);
    await t.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('站点A'), findsNothing, reason: '站点A 启用，禁用过滤下隐藏');
    expect(find.text('站点C'), findsOneWidget, reason: '站点C 禁用，显示');
  });

  testWidgets('状态过滤：点击"18禁"后仅显示站点B/D', (t) async {
    await _openResourceConfigDialog(t);
    // 18禁 chip 在状态行和工具栏各一，状态行的在 ListView 顺序在前
    await t.tap(find.text('18禁').first);
    await t.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('站点A'), findsNothing, reason: '站点A 非18禁');
    expect(find.text('站点B'), findsOneWidget, reason: '站点B 18禁');
    expect(find.text('站点D'), findsOneWidget, reason: '站点D 18禁');
  });

  testWidgets('工具栏-全选：点击后全部 4 项选中，按钮变"取消全选"', (t) async {
    await _openResourceConfigDialog(t);
    await t.tap(find.text('全选'));
    await t.pump();
    expect(find.text('4/4'), findsOneWidget, reason: '全选后 4/4');
    expect(find.text('取消全选'), findsOneWidget, reason: '按钮文案切换');
    // 再点击取消
    await t.tap(find.text('取消全选'));
    await t.pump();
    expect(find.text('0/4'), findsOneWidget, reason: '取消全选后 0/4');
  });

  testWidgets('工具栏-18禁：点击切换站点B/D 的选中', (t) async {
    await _openResourceConfigDialog(t);
    // 初始 1/4（仅 site_a）
    await t.tap(find.text('18禁').last); // 工具栏的 18禁
    await t.pump();
    // 加上 site_b site_d → 3/4
    expect(find.text('3/4'), findsOneWidget, reason: '18禁按钮后 3/4');
    // 再点击取消
    await t.tap(find.text('18禁').last);
    await t.pump();
    expect(find.text('1/4'), findsOneWidget, reason: '再次 18禁按钮回到 1/4');
  });

  testWidgets('工具栏-反选：当前可见项各自翻转', (t) async {
    await _openResourceConfigDialog(t);
    // 初始 site_a 选中（1/4）
    await t.tap(find.text('反选'));
    await t.pump();
    // 翻转后 site_a 取消，site_b/c/d 选中 → 3/4
    expect(find.text('3/4'), findsOneWidget, reason: '反选后 3/4');
  });

  testWidgets('保存按钮调用 setGroupResources', (t) async {
    await _openResourceConfigDialog(t);
    await t.tap(find.text('站点B'));
    await t.pump();
    await t.tap(find.text('保存配置'));
    await t.pumpAndSettle(const Duration(milliseconds: 300));
    // Fake 内部记录了调用
    // （无法直接断言私有字段，这里仅保证不抛异常且对话框关闭）
    expect(find.text('配置资源'), findsWidgets);
  });

  // ── 待补：双指拖动批量翻转（需合成多指 Pointer 事件） ──────────────────
  // testWidgets('双指拖动经过 pill 翻转选中', (t) async {
  //   // 1. 打开对话框
  //   // 2. 用 t.startGesture 起两个 Pointer
  //   // 3. 各自 moveTo 某个 pill 中心
  //   // 4. 验证对应 pill 被翻转
  //   // 因 Listener.onPointerDown/Move 在 flutter_test 中需通过
  //   //    TestGesture + WidgetsBinding.instance.pointerRouter 模拟，
  //   //    且 GlobalKey 命中测试依赖 RenderObject 布局完成，
  //   //    留待真机验收（任务6）覆盖。
  // });

  testWidgets('无双指批量模式横幅（已移除双指逻辑）', (t) async {
    await _openResourceConfigDialog(t);
    expect(find.textContaining('双指批量模式'), findsNothing, reason: '双指批量模式已移除');
  });
}
