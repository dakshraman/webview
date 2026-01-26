import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const WeViewApp());
}

class WeViewApp extends StatelessWidget {
  const WeViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeView',
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
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isOnline = true;
  bool _dialogVisible = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _updateProgress(0),
          onProgress: (value) => _updateProgress(value / 100),
          onPageFinished: (_) async {
            await _syncNavigationState();
            _updateProgress(1);
          },
          onWebResourceError: (_) {
            _handleOffline(message: 'Unable to load the page. Check your internet connection.');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final status = await Connectivity().checkConnectivity();
    _handleConnectivityResults(status);

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_handleConnectivityResults);
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
    _controller.reload();
  }

  void _handleOffline({required String message}) {
    if (!mounted) return;
    setState(() => _isOnline = false);
    _showOfflineDialog(message);
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
      await _controller.reload();
    } else {
      _showOfflineDialog('Still no connection. Please try again.');
    }
  }

  void _updateProgress(double value) {
    if (!mounted) return;
    setState(() => _progress = value);
  }

  Future<void> _syncNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();

    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      await _syncNavigationState();
    }
  }

  Future<void> _goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
      await _syncNavigationState();
    }
  }

  Future<void> _reload() => _controller.reload();

  Future<void> _goHome() async {
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
    await _syncNavigationState();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_progress < 1 && _isOnline)
              LinearProgressIndicator(value: _progress),
            Expanded(
              child: _isOnline
                  ? WebViewWidget(controller: _controller)
                  : OfflineView(onRetry: _handleRetry),
            ),
          ],
        ),
      ),
      bottomNavigationBar: GlassBottomBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'Home',
              onPressed: _isOnline ? _goHome : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: _isOnline && _canGoBack ? _goBack : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Forward',
              onPressed: _isOnline && _canGoForward ? _goForward : null,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: () {
                if (_isOnline) {
                  _reload();
                } else {
                  _handleRetry();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const double height = 60;
    const double inset = 12;
    final radius = BorderRadius.circular(20);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(inset, 0, inset, inset),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: Colors.white.withOpacity(0.6),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  height: height,
                  child: IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        disabledForegroundColor: const Color(0x990F172A),
                        iconSize: 24,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
            Text(
              'No internet connection',
              style: theme.textTheme.titleLarge,
            ),
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
