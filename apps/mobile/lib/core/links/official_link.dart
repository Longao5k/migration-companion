import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/app_language.dart';
import 'official_web_view.dart';

/// Opens a verified HTTPS source in Waymark's own reader on mobile.
/// The visible host label makes it clear which organisation owns the page.
Future<bool> openOfficialSource(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    _report(context, tr(context, '这个官方链接无效。', 'This source link is invalid.'));
    return false;
  }

  final mobileReader =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  if (mobileReader && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfficialWebViewScreen(initialUri: uri),
      ),
    );
    return true;
  }

  if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
  if (context.mounted) {
    _report(context, tr(context, '无法打开这个官方页面。', 'Unable to open this source.'));
  }
  return false;
}

void _report(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
