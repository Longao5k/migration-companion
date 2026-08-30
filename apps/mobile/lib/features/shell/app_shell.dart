import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documents/document_engines.dart';
import '../../core/state/app_store.dart';
import '../change_log/change_log_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../projects/projects_screen.dart';
import '../tools/tools_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;

  /// 回到前台时重新拉一次提醒。
  ///
  /// 原先只在 initState 拉一次：手机上 App 很少被真正杀掉，用户切出去看邮件
  /// 再切回来，看到的还是几小时前那一批。一个「政策更新提醒」产品，
  /// 更新要等冷启动才出现，等于没有提醒。
  ///
  /// 只重拉提醒和内容，不碰云同步和过期副本清理——那两件事有各自的时机，
  /// 每次切前台都跑一遍是白费流量。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final store = ref.read(appStoreProvider.notifier);
    Future<void>.microtask(() async {
      await store.refreshContent();
      await store.refreshPolicyAlerts();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(() async {
      final store = ref.read(appStoreProvider.notifier);
      await store.ready;
      await store.refreshTaxonomy();
      await store.refreshContent();
      await store.resumeCloudSync();
      await store.refreshPolicyAlerts();
      // 交给外部阅读器的副本是完整的申请材料。启动时清一次过期的，
      // 否则只打开过一次文件的用户会永远留着那份明文拷贝。
      await pruneStaleWorkingCopies();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onOpenProjects: () => setState(() => _index = 2),
        onOpenChanges: () => setState(() => _index = 1),
      ),
      const ChangeLogScreen(),
      const ProjectsScreen(),
      const ToolsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: '资讯',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar_rounded),
            label: '追踪',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route_rounded),
            label: '申请',
          ),
          NavigationDestination(
            icon: Icon(Icons.draw_outlined),
            selectedIcon: Icon(Icons.draw_rounded),
            label: '文档',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
