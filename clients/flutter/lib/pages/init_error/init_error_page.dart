import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/app_restart.dart';
import 'package:liza/utils/client_manager.dart';
import 'package:liza/widgets/liza_app.dart';
import 'package:liza/widgets/matrix.dart';

/// Shown when client initialization fails. Automatically retries in a loop
/// and displays a pulsing Liza logo so the user sees a seamless loading
/// experience rather than an error screen.
class InitErrorPage extends StatefulWidget {
  const InitErrorPage({super.key});

  @override
  State<InitErrorPage> createState() => _InitErrorPageState();
}

class _InitErrorPageState extends State<InitErrorPage>
    with SingleTickerProviderStateMixin {
  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _autoRecover();
  }

  Future<void> _autoRecover() async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      await Future.delayed(_retryDelay);
      if (!mounted) return;

      try {
        Logs().i('[Recovery] Auto-retry attempt ${attempt + 1}/$_maxRetries');
        final success = await Matrix.of(context).reinitializeClients();
        if (!mounted) return;

        if (success) {
          final hasLoggedIn = Matrix.of(context).widget.clients.any(
            (c) => c.isLogged(),
          );
          LizaApp.router.go(hasLoggedIn ? '/rooms' : '/home');
          return;
        }
      } catch (e, s) {
        Logs().e('[Recovery] Auto-retry attempt ${attempt + 1} failed', e, s);
        ClientManager.initializationError ??= e;
        ClientManager.initializationErrorStack ??= s;
      }
    }

    // All retries exhausted — hard restart the app.
    Logs().w('[Recovery] All retries exhausted, restarting app');
    AppRestart.restart();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ScaleTransition(
          scale: _pulseAnimation,
          child: Image.asset(
            'assets/logo.png',
            width: 120,
            height: 120,
          ),
        ),
      ),
    );
  }
}
