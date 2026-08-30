import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_store.dart';
import '../../shared/widgets/common.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  // 商品 ID 在 Play / App Store 里一经创建就永久保留，删不掉也改不了名。
  // 必须和服务端 entitlements.service.ts 的默认值一致，否则购买回来的收据
  // 对不上权益。两边都还没在商店创建过，趁现在定成产品名。
  static const monthlyId = 'waymark_premium_monthly';
  static const yearlyId = 'waymark_premium_yearly';
  final _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<ProductDetails> _products = const [];
  bool _storeAvailable = false;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) => setState(() => _message = '商店返回错误：$error'),
    );
    _loadStore();
  }

  Future<void> _loadStore() async {
    try {
      final available = await _store.isAvailable();
      var products = <ProductDetails>[];
      if (available) {
        final response = await _store.queryProductDetails({
          monthlyId,
          yearlyId,
        });
        products = response.productDetails;
        if (response.error != null) _message = response.error!.message;
      }
      if (!mounted) return;
      setState(() {
        _storeAvailable = available;
        _products = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '此设备暂时无法连接应用商店：$error';
      });
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _message = '购买正在等待商店确认');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() => _message = purchase.error?.message ?? '购买未完成');
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _message = '你已取消购买，没有产生新的权益');
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          await ref
              .read(appStoreProvider.notifier)
              .submitPurchase(
                provider: defaultTargetPlatform == TargetPlatform.iOS
                    ? 'APPLE'
                    : 'GOOGLE',
                productId: purchase.productID,
                verificationData:
                    purchase.verificationData.serverVerificationData,
              );
          if (purchase.pendingCompletePurchase) {
            await _store.completePurchase(purchase);
          }
          if (mounted) {
            // 原文案是「购买已提交并由服务端核验」。核验其实并不存在，
            // 这句话让人以为权益马上会到。说清楚它是待核验状态。
            setState(() => _message = '购买凭证已提交，等待服务端向商店核验后开通');
          }
        } catch (error) {
          if (mounted) setState(() => _message = '购买凭证尚未通过核验：$error');
        }
      }
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(appStoreProvider);
    final tierLabel = switch (account.entitlementTier) {
      'PREMIUM' => 'Premium',
      'TRIAL' => '7 天高级试用',
      _ => '永久免费',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('订阅与高级试用')),
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
                  const Text('当前权益'),
                  const SizedBox(height: 6),
                  Text(
                    tierLabel,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (account.trialEndsAt case final trialEndsAt?) ...[
                    const SizedBox(height: 8),
                    Text(
                      '试用截至 ${DateFormat('yyyy-MM-dd HH:mm').format(trialEndsAt.toLocal())}',
                    ),
                  ],
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: account.cloudStorageBytes == 0
                        ? 0
                        : (account.cloudStorageAllocatedBytes /
                                  account.cloudStorageBytes)
                              .clamp(0, 1),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '云文件 ${_storageLabel(account.cloudStorageUsedBytes)} / ${_storageLabel(account.cloudStorageBytes)}',
                  ),
                  if (account.cloudStorageReservedBytes > 0)
                    Text(
                      '另有 ${_storageLabel(account.cloudStorageReservedBytes)} 正在上传或等待完成',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (account.isCloudStorageOverLimit) ...[
                    const SizedBox(height: 8),
                    Text(
                      '当前已达到云空间上限。你仍可查看、下载、导出和删除已有文件，'
                      '本机原件不会被锁定；清理空间前不能继续上传。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!account.isSignedIn) ...[
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('高级试用和订阅权益需要账号。请先在“我的”页面登录；登录不会自动上传项目文件。'),
              ),
            ),
          ],
          const SectionHeader(title: '先免费试用'),
          _PlanCard(
            title: '7 天高级试用',
            price: 'A\$0',
            description: '主动开启一次，不要求支付方式，不会自动转为付费。',
            action: FilledButton.tonal(
              onPressed:
                  !account.isSignedIn || account.entitlementTier != 'FREE'
                  ? null
                  : () => _run(
                      () => ref.read(appStoreProvider.notifier).startTrial(),
                    ),
              child: const Text('明确开启 7 天试用'),
            ),
          ),
          // 服务端还没接通商店收据核验时，购买入口必须是关的。
          // 此时付款会被扣钱、`completePurchase` 关掉退款窗口，而权益永远不来。
          // 宁可少卖，不可收了钱不发货。
          if (!account.purchasesEnabled) ...[
            const SizedBox(height: 12),
            _PlanCard(
              title: 'Premium 订阅',
              price: '暂未开放',
              description:
                  account.purchasesDisabledReason ??
                  '订阅购买暂未开放，开放后会在应用内提示。',
              action: const FilledButton(
                onPressed: null,
                child: Text('暂未开放'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            _PlanCard(
              title: 'Premium 月付',
              price: _priceFor(monthlyId, 'A\$11.99/月'),
              description: '自动续订；高级文档编辑与 10 GB 云文件额度。',
              action: FilledButton(
                onPressed: !account.isSignedIn
                    ? null
                    : () => _purchase(monthlyId),
                child: const Text('通过应用商店订阅'),
              ),
            ),
            const SizedBox(height: 12),
            _PlanCard(
              title: 'Premium 年付',
              price: _priceFor(yearlyId, 'A\$89.99/年'),
              description: '自动续订；一次支付全年费用，权益与月付相同。',
              action: FilledButton(
                onPressed: !account.isSignedIn
                    ? null
                    : () => _purchase(yearlyId),
                child: const Text('通过应用商店订阅'),
              ),
            ),
          ],
          if (kDebugMode && (!_storeAvailable || _products.isEmpty)) ...[
            const SectionHeader(title: '本地开发沙盒'),
            const Text('仅 Debug 构建显示。它不产生真实扣款，也不会进入发布构建。'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: account.isSignedIn
                      ? () => _sandboxPurchase(monthlyId)
                      : null,
                  child: const Text('模拟月付成功'),
                ),
                OutlinedButton(
                  onPressed: account.isSignedIn
                      ? () => _sandboxPurchase(yearlyId)
                      : null,
                  child: const Text('模拟年付成功'),
                ),
              ],
            ),
          ],
          const SectionHeader(title: '恢复与管理'),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('恢复购买'),
            subtitle: const Text('只有你主动操作时才请求商店恢复'),
            onTap: !account.isSignedIn ? null : _restore,
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('管理或取消订阅'),
            subtitle: const Text('前往 Apple 或 Google 的订阅管理页面'),
            onTap: _manageSubscription,
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_message case final message?) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(message),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            '订阅会自动续订，除非你在商店规定的续订时间前取消。删除 Waymark 账号不会自动取消 Apple 或 Google 订阅；取消订阅也不会删除账号。试用结束或订阅到期后，仍可查看、导出和删除自己的原始文件与历史输出。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  String _priceFor(String id, String fallback) =>
      _products.where((product) => product.id == id).firstOrNull?.price ??
      fallback;

  Future<void> _purchase(String id) async {
    final product = _products.where((item) => item.id == id).firstOrNull;
    if (!_storeAvailable || product == null) {
      setState(() => _message = '商店商品尚未配置。Debug 环境可使用下方本地沙盒。');
      return;
    }
    await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> _sandboxPurchase(String productId) => _run(
    () => ref
        .read(appStoreProvider.notifier)
        .submitPurchase(
          provider: 'LOCAL_SANDBOX',
          productId: productId,
          verificationData:
              'local-sandbox-${DateTime.now().microsecondsSinceEpoch}',
        ),
  );

  Future<void> _restore() async {
    if (_storeAvailable) await _store.restorePurchases();
    await _run(
      () => ref.read(appStoreProvider.notifier).restorePurchasesFromServer(),
    );
  }

  Future<void> _manageSubscription() async {
    final uri = defaultTargetPlatform == TargetPlatform.iOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse(
            // 包名要与 build.gradle.kts 里的 applicationId 一致。改名成 Waymark
            // 之后这里没跟着改，链接指向一个不存在的应用——订阅用户点「管理订阅」
            // 会找不到自己的订阅，连退订入口都没有。
            'https://play.google.com/store/account/subscriptions?package=com.waymark.app',
          );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _message = null);
    try {
      await action();
      if (mounted) setState(() => _message = '权益状态已更新');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }
}

String _storageLabel(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.description,
    required this.action,
  });

  final String title;
  final String price;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SourceBadge(label: price),
            ],
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: action),
        ],
      ),
    ),
  );
}
