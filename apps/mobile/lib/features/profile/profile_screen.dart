import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_store.dart';
import '../../core/api/web_config.dart';
import '../../shared/widgets/common.dart';
import '../subscription/subscription_screen.dart';

/// 订阅入口是否可见。
///
/// 第一版会靠订阅出售 PDF / Word 的编辑能力，所以计费依赖留在构建里。
/// 但在编辑真正接进来之前这个开关保持关闭：权益还不存在就卖，既违反商店计费政策，
/// 也踩澳洲消费者法。编辑能力上线后用 --dart-define=SUBSCRIPTIONS=true 打开，
/// 并把商店表单的「应用内购买」改成「是」。
const subscriptionsEnabled = bool.fromEnvironment('SUBSCRIPTIONS');

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
                        ? '${state.accountEmail}\n换手机时可以用这个账号找回你的清单。'
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
          if (state.deletionRequestedAt != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '账号删除已排期',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '预计 ${DateFormat('yyyy-MM-dd').format(state.deletionRequestedAt!.add(const Duration(days: 7)))} 清除云端主数据。此前可撤回；本机项目不会自动删除。',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _cancelAccountDeletion(context, ref),
                      child: const Text('撤回删除申请'),
                    ),
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
            subtitle: state.deletionRequestedAt == null
                ? 'App 内可发起；订阅需单独管理'
                : '已提交，可在计划清除前撤回',
            onTap: state.isSignedIn && state.deletionRequestedAt == null
                ? () => _deleteAccount(context, ref)
                : null,
          ),
          _SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: '政策通知与关注',
            subtitle: state.isSignedIn
                ? state.policyNotificationsEnabled
                      ? '已开启 · ${state.followedTags.isEmpty ? '全部南澳主题' : state.followedTags.join(' / ')}'
                      : '已关闭；可按 190/491 关注'
                : '登录后同步关注规则；本机材料提醒不受影响',
            onTap: state.isSignedIn
                ? () => _showNotificationPreferences(context, ref)
                : null,
          ),
          // 权益（PDF / Word 编辑）尚未交付，入口按 subscriptionsEnabled 关闭。
          if (subscriptionsEnabled) ...[
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
          ],
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
              '内测期间请直接联系把这个版本发给你的人。'
                  '正式发布前这里会换成公开的支持邮箱。',
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
  const pilotAuthEnabled = bool.fromEnvironment('PILOT_AUTH');
  final controller = TextEditingController(
    text: kDebugMode ? 'owner@example.com' : '',
  );
  final accessCodeController = TextEditingController();
  final credentials = await showDialog<({String email, String accessCode})>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        pilotAuthEnabled
            ? '内测账号登录'
            : kDebugMode
            ? '本地开发账号'
            : '邮箱登录',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '邮箱地址'),
          ),
          if (pilotAuthEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: accessCodeController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '内测访问码',
                helperText: '只用于当前封闭测试，正式登录上线后会替换。',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            email: controller.text.trim(),
            accessCode: accessCodeController.text,
          )),
          child: const Text('继续'),
        ),
      ],
    ),
  );
  if (credentials == null || !context.mounted) return;
  try {
    await ref
        .read(appStoreProvider.notifier)
        .signIn(credentials.email, accessCode: credentials.accessCode);
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
      content: const Text('账号主数据目标在确认后 7 天内删除；备份轮换最长 35 天。本机项目不会在此步骤中自动删除。Apple 或 Google 订阅也不会自动取消，请另行前往商店管理。'),
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

Future<void> _cancelAccountDeletion(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(appStoreProvider.notifier).cancelAccountDeletion();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除申请已撤回')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('撤回失败：$error')));
    }
  }
}

Future<void> _showNotificationPreferences(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(appStoreProvider);
  var enabled = current.policyNotificationsEnabled;
  var importantOnly = current.importantNotificationsOnly;
  var includeSa = current.followedJurisdictions.contains('AU-SA');
  var includeFederal = current.followedJurisdictions.contains('AU-FED');
  final tags = current.followedTags.toSet();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('政策通知与关注'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('接收已核实的政策通知'),
                subtitle: const Text('重大与重要变化必须先经人工核实。'),
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('南澳州担保'),
                value: includeSa,
                onChanged: enabled
                    ? (value) => setState(() => includeSa = value ?? false)
                    : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('必要的联邦上游'),
                value: includeFederal,
                onChanged: enabled
                    ? (value) => setState(() => includeFederal = value ?? false)
                    : null,
              ),
              const SizedBox(height: 8),
              const Text('签证主题（不选表示全部）'),
              for (final tag in const ['190', '491'])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tag),
                  value: tags.contains(tag),
                  onChanged: enabled
                      ? (value) => setState(
                          () =>
                              value == true ? tags.add(tag) : tags.remove(tag),
                        )
                      : null,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('只通知重大与重要变化'),
                value: importantOnly,
                onChanged: enabled
                    ? (value) => setState(() => importantOnly = value)
                    : null,
              ),
              const Text(
                '锁屏只显示泛化文案，不显示资格判断、材料名称或政策正文。生产推送通道仍需 APNs/FCM 凭据。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: enabled && !includeSa && !includeFederal
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (result != true || !context.mounted) return;
  try {
    await ref
        .read(appStoreProvider.notifier)
        .updateNotificationPreferences(
          enabled: enabled,
          jurisdictions: [if (includeSa) 'AU-SA', if (includeFederal) 'AU-FED'],
          tags: tags.toList()..sort(),
          importantOnly: importantOnly,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('关注规则已保存')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }
}
