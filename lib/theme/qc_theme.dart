import 'package:flutter/material.dart';

/// Matches website `VALID_THEMES` in `ThemeContext.jsx`.
enum QcThemeId {
  dark,
  light,
  eyecare,
  moonveil,
  sakura,
  sunset,
  aurora,
  ocean,
  nebula,
  dreamcloud,
}

extension QcThemeIdX on QcThemeId {
  String get label {
    switch (this) {
      case QcThemeId.dark:
        return 'Dark';
      case QcThemeId.light:
        return 'Light';
      case QcThemeId.eyecare:
        return 'Eyecare';
      case QcThemeId.moonveil:
        return 'Moonveil';
      case QcThemeId.sakura:
        return 'Sakura';
      case QcThemeId.sunset:
        return 'Sunset Ember';
      case QcThemeId.aurora:
        return 'Aurora';
      case QcThemeId.ocean:
        return 'Bioluminescent';
      case QcThemeId.nebula:
        return 'Nebula';
      case QcThemeId.dreamcloud:
        return 'Dreamcloud';
    }
  }

  String get hint {
    switch (this) {
      case QcThemeId.dark:
        return 'Rose gold leather';
      case QcThemeId.light:
        return 'Warm champagne';
      case QcThemeId.eyecare:
        return 'Warm amber';
      case QcThemeId.moonveil:
        return 'Purple moonlight';
      case QcThemeId.sakura:
        return 'Soft pink blossom';
      case QcThemeId.sunset:
        return 'Warm ember dusk';
      case QcThemeId.aurora:
        return 'Teal northern lights';
      case QcThemeId.ocean:
        return 'Deep bioluminescent';
      case QcThemeId.nebula:
        return 'Cosmic magenta';
      case QcThemeId.dreamcloud:
        return 'Pastel dream sky';
    }
  }

  bool get isModeTheme =>
      this == QcThemeId.dark || this == QcThemeId.light || this == QcThemeId.eyecare;

  bool get isFunTheme => !isModeTheme;

  /// Same light-like rule as the website.
  bool get isLightLike =>
      this == QcThemeId.light || this == QcThemeId.sakura || this == QcThemeId.dreamcloud;

  /// Circular gradient preview used in Settings (matches website FunThemeSwitcher).
  List<Color> get previewGradient {
    switch (this) {
      case QcThemeId.moonveil:
        return const [Color(0xFF8B5CF6), Color(0xFFA78BFA), Color(0xFFC4B5FD)];
      case QcThemeId.sakura:
        return const [Color(0xFFDB2777), Color(0xFFEC4899), Color(0xFFF9A8D4)];
      case QcThemeId.sunset:
        return const [Color(0xFFEA580C), Color(0xFFFB923C), Color(0xFFF472B6)];
      case QcThemeId.aurora:
        return const [Color(0xFF0D9488), Color(0xFF2DD4BF), Color(0xFFA78BFA)];
      case QcThemeId.ocean:
        return const [Color(0xFF0891B2), Color(0xFF22D3EE), Color(0xFF99F6E4)];
      case QcThemeId.nebula:
        return const [Color(0xFF7C3AED), Color(0xFFD946EF), Color(0xFF60A5FA)];
      case QcThemeId.dreamcloud:
        return const [Color(0xFFD946AF), Color(0xFFE879C9), Color(0xFFD8B4FE)];
      case QcThemeId.light:
        return const [Color(0xFF8A4A52), Color(0xFFA45D61), Color(0xFFE8B9AE)];
      case QcThemeId.eyecare:
        return const [Color(0xFFD97706), Color(0xFFF59E0B), Color(0xFFFBBF24)];
      case QcThemeId.dark:
        return const [Color(0xFF8A4A52), Color(0xFFE8B9AE), Color(0xFFF6E6D8)];
    }
  }

  static const modeThemes = [QcThemeId.light, QcThemeId.dark, QcThemeId.eyecare];

  static const funThemes = [
    QcThemeId.moonveil,
    QcThemeId.sakura,
    QcThemeId.sunset,
    QcThemeId.aurora,
    QcThemeId.ocean,
    QcThemeId.nebula,
    QcThemeId.dreamcloud,
  ];

  static QcThemeId? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final id in QcThemeId.values) {
      if (id.name == raw) return id;
    }
    return null;
  }
}

class QcColors {
  const QcColors({
    required this.body,
    required this.surface,
    required this.elevated,
    required this.input,
    required this.chat,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.accentCyan,
    required this.accentMuted,
    required this.bubbleMine,
    required this.bubbleMineFg,
    required this.bubbleTheirs,
    required this.bubbleTheirsFg,
    required this.error,
    required this.success,
    required this.overlay,
    required this.isDark,
    Color? onAccent,
    this.bubbleMineGradient,
    this.bubbleTheirsBorder,
  }) : _onAccent = onAccent;

  final Color body;
  final Color surface;
  final Color elevated;
  final Color input;
  final Color chat;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentHover;
  final Color accentCyan;
  final Color accentMuted;
  final Color bubbleMine;
  final Color bubbleMineFg;
  final Color bubbleTheirs;
  final Color bubbleTheirsFg;
  final Color error;
  final Color success;
  final Color overlay;
  final bool isDark;
  final Color? _onAccent;

  /// Optional gradient for outgoing bubbles (website `--bubble-mine-bg`).
  final Gradient? bubbleMineGradient;

  /// Optional hairline around incoming bubbles (website `--bubble-theirs-border`).
  final Color? bubbleTheirsBorder;

  /// Text / icon color on top of a solid [accent] fill (website `--accent-contrast`).
  Color get onAccent => _onAccent ?? bubbleMineFg;

  /// Website dark tokens — leather canvas, rose gold accent, champagne text.
  static const dark = QcColors(
    body: Color(0xFF1A1214),
    surface: Color(0xFF231819),
    elevated: Color(0xFF2D2022),
    input: Color(0xD92D2022),
    chat: Color(0xFF1E1517),
    border: Color(0xFF3D2C2E),
    textPrimary: Color(0xFFF6E6D8),
    textSecondary: Color(0xFFD9BFB3),
    textMuted: Color(0xFFB39A95),
    accent: Color(0xFFE8B9AE),
    accentHover: Color(0xFFECD2C4),
    accentCyan: Color(0xFFF6E6D8),
    accentMuted: Color(0x24E8B9AE),
    bubbleMine: Color(0xFF8A4A52),
    bubbleMineFg: Color(0xFFFFF5EE),
    bubbleTheirs: Color(0xFF33252A),
    bubbleTheirsFg: Color(0xFFF6E6D8),
    error: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    overlay: Color(0xB81A1214),
    isDark: true,
    onAccent: Color(0xFF2D1A1C),
    bubbleMineGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFA45D61), Color(0xFF8A4A52)],
    ),
    bubbleTheirsBorder: Color(0xFF4A3539),
  );

  /// Website light tokens — champagne base, deep mauve-rose accent.
  static const light = QcColors(
    body: Color(0xFFFBF4EE),
    surface: Color(0xFFFDF8F3),
    elevated: Color(0xFFFFFAF6),
    input: Color(0xEBFFFAF6),
    chat: Color(0xFFFBF2EA),
    border: Color(0xFFECD9CC),
    textPrimary: Color(0xFF2D1A1C),
    textSecondary: Color(0xFF5A4146),
    textMuted: Color(0xFF75605A),
    accent: Color(0xFF8A4A52),
    accentHover: Color(0xFF733D44),
    accentCyan: Color(0xFFA65F63),
    accentMuted: Color(0x1F8A4A52),
    bubbleMine: Color(0xFF8A4A52),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFFF3E0D3),
    bubbleTheirsFg: Color(0xFF2D1A1C),
    error: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    overlay: Color(0x592D1A1C),
    isDark: false,
    onAccent: Color(0xFFFFFFFF),
    bubbleMineGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8A4A52), Color(0xFFA45D61)],
    ),
    bubbleTheirsBorder: Color(0xFFAD8370),
  );

  static const eyecare = QcColors(
    body: Color(0xFF15130F),
    surface: Color(0xFF1E1B15),
    elevated: Color(0xFF28241C),
    input: Color(0xD928241C),
    chat: Color(0xFF1B1914),
    border: Color(0xFF322D23),
    textPrimary: Color(0xFFE6DFD3),
    textSecondary: Color(0xFFB5AA9A),
    textMuted: Color(0xFF7C7262),
    accent: Color(0xFFD97706),
    accentHover: Color(0xFFF59E0B),
    accentCyan: Color(0xFFFBBF24),
    accentMuted: Color(0x28D97706),
    bubbleMine: Color(0xFFD97706),
    bubbleMineFg: Color(0xFF1A140C),
    bubbleTheirs: Color(0xFF2A251C),
    bubbleTheirsFg: Color(0xFFF0E9DC),
    error: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    overlay: Color(0xB815130F),
    isDark: true,
  );

  static const moonveil = QcColors(
    body: Color(0xFF14122A),
    surface: Color(0xFF1C1A3A),
    elevated: Color(0xFF262347),
    input: Color(0xD9262347),
    chat: Color(0xFF191735),
    border: Color(0xFF2F2B57),
    textPrimary: Color(0xFFECE7FF),
    textSecondary: Color(0xFFB3A9DB),
    textMuted: Color(0xFF7D72A8),
    accent: Color(0xFFA78BFA),
    accentHover: Color(0xFF8B5CF6),
    accentCyan: Color(0xFF93C5FD),
    accentMuted: Color(0x28A78BFA),
    bubbleMine: Color(0xFF8B5CF6),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFF2A2750),
    bubbleTheirsFg: Color(0xFFF3EFFF),
    error: Color(0xFFF87171),
    success: Color(0xFF34D399),
    overlay: Color(0xB814122A),
    isDark: true,
  );

  static const sakura = QcColors(
    body: Color(0xFFFFF5F7),
    surface: Color(0xFFFFF0F3),
    elevated: Color(0xFFFFE4EA),
    input: Color(0xD9FFE4EA),
    chat: Color(0xFFFFF8F9),
    border: Color(0xFFF7D3DC),
    textPrimary: Color(0xFF4A2532),
    textSecondary: Color(0xFF8A5568),
    textMuted: Color(0xFFB98A9A),
    accent: Color(0xFFEC4899),
    accentHover: Color(0xFFDB2777),
    accentCyan: Color(0xFFFB7185),
    accentMuted: Color(0x24EC4899),
    bubbleMine: Color(0xFFDB2777),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFFFFD6E0),
    bubbleTheirsFg: Color(0xFF3B1524),
    error: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    overlay: Color(0x594A2532),
    isDark: false,
  );

  static const sunset = QcColors(
    body: Color(0xFF1A0E12),
    surface: Color(0xFF24141A),
    elevated: Color(0xFF301A1C),
    input: Color(0xD9301A1C),
    chat: Color(0xFF1E1114),
    border: Color(0xFF45231F),
    textPrimary: Color(0xFFFFF2E2),
    textSecondary: Color(0xFFD9AB8C),
    textMuted: Color(0xFFA8795F),
    accent: Color(0xFFF4A93A),
    accentHover: Color(0xFFE2792A),
    accentCyan: Color(0xFFFB7185),
    accentMuted: Color(0x28F4A93A),
    bubbleMine: Color(0xFFE2792A),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFF3A2226),
    bubbleTheirsFg: Color(0xFFFFF5EA),
    error: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    overlay: Color(0xB80F080A),
    isDark: true,
  );

  static const aurora = QcColors(
    body: Color(0xFF050E14),
    surface: Color(0xFF081722),
    elevated: Color(0xFF0E202E),
    input: Color(0xD90E202E),
    chat: Color(0xFF071420),
    border: Color(0xFF122A3A),
    textPrimary: Color(0xFFE8FFFB),
    textSecondary: Color(0xFF9FD8CC),
    textMuted: Color(0xFF5F8F88),
    accent: Color(0xFF2DD4BF),
    accentHover: Color(0xFF14B8A6),
    accentCyan: Color(0xFF67E8F9),
    accentMuted: Color(0x282DD4BF),
    bubbleMine: Color(0xFF0D9488),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFF123342),
    bubbleTheirsFg: Color(0xFFE8FFFB),
    error: Color(0xFFF87171),
    success: Color(0xFF22C55E),
    overlay: Color(0xB8050E14),
    isDark: true,
  );

  static const ocean = QcColors(
    body: Color(0xFF02100F),
    surface: Color(0xFF031917),
    elevated: Color(0xFF052220),
    input: Color(0xD9052220),
    chat: Color(0xFF021513),
    border: Color(0xFF0A332F),
    textPrimary: Color(0xFFE0FFFB),
    textSecondary: Color(0xFF8FD4C9),
    textMuted: Color(0xFF4F8A80),
    accent: Color(0xFF22D3EE),
    accentHover: Color(0xFF06B6D4),
    accentCyan: Color(0xFF22D3EE),
    accentMuted: Color(0x2822D3EE),
    bubbleMine: Color(0xFF0891B2),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFF0A3532),
    bubbleTheirsFg: Color(0xFFE0FFFB),
    error: Color(0xFFF87171),
    success: Color(0xFF22C55E),
    overlay: Color(0xB8020A09),
    isDark: true,
  );

  static const nebula = QcColors(
    body: Color(0xFF0A0518),
    surface: Color(0xFF120A24),
    elevated: Color(0xFF1C1036),
    input: Color(0xD91C1036),
    chat: Color(0xFF0F081F),
    border: Color(0xFF271447),
    textPrimary: Color(0xFFF5ECFF),
    textSecondary: Color(0xFFC3A8E0),
    textMuted: Color(0xFF8A6FA8),
    accent: Color(0xFFD946EF),
    accentHover: Color(0xFFC026D3),
    accentCyan: Color(0xFF818CF8),
    accentMuted: Color(0x2ED946EF),
    bubbleMine: Color(0xFFA21CAF),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFF241448),
    bubbleTheirsFg: Color(0xFFF5ECFF),
    error: Color(0xFFF87171),
    success: Color(0xFF34D399),
    overlay: Color(0xC10A0518),
    isDark: true,
  );

  static const dreamcloud = QcColors(
    body: Color(0xFFFDF3FB),
    surface: Color(0xFFFFF5FC),
    elevated: Color(0xFFFBE7F7),
    input: Color(0xD9FBE7F7),
    chat: Color(0xFFFEF7FD),
    border: Color(0xFFF5D9EF),
    textPrimary: Color(0xFF5B3A5C),
    textSecondary: Color(0xFF9C6EA0),
    textMuted: Color(0xFFC39EC7),
    accent: Color(0xFFE879C9),
    accentHover: Color(0xFFD946AF),
    accentCyan: Color(0xFFF9A8D4),
    accentMuted: Color(0x24E879C9),
    bubbleMine: Color(0xFFD946AF),
    bubbleMineFg: Color(0xFFFFFFFF),
    bubbleTheirs: Color(0xFFF3D4EE),
    bubbleTheirsFg: Color(0xFF3D2040),
    error: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    overlay: Color(0x525B3A5C),
    isDark: false,
  );

  static QcColors of(QcThemeId id) {
    switch (id) {
      case QcThemeId.light:
        return light;
      case QcThemeId.eyecare:
        return eyecare;
      case QcThemeId.moonveil:
        return moonveil;
      case QcThemeId.sakura:
        return sakura;
      case QcThemeId.sunset:
        return sunset;
      case QcThemeId.aurora:
        return aurora;
      case QcThemeId.ocean:
        return ocean;
      case QcThemeId.nebula:
        return nebula;
      case QcThemeId.dreamcloud:
        return dreamcloud;
      case QcThemeId.dark:
        return dark;
    }
  }
}

class QcTheme {
  static ThemeData material(QcColors c) {
    final scheme = c.isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: scheme,
      scaffoldBackgroundColor: c.body,
      colorScheme: ColorScheme(
        brightness: scheme,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.accentCyan,
        onSecondary: c.body,
        error: c.error,
        onError: Colors.white,
        surface: c.surface,
        onSurface: c.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: c.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.elevated,
        contentTextStyle: TextStyle(color: c.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.input,
        hintStyle: TextStyle(color: c.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.accent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(c.onAccent),
        side: BorderSide(color: c.border),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.elevated,
        selectedColor: c.accent,
        disabledColor: c.elevated,
        labelStyle: TextStyle(color: c.textSecondary),
        secondaryLabelStyle: TextStyle(color: c.onAccent),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
