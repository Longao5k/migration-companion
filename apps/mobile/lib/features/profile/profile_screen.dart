import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/web_config.dart';
import '../../core/i18n/app_language.dart';
import '../../core/state/app_store.dart';
import '../subscription/subscription_screen.dart';

const subscriptionsEnabled = bool.fromEnvironment('SUBSCRIPTIONS');

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStoreProvider);
    final zh = isChineseUi(context);
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '我的' : 'Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
                    child: Icon(
                      state.isSignedIn ? Icons.person : Icons.person_outline,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    state.isSignedIn
                        ? (zh ? '已登录' : 'Signed in')
                        : (zh ? '访客模式' : 'Guest mode'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.isSignedIn
                        ? '${state.accountEmail}\n${zh ? '账号用于恢复清单和关注设置。' : 'Your account restores checklists and follow settings.'}'
                        : (zh
                              ? '资料和申请默认保存在这台设备上。'
                              : 'Documents and applications stay on this device by default.'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.isSignedIn
                        ? ref.read(appStoreProvider.notifier).signOut
                        : () => _signIn(context, ref),
                    child: Text(
                      state.isSignedIn
                          ? (zh ? '退出账号' : 'Sign out')
                          : (zh ? '注册或登录' : 'Sign up or sign in'),
                    ),
                  ),
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
                      zh ? '账号删除已排期' : 'Account deletion scheduled',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      zh
                          ? '预计 ${DateFormat('yyyy-MM-dd').format(state.deletionRequestedAt!.add(const Duration(days: 7)))} 清除云端账号数据。设备内资料不会自动删除。'
                          : 'Cloud account data is scheduled for deletion by ${DateFormat.yMMMd().format(state.deletionRequestedAt!.add(const Duration(days: 7)))}. On-device data will remain.',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _cancelDeletion(context, ref),
                      child: Text(zh ? '撤回删除申请' : 'Cancel deletion'),
                    ),
                  ],
                ),
              ),
            ),
          _Section(title: zh ? '偏好与隐私' : 'Preferences & privacy'),
          _Tile(
            icon: Icons.notifications_active_outlined,
            title: zh ? '资讯关注' : 'Update preferences',
            subtitle: state.isSignedIn
                ? (state.policyNotificationsEnabled
                      ? (zh ? '已开启' : 'Enabled')
                      : (zh ? '未开启' : 'Disabled'))
                : (zh ? '登录后可同步关注设置' : 'Sign in to sync preferences'),
            onTap: state.isSignedIn
                ? () => _notificationPreferences(context, ref)
                : null,
          ),
          _Tile(
            icon: Icons.lock_outline,
            title: zh ? '本机资料' : 'On-device documents',
            subtitle: zh
                ? '你的文件默认只保存在这台设备'
                : 'Your files stay on this device by default',
            onTap: () => _info(
              context,
              zh ? '本机资料' : 'On-device documents',
              zh ? '添加到“我的资料”的文件保存在 App 私有目录。只有你主动分享时，文件才会离开设备。' : 'Files added to My documents are stored in the app private directory. They leave the device only when you choose to share them.',
            ),
          ),
          _Tile(
            icon: Icons.delete_outline,
            title: zh ? '删除账号与云端数据' : 'Delete account and cloud data',
            subtitle: state.deletionRequestedAt == null
                ? (zh ? '可在 App 内发起' : 'Request from the app')
                : (zh ? '已提交' : 'Request submitted'),
            onTap: state.isSignedIn && state.deletionRequestedAt == null
                ? () => _deleteAccount(context, ref)
                : null,
          ),
          if (subscriptionsEnabled) ...[
            _Section(title: zh ? '订阅' : 'Subscription'),
            _Tile(
              icon: Icons.workspace_premium_outlined,
              title: 'Waymark Premium',
              subtitle: state.entitlementTier,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              ),
            ),
          ],
          _Section(title: zh ? '关于' : 'About'),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: zh ? '隐私政策' : 'Privacy policy',
            subtitle: zh ? '了解数据如何保存和删除' : 'How data is stored and deleted',
            onTap: () => launchUrl(Uri.parse('${publicWebBaseUrl()}/privacy')),
          ),
          _Tile(
            icon: Icons.gavel_outlined,
            title: zh ? '使用条款' : 'Terms of use',
            subtitle: zh ? 'Waymark 不是政府服务，也不提供个人法律意见' : 'Waymark is not a government service and does not provide personal legal advice',
            onTap: () => launchUrl(Uri.parse('${publicWebBaseUrl()}/terms')),
          ),
          _Tile(
            icon: Icons.code_outlined,
            title: zh ? '开源软件许可' : 'Open-source licences',
            subtitle: zh
                ? '查看 App 使用的第三方软件与许可'
                : 'Third-party software and licence notices',
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Waymark'),
          ),
          _Tile(
            icon: Icons.support_agent_outlined,
            title: zh ? '帮助与支持' : 'Help & support',
            subtitle: zh ? '获取测试版本支持' : 'Support for this test build',
            onTap: () => _info(
              context,
              zh ? '帮助与支持' : 'Help & support',
              zh ? '内测期间请联系向你提供此版本的人。公开支持渠道会在上架前加入。' : 'During testing, contact the person who provided this build. Public support details will be added before store release.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    leading: Icon(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

Future<void> _signIn(BuildContext context, WidgetRef ref) async {
  final zh = isChineseUi(context);
  const pilotAuthEnabled = bool.fromEnvironment('PILOT_AUTH');
  final email = TextEditingController(
    text: kDebugMode ? 'owner@example.com' : '',
  );
  final code = TextEditingController();
  final value = await showDialog<({String email, String code})>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(zh ? '登录 Waymark' : 'Sign in to Waymark'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: zh ? '邮箱地址' : 'Email address',
            ),
          ),
          if (pilotAuthEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: code,
              obscureText: true,
              decoration: InputDecoration(
                labelText: zh ? '内测访问码' : 'Pilot access code',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            email: email.text.trim(),
            code: code.text,
          )),
          child: Text(zh ? '继续' : 'Continue'),
        ),
      ],
    ),
  );
  if (value == null) return;
  try {
    await ref
        .read(appStoreProvider.notifier)
        .signIn(value.email, accessCode: value.code);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${zh ? '登录失败' : 'Sign-in failed'}: $error')),
      );
    }
  }
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final zh = isChineseUi(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(zh ? '删除账号与云端数据？' : 'Delete account and cloud data?'),
      content: Text(
        zh ? '确认后，云端账号数据会进入删除流程。设备内资料不会自动删除，Apple 或 Google 订阅也需要在商店中单独取消。' : 'Cloud account data will enter the deletion process. On-device documents remain, and Apple or Google subscriptions must be cancelled separately in the store.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(zh ? '提交删除申请' : 'Request deletion'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(appStoreProvider.notifier).requestAccountDeletion();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${zh ? '提交失败' : 'Request failed'}: $error')),
      );
    }
  }
}

Future<void> _cancelDeletion(BuildContext context, WidgetRef ref) async {
  final zh = isChineseUi(context);
  try {
    await ref.read(appStoreProvider.notifier).cancelAccountDeletion();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${zh ? '撤回失败' : 'Cancellation failed'}: $error'),
        ),
      );
    }
  }
}

Future<void> _notificationPreferences(
  BuildContext context,
  WidgetRef ref,
) async {
  final zh = isChineseUi(context);
  final current = ref.read(appStoreProvider);
  var enabled = current.policyNotificationsEnabled;
  var importantOnly = current.importantNotificationsOnly;
  final jurisdictions = current.followedJurisdictions.toSet();
  final tags = current.followedTags.toSet();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(zh ? '资讯关注' : 'Update preferences'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  zh ? '接收已核实的重要更新' : 'Receive verified important updates',
                ),
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
              const SizedBox(height: 6),
              Text(
                zh ? '地区' : 'Regions',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final entry in current.taxonomy.jurisdictions)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(entry.display),
                  value: jurisdictions.contains(entry.code),
                  onChanged: enabled
                      ? (value) => setState(
                          () => value == true
                              ? jurisdictions.add(entry.code)
                              : jurisdictions.remove(entry.code),
                        )
                      : null,
                ),
              if (current.taxonomy.visas.isNotEmpty) ...[
                Text(
                  zh ? '签证（不选表示全部）' : 'Visas (none means all)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final entry in current.taxonomy.visas)
                      FilterChip(
                        label: Text(entry.code),
                        selected: tags.contains(entry.code),
                        onSelected: enabled
                            ? (value) => setState(
                                () => value
                                    ? tags.add(entry.code)
                                    : tags.remove(entry.code),
                              )
                            : null,
                      ),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  zh ? '只通知重大与重要变化' : 'Only major and important changes',
                ),
                value: importantOnly,
                onChanged: enabled
                    ? (value) => setState(() => importantOnly = value)
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: enabled && jurisdictions.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: Text(zh ? '保存' : 'Save'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true) return;
  await ref
      .read(appStoreProvider.notifier)
      .updateNotificationPreferences(
        enabled: enabled,
        jurisdictions: jurisdictions.toList(),
        tags: tags.toList()..sort(),
        importantOnly: importantOnly,
      );
}

Future<void> _info(BuildContext context, String title, String body) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '知道了', 'OK')),
          ),
        ],
      ),
    );
