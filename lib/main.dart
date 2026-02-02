import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const WeViewApp());
}

class WeViewApp extends StatelessWidget {
  const WeViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RR Dream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WebViewScreen(initialUrl: 'https://rrdream.in'),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final Uri _initialUri;
  double _progress = 0;
  bool _isOnline = true;
  bool _dialogVisible = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initialUri = Uri.parse(widget.initialUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _shouldOpenExternally(uri)) {
              unawaited(_openExternalUrl(uri));
              return NavigationDecision.prevent;
            }

            unawaited(_clearWebViewData());
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => _updateProgress(0),
          onProgress: (value) => _updateProgress(value / 100),
          onPageFinished: (_) => _updateProgress(1),
          onWebResourceError: (_) {
            _handleOffline(
              message:
                  'Unable to load the page. Check your internet connection.',
            );
          },
        ),
      );
    unawaited(_loadInitialUrl());
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final status = await Connectivity().checkConnectivity();
    _handleConnectivityResults(status);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityResults,
    );
  }

  void _handleConnectivityResults(List<ConnectivityResult> results) {
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _handleConnectivityResult(result);
  }

  void _handleConnectivityResult(ConnectivityResult result) {
    final online = result != ConnectivityResult.none;
    if (!mounted || _isOnline == online) return;

    if (!online) {
      _handleOffline(message: 'You appear to be offline.');
      return;
    }

    setState(() => _isOnline = true);
    _closeDialogIfOpen();
    unawaited(_reload());
  }

  void _handleOffline({required String message}) {
    if (!mounted) return;
    setState(() => _isOnline = false);
    unawaited(_showOfflineDialog(message));
  }

  Future<void> _showOfflineDialog(String message) async {
    if (_dialogVisible || !mounted) return;
    _dialogVisible = true;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('No Connection'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop();
              _dialogVisible = false;
              _handleRetry();
            },
            isDefaultAction: true,
            child: const Text('Retry'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop();
              _dialogVisible = false;
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _closeDialogIfOpen() {
    if (!_dialogVisible) return;
    Navigator.of(context, rootNavigator: true).pop();
    _dialogVisible = false;
  }

  Future<void> _handleRetry() async {
    final status = await Connectivity().checkConnectivity();
    final online = status.any((r) => r != ConnectivityResult.none);

    if (online) {
      setState(() => _isOnline = true);
      await _reload();
    } else {
      unawaited(_showOfflineDialog('Still no connection. Please try again.'));
    }
  }

  void _updateProgress(double value) {
    if (!mounted) return;
    setState(() => _progress = value);
  }

  bool _shouldOpenExternally(Uri uri) {
    if (uri.scheme == 'about' || uri.scheme == 'data') {
      return false;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return true;
    }

    return uri.host != _initialUri.host;
  }

  Future<void> _openExternalUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _clearWebViewData() async {
    await _controller.clearCache();
  }

  Future<void> _loadInitialUrl() async {
    await _clearWebViewData();
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _reload() async {
    await _clearWebViewData();
    await _controller.reload();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_progress < 1 && _isOnline)
              LinearProgressIndicator(value: _progress),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _isOnline
                        ? WebViewWidget(controller: _controller)
                        : OfflineView(onRetry: _handleRetry),
                  ),
                  Positioned.fill(
                    child: SwipeReloadRegion(
                      isEnabled: _isOnline,
                      onTriggered: _reload,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_isOnline) {
            unawaited(_reload());
          } else {
            unawaited(_handleRetry());
          }
        },
        tooltip: 'Reload',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class SwipeReloadRegion extends StatefulWidget {
  const SwipeReloadRegion({
    super.key,
    required this.onTriggered,
    required this.isEnabled,
  });

  final Future<void> Function() onTriggered;
  final bool isEnabled;

  @override
  State<SwipeReloadRegion> createState() => _SwipeReloadRegionState();
}

class _SwipeReloadRegionState extends State<SwipeReloadRegion> {
  static const double _triggerDistance = 70;
  static const double _edgeHeight = 56;

  int? _activePointer;
  double _dragDistance = 0;
  bool _triggered = false;
  bool _eligible = false;

  void _reset() {
    _activePointer = null;
    _dragDistance = 0;
    _triggered = false;
    _eligible = false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.isEnabled) return;
    _activePointer = event.pointer;
    _eligible = event.localPosition.dy <= _edgeHeight;
    _dragDistance = 0;
    _triggered = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.isEnabled || _triggered || !_eligible) return;
    if (_activePointer != event.pointer) return;
    if (event.delta.dy <= 0) return;
    _dragDistance += event.delta.dy;
    if (_dragDistance >= _triggerDistance) {
      _triggered = true;
      unawaited(widget.onTriggered());
    }
  }

  void _handlePointerUp(PointerUpEvent event) => _reset();

  void _handlePointerCancel(PointerCancelEvent event) => _reset();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: const SizedBox.expand(),
    );
  }
}

class OfflineView extends StatelessWidget {
  const OfflineView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/logo.webp',
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text('No internet connection', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
