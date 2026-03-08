import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    print("Handling a background message: ${message.messageId}");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
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
  static const String _pullToRefreshChannel = 'PullToRefreshChannel';
  static const Duration _pullToRefreshCooldown = Duration(seconds: 2);
  static const String _broadcastTopic = 'all-users';

  late final WebViewController _controller;
  late final Uri _initialUri;
  double _progress = 0;
  bool _isOnline = true;
  bool _dialogVisible = false;
  DateTime? _lastPullToRefreshAt;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<String>? _fcmTokenRefreshSubscription;

  @override
  void initState() {
    super.initState();
    _initialUri = Uri.parse(widget.initialUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        _pullToRefreshChannel,
        onMessageReceived: (message) {
          if (message.message == 'refresh') {
            _handlePullToRefresh();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _shouldOpenExternally(uri)) {
              unawaited(_openExternalUrl(uri));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => _updateProgress(0),
          onProgress: (value) => _updateProgress(value / 100),
          onPageFinished: (_) {
            _updateProgress(1);
            unawaited(_installPullToRefreshJs());
          },
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
    _setupFCM();
  }

  Future<void> _setupFCM() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (kDebugMode) {
      print('User granted permission: ${settings.authorizationStatus}');
    }

    final token = await messaging.getToken();
    if (kDebugMode) {
      print('=========================================');
      print('FCM Token: $token');
      print('=========================================');
    }

    await _subscribeToBroadcastTopic(messaging);

    _fcmTokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        print('FCM token refreshed: $newToken');
      }
      await _subscribeToBroadcastTopic(messaging);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');
      }

      if (message.notification != null && mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(message.notification?.title ?? 'Notification'),
            content: Text(message.notification?.body ?? ''),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  Future<void> _subscribeToBroadcastTopic(FirebaseMessaging messaging) async {
    try {
      await messaging.subscribeToTopic(_broadcastTopic);
      if (kDebugMode) {
        print('Subscribed to topic: $_broadcastTopic');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Topic subscription failed: $error');
      }
    }
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

  void _handlePullToRefresh() {
    if (!_isOnline) return;
    final now = DateTime.now();
    if (_lastPullToRefreshAt != null &&
        now.difference(_lastPullToRefreshAt!) < _pullToRefreshCooldown) {
      return;
    }
    _lastPullToRefreshAt = now;
    unawaited(_reload());
  }

  Future<void> _installPullToRefreshJs() async {
    if (!_isOnline) return;
    const script =
        '''
(function() {
  if (window.__weviewPullToRefreshInstalled) return;
  window.__weviewPullToRefreshInstalled = true;
  var startY = 0;
  var tracking = false;
  var triggered = false;
  function getScrollTop() {
    var se = document.scrollingElement;
    if (se) return se.scrollTop || 0;
    return (document.documentElement && document.documentElement.scrollTop) ||
      (document.body && document.body.scrollTop) || 0;
  }
  window.addEventListener('touchstart', function(e) {
    if (getScrollTop() <= 0) {
      tracking = true;
      triggered = false;
      startY = e.touches[0].clientY;
    } else {
      tracking = false;
    }
  }, {passive: true});
  window.addEventListener('touchmove', function(e) {
    if (!tracking || triggered) return;
    var dy = e.touches[0].clientY - startY;
    if (dy > 70) {
      triggered = true;
      if (window.${_pullToRefreshChannel} &&
          window.${_pullToRefreshChannel}.postMessage) {
        window.${_pullToRefreshChannel}.postMessage('refresh');
      }
    }
  }, {passive: true});
  window.addEventListener('touchend', function() { tracking = false; }, {passive: true});
  window.addEventListener('touchcancel', function() { tracking = false; }, {passive: true});
})();
''';
    await _controller.runJavaScript(script);
  }

  Future<void> _loadInitialUrl() async {
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _reload() async {
    await _controller.reload();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _fcmTokenRefreshSubscription?.cancel();
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
                ],
              ),
            ),
          ],
        ),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     if (_isOnline) {
      //       unawaited(_reload());
      //     } else {
      //       unawaited(_handleRetry());
      //     }
      //   },
      //   tooltip: 'Reload',
      //   child: const Icon(Icons.refresh),
      // ),
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
