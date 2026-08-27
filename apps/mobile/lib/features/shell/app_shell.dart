import 'package:flutter/material.dart';

import '../change_log/change_log_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../projects/projects_screen.dart';
import '../tools/tools_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onOpenProjects: () => setState(() => _index = 2)),
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
            icon: Icon(Icons.newspaper_outlined),
            selectedIcon: Icon(Icons.newspaper),
            label: '资讯',
          ),
          NavigationDestination(
            icon: Icon(Icons.change_circle_outlined),
            selectedIcon: Icon(Icons.change_circle),
            label: '变更',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '项目',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_document),
            selectedIcon: Icon(Icons.edit_document),
            label: '工具',
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
