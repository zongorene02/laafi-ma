import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identité visuelle de Laafi Ma : une palette CHAUDE et CALME.
/// - terre cuite douce (couleur principale : boutons, sélection) ;
/// - vert feuille (accent rassurant : santé, réussite) ;
/// - fonds crème plutôt que blanc pur, moins agressifs au soleil.
/// Le rouge vif est réservé à l'alerte et à la sortie rapide.
abstract final class AppTheme {
  static const _primary = Color(0xFFB4532A);
  static const leaf = Color(0xFF2F7D5B);
  static const terracotta = Color(0xFFD9774A);
  static const amber = Color(0xFFE9A23B);
  static const danger = Color(0xFFC62828);
  static const sky = Color(0xFF3B7EA1);
  static const plum = Color(0xFF8E4A7A);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9C4221), Color(0xFFC8693D), Color(0xFFE9A23B)],
  );

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [terracotta, amber],
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: _primary, brightness: brightness);
    final colorScheme = base.copyWith(
      primary: isDark ? const Color(0xFFF4A27A) : _primary,
      onPrimary: isDark ? const Color(0xFF3A1406) : Colors.white,
      tertiary: isDark ? const Color(0xFF7FD1A8) : leaf,
      tertiaryContainer: isDark ? const Color(0xFF0F3B28) : const Color(0xFFDDF1E6),
      onTertiaryContainer: isDark ? const Color(0xFFCDEFDC) : const Color(0xFF0C3B26),
      // Fonds crème (clair) ou brun très sombre (sombre).
      surface: isDark ? const Color(0xFF1A1411) : const Color(0xFFFFF8F2),
      surfaceContainerLowest: isDark ? const Color(0xFF120D0B) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF231B17) : const Color(0xFFFFFCF8),
      surfaceContainer: isDark ? const Color(0xFF2B221D) : const Color(0xFFF8EDE3),
      surfaceContainerHigh: isDark ? const Color(0xFF342923) : const Color(0xFFF2E3D6),
      surfaceContainerHighest: isDark ? const Color(0xFF3D312A) : const Color(0xFFEBD8C8),
      outlineVariant: isDark ? const Color(0xFF4A3B32) : const Color(0xFFEADBCD),
    );

    // Manrope donne son identité visuelle à l'application, mais ne contient
    // pas les caractères ɔ et ɛ du Dioula, du Bambara et du Mooré : sans
    // secours, une traduction s'affiche avec des carrés à la place des
    // lettres. `fontFamilyFallback` ne change rien à l'apparence du texte
    // latin ordinaire — il n'intervient que sur les caractères que la police
    // principale ne sait pas dessiner, et la police de secours est embarquée
    // (voir pubspec.yaml), donc utilisable sans connexion.
    final textTheme = GoogleFonts.manropeTextTheme(isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme)
        .apply(
          fontFamilyFallback: const ['NotoSansFallback'],
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );

    final radius = BorderRadius.circular(AppRadius.md);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      scaffoldBackgroundColor: colorScheme.surface,
      // Cibles tactiles d'au moins 48 dp partout (doigts, écrans abîmés).
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: colorScheme.outline),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: colorScheme.outlineVariant),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        side: BorderSide.none,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: colorScheme.primary,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Espacements standardisés — évite les valeurs magiques (`SizedBox(height: 13)`)
/// éparpillées dans les écrans, pour un rythme visuel cohérent partout.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

/// Rayons d'arrondi, même logique que [AppSpacing].
abstract final class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Largeurs de référence. L'app est conçue pour un téléphone mais tourne
/// aussi dans un navigateur : au-delà de [wide], la navigation passe du bas
/// de l'écran à une barre latérale, et le contenu se limite à une largeur
/// lisible (60-80 caractères par ligne pour un formulaire).
abstract final class AppBreakpoints {
  static const wide = 840.0;
  static const formMaxWidth = 760.0;
  static const pageMaxWidth = 1120.0;
}
