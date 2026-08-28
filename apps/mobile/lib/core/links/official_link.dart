import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 在 App 内的浏览器视图里打开官方页面。
///
/// 我们只展示很短的摘录（引用配额见 `services/api/src/content/excerpt-quota.ts`），
/// 用户想看完整规定就必须回到官方原文。跳到外部浏览器会把人踢出 App，很多人就不回来了；
/// 用系统提供的应用内浏览器（Android Custom Tabs / iOS SFSafariViewController）能让人
/// 看完整页再退回来，同时地址栏仍显示官方域名——原文是谁写的、有没有被我们改过，
/// 用户自己能看见。这一点比省一次跳转重要，所以不用 WebView 自绘。
///
/// 不引入新依赖：`url_launcher` 已在依赖里。
Future<bool> openOfficialSource(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  // 只允许 https。官方来源都是 https；放行其它 scheme 等于把任意 intent 交给系统。
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    _report(context, '这条来源的链接无效，请到官网查看。');
    return false;
  }

  // 应用内浏览器不是每台设备都有（没装 Chrome 的 Android、部分定制系统），
  // 失败就退回外部浏览器，不能让「查看原文」变成一个没反应的按钮。
  for (final mode in [
    LaunchMode.inAppBrowserView,
    LaunchMode.externalApplication,
  ]) {
    try {
      if (await launchUrl(uri, mode: mode)) return true;
    } on PlatformException {
      continue;
    } on MissingPluginException {
      continue;
    }
  }
  if (context.mounted) _report(context, '这台设备打不开浏览器，请手动访问：$url');
  return false;
}

void _report(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
