import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_store.dart';
import '../../core/api/web_config.dart';
import '../../shared/widgets/common.dart';
import '../subscription/subscription_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(
                      state.isSignedIn ? Icons.person : Icons.person_outline,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.isSignedIn ? '已登录账号' : '访客模式',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.isSignedIn
                        ? '${state.accountEmail}\n项目归属已保护；文件仍按项目决定是否上传。'
                        : '项目保存在本机。你可以随时导出备份，不会遇到登录墙。',
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => state.isSignedIn
                        ? ref.read(appStoreProvider.notifier).signOut()
                        : _signIn(context, ref),
                    child: Text(state.isSignedIn ? '退出账号（保留本机项目）' : '注册或登录'),
                  ),
                  if (!state.isSignedIn && kDebugMode) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Debug 构建使用本地邮箱账号；正式构建将接入邮箱验证码。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SectionHeader(title: '数据与隐私'),
          _SettingsTile(
            icon: Icons.cloud_outlined,
            title: '云同步',
            subtitle: '按项目开启；默认关闭',
            onTap: () => _showInfo(
              context,
              '云同步',
              '登录不会上传任何文件。请进入具体项目，由项目所有者单独开启云文件同步。',
            ),
          ),
          _SettingsTile(
            icon: Icons.download_outlined,
            title: '导出与恢复',
            subtitle: '取回完整项目备份',
            onTap: () =>
                _showInfo(context, '导出与恢复', '在“材料项目”页面可导入备份；进入具体项目可导出加密备份。'),
          ),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: '删除账号与数据',
            subtitle: 'App 内可发起；订阅需单独管理',
            onTap: state.isSignedIn ? () => _deleteAccount(context, ref) : null,
          ),
          const SectionHeader(title: '订阅'),
          _SettingsTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Migration Companion Premium',
            subtitle:
                '${_tierLabel(state.entitlementTier)} · A\$11.99/月 · A\$89.99/年',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
            ),
          ),
          _SettingsTile(
            icon: Icons.restore,
            title: '恢复购买',
            subtitle: '从 Apple 或 Google 商店恢复权益',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
            ),
          ),
          const SectionHeader(title: '关于'),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: '隐私政策',
            subtitle: '数据范围、保存、删除与跨境处理',
            onTap: () => launchUrl(Uri.parse('${publicWebBaseUrl()}/privacy')),
          ),
          _SettingsTile(
            icon: Icons.gavel_outlined,
            title: '信息与法律边界',
            subtitle: '不是政府官方服务，不提供个人移民法律意见',
            onTap: () => launchUrl(Uri.parse('${publicWebBaseUrl()}/terms')),
          ),
          _SettingsTile(
            icon: Icons.support_agent_outlined,
            title: '帮助与支持',
            subtitle: '订阅、退款、权限和数据问题',
            onTap: () => _showInfo(
              context,
              '帮助与支持',
              '本地开发版本暂未配置公开支持邮箱。正式发布前会替换为运营主体的支持渠道。',
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    leading: Icon(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

String _tierLabel(String tier) => switch (tier) {
  'PREMIUM' => 'Premium',
  'TRIAL' => '高级试用中',
  _ => '永久免费',
};

Future<void> _signIn(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(
    text: kDebugMode ? 'owner@example.com' : '',
  );
  final email = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(kDebugMode ? '本地开发账号' : '邮箱登录'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: '邮箱地址'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('继续'),
        ),
      ],
    ),
  );
  if (email == null || !context.mounted) return;
  try {
    await ref.read(appStoreProvider.notifier).signIn(email);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登录失败：$error')));
    }
  }
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('申请删除账号与云端数据？'),
      content: const Text(
        '账号主数据目标在确认后 7 天内删除；备份轮换最长 35 天。本机项目不会在此步骤中自动删除。Apple 或 Google 订阅也不会自动取消，请另行前往商店管理。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('提交删除申请'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(appStoreProvider.notifier).requestAccountDeletion();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除申请已提交')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('提交失败：$error')));
    }
  }
}

Future<void> _showInfo(BuildContext context, String title, String body) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
