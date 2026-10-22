import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/qc_socket.dart';
import 'app.dart';
import 'crypto/key_storage.dart';
import 'state/auth_controller.dart';
import 'state/chat_controller.dart';
import 'state/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface unexpected errors instead of a silent black screen.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  final storage = KeyStorage.instance;
  try {
    await storage.init().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('KeyStorage.init slow/failed: $e');
  }
  final socket = QcSocket();
  final theme = ThemeController(storage);
  try {
    await theme.load();
  } catch (e) {
    debugPrint('Theme load failed: $e');
  }
  final auth = AuthController(storage: storage, socket: socket);

  // Show UI immediately — ChatController is lazy so landing/boot never
  // pays for inbox/socket wiring on frame 0.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(
          lazy: true,
          create: (_) => ChatController(
            auth: auth,
            storage: storage,
            socket: socket,
          ),
        ),
      ],
      child: const QuantumChatApp(),
    ),
  );

  // Fire-and-forget so secure-storage / network cannot stall the UI isolate.
  unawaited(auth.bootstrap());
}
