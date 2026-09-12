import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../i18n/app_language.dart';

class OfficialWebViewScreen extends StatefulWidget {
  const OfficialWebViewScreen({required this.initialUri, super.key});

  final Uri initialUri;

  @override
  State<OfficialWebViewScreen> createState() => _OfficialWebViewScreenState();
}

class _OfficialWebViewScreenState extends State<OfficialWebViewScreen> {
  late final WebViewController _controller;
  var _progress = 0;
  String? _error;
  late Uri _currentUri;

  @override
  void initState() {
    super.initState();
    _currentUri = widget.initialUri;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ThemeData.light().colorScheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value),
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            setState(() {
              if (uri != null) _currentUri = uri;
              _error = null;
            });
          },
          onPageFinished: (_) => setState(() => _progress = 100),
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            setState(() => _error = error.description);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || uri.scheme != 'https') {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.initialUri);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _controller.canGoBack()) {
        await _controller.goBack();
      } else if (context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, '官方原文', 'Official source'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              _currentUri.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr(context, '刷新', 'Reload'),
            onPressed: _controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: tr(context, '用外部浏览器打开', 'Open in browser'),
            onPressed: () =>
                launchUrl(_currentUri, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: _error == null
          ? WebViewWidget(controller: _controller)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        context,
                        '官方页面暂时无法加载',
                        'The official page could not be loaded',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _controller.loadRequest(_currentUri),
                      icon: const Icon(Icons.refresh),
                      label: Text(tr(context, '重试', 'Try again')),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
