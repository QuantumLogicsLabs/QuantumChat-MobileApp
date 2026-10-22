import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/chat_home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/unlock_keys_screen.dart';
import 'state/auth_controller.dart';
import 'state/theme_controller.dart';
import 'theme/qc_theme.dart';

class QuantumChatApp extends StatelessWidget {
  const QuantumChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: 'QuantumChat',
      debugShowCheckedModeBanner: false,
      theme: QcTheme.material(theme.colors),
      // Never show a silent black failure — surface the error brightly.
      builder: (context, child) {
        ErrorWidget.builder = (details) {
          return Material(
            color: const Color(0xFF1A0A0A),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ListView(
                  children: [
                    const Text(
                      'QuantumChat hit an error',
                      style: TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      details.exceptionAsString(),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        };
        return child ?? const SizedBox.shrink();
      },
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  /// Hold a simple boot frame so the engine always paints something visible
  /// before we mount ChatHome / Landing (those trees are heavy on emulators).
  bool _allowHeavy = false;

  @override
  void initState() {
    super.initState();
    // Give the engine two frames + a short delay so software/Skia can present
    // before we mount landing or chat (avoids logo → black on slow AVDs).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _allowHeavy = true);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (!auth.ready || !_allowHeavy) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1214),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Quantum',
                  style: TextStyle(
                    color: Color(0xFFF6E6D8),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                  children: [
                    TextSpan(
                      text: 'Chat',
                      style: TextStyle(color: Color(0xFFE8B9AE)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFFE8B9AE)),
              SizedBox(height: 16),
              Text(
                'Starting…',
                style: TextStyle(color: Color(0xFFB39A95), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (auth.user == null) return const LandingScreen();
    if (!auth.hasLocalKeyring) return const UnlockKeysScreen();
    return const ChatHomeScreen();
  }
}
