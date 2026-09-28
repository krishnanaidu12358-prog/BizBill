import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// A named palette the user can pick. Each one is a seed colour that Material 3
/// expands into a full light and dark scheme, so every theme works in both modes.
class AppPalette {
  const AppPalette({
    required this.key,
    required this.label,
    required this.seed,
    required this.blurb,
  });

  final String key;
  final String label;
  final Color seed;
  final String blurb;
}

const appPalettes = <AppPalette>[
  AppPalette(
    key: 'BizBill',
    label: 'BizBill Blue',
    seed: Color(0xFF064C9C),
    blurb: 'The BizBill brand colours',
  ),
  AppPalette(
    key: 'Classic',
    label: 'Classic Green',
    seed: Color(0xFF1B6B4A),
    blurb: 'Fresh green',
  ),
  AppPalette(
    key: 'Indigo',
    label: 'Royal Indigo',
    seed: Color(0xFF3949AB),
    blurb: 'Calm and corporate',
  ),
  AppPalette(
    key: 'Maroon',
    label: 'Deep Maroon',
    seed: Color(0xFF8E1B3A),
    blurb: 'Warm and traditional',
  ),
  AppPalette(
    key: 'Teal',
    label: 'Ocean Teal',
    seed: Color(0xFF00695C),
    blurb: 'Fresh and clean',
  ),
  AppPalette(
    key: 'Saffron',
    label: 'Saffron Gold',
    seed: Color(0xFFC77700),
    blurb: 'Bright and festive',
  ),
  AppPalette(
    key: 'Slate',
    label: 'Midnight Slate',
    seed: Color(0xFF37474F),
    blurb: 'Quiet and neutral',
  ),
];

AppPalette paletteFor(String key) =>
    appPalettes.firstWhere((p) => p.key == key, orElse: () => appPalettes.first);

/// Kept for code that still refers to the original single seed colour.
const seed = Color(0xFF1B6B4A);

ThemeData buildTheme(Brightness brightness, {String paletteKey = 'Classic'}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: paletteFor(paletteKey).seed,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.03), const Color(0xFFF6F7F9))
        : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      color: scheme.surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    // Native feel per platform: iOS slides with the swipe-back gesture,
    // Android uses its own predictive-back / zoom transition.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      elevation: 3,
      shadowColor: Colors.black26,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          )),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ),
  );
}

/// Semantic colours that must stay readable in both light and dark schemes.
Color moneyPositive(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6ADB8F)
        : const Color(0xFF1B7F3B);

Color moneyNegative(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF8A80)
        : const Color(0xFFB3261E);

Color moneyWarning(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFC46B)
        : const Color(0xFFB26A00);

/// Status pill colours shared by bills, credits and claims.
Color statusColor(String status, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  switch (status) {
    case 'Paid':
    case 'Approved':
    case 'Claimed':
    case 'Sent':
    case 'Active':
    case 'Good':
      return dark ? const Color(0xFF6ADB8F) : const Color(0xFF1B7F3B);
    case 'PartiallyPaid':
    case 'PartiallyClaimed':
    case 'Pending':
    case 'Queued':
    case 'Watch':
      return dark ? const Color(0xFFFFC46B) : const Color(0xFFB26A00);
    case 'Credit':
    case 'Overdue':
      return dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);
    case 'Cancelled':
    case 'Rejected':
    case 'Expired':
    case 'Failed':
    case 'None':
      return scheme.outline;
    default:
      return scheme.primary;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'PartiallyPaid':
      return 'Part paid';
    case 'PartiallyClaimed':
      return 'Part claimed';
    case 'Credit':
      return 'Udhaar';
    default:
      return status;
  }
}
