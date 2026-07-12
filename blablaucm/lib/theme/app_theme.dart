import 'package:flutter/material.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Clase para manejar el tema de la aplicacion

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppColors.light);
  static ThemeData get dark => _build(AppColors.dark);

  static ThemeData _build(AppColors c) {
    final base = ThemeData(brightness: c.brightness, useMaterial3: true);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: c.brightness,
    ).copyWith(
      primary: AppColors.primary,
      error: c.danger,
      surface: c.card,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      cardColor: c.card,
      dividerColor: c.border,
      iconTheme: IconThemeData(color: c.textSecondary),
      primaryColor: AppColors.primary,

      appBarTheme: AppBarTheme(
        backgroundColor: c.card,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: c.textSecondary),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      textTheme: base.textTheme.apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceLow,
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: c.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.danger),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      cardTheme: CardThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? const Color(0xFF334155) : const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color bgColor(BuildContext context) => AppColors.of(context).background;
  static Color cardColor(BuildContext context) => AppColors.of(context).card;
  static Color surfaceLow(BuildContext context) => AppColors.of(context).surfaceLow;
  static Color borderColor(BuildContext context) => AppColors.of(context).border;
  static Color textColor(BuildContext context) => AppColors.of(context).textPrimary;
  static Color textMuted(BuildContext context) => AppColors.of(context).textSecondary;
  static Color errorColor(BuildContext context) => AppColors.of(context).danger;

  static const Color primaryColor = AppColors.primary;
  static const Color successColor = AppColors.success;
  static const Color warningColor = AppColors.warning;

  static Widget buildCard(BuildContext context, {required Widget child, EdgeInsetsGeometry? padding}) {
    final c = AppColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 1),
        boxShadow: c.isDark
            ? []
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
  }

  // Widget para crear un InputDecoration personalizado
  static InputDecoration customInputDecoration(BuildContext context, String label, {bool hasError = false, String? errorText, IconData? prefixIcon, Color? iconColor}) {
    final c = AppColors.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: c.surfaceLow,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: iconColor ?? AppColors.primary) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.danger)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      errorText: hasError ? errorText : null,
    );
  }

  // Widget para crear un footer fijo
  static Widget buildStickyFooter(BuildContext context, {required List<Widget> children}) {
    final c = AppColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: c.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, -4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // Widget para crear un boton primario
  static Widget buildPrimaryButton({required VoidCallback? onPressed, required String text, bool isLoading = false, Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
