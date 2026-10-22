import 'package:flutter/material.dart';

/// Minimal entry to prove the emulator GPU can paint Flutter content.
/// Run: flutter run -d emulator-5554 -t lib/smoke_main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF00C853),
        body: Center(
          child: Text(
            'SMOKE OK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ),
  );
}
