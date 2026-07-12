import 'package:flutter/material.dart';

// Clase para manejar los colores de la aplicacion

class AppColors {

  static const Color primary = Color(0xFF4F46E5); 
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color success = Color(0xFF10B981); 
  static const Color successDark = Color(0xFF059669);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  static const Color successSurface = Color(0xFFECFDF5); 
  static const Color successBorder = Color(0xFFD1FAE5); 
  static const Color successText = Color(0xFF059669); 
  static const Color dangerSurface = Color(0xFFFEF2F2); 
  static const Color dangerBorder = Color(0xFFFEE2E2); 

  final Brightness brightness;
  final Color background; 
  final Color card; 
  final Color surfaceLow;
  final Color border;
  final Color textPrimary; 
  final Color textSecondary;
  final Color textTertiary; 
  final Color danger; 

  const AppColors._({
    required this.brightness,
    required this.background,
    required this.card,
    required this.surfaceLow,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.danger,
  });

  bool get isDark => brightness == Brightness.dark;

  // Paleta del tema claro
  static const AppColors light = AppColors._(
    brightness: Brightness.light,
    background: Color(0xFFF3F4F6),
    card: Colors.white,
    surfaceLow: Color(0xFFF9FAFB),
    border: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textTertiary: Color(0xFF9CA3AF),
    danger: Color(0xFFEF4444),
  );

  // Paleta del tema oscuro
  static const AppColors dark = AppColors._(
    brightness: Brightness.dark,
    background: Color(0xFF0F172A),
    card: Color(0xFF1E293B),
    surfaceLow: Color(0xFF334155),
    border: Color(0xFF475569),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF94A3B8),
    danger: Color(0xFFF87171),
  );

  // Devuelve la paleta correcta segun el brillo del tema actual.
  static AppColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}
