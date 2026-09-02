import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';

// Clase para construir los widgets de las etiquetas ambientales de los vehiculos

class EnvStickerBadge extends StatelessWidget {
  final EnvSticker? sticker;
  final double size;
  final bool showEmpty;

  const EnvStickerBadge({super.key, required this.sticker, this.size = 28, this.showEmpty = false});

  @override
  Widget build(BuildContext context) {
    final config = _stickerConfig(sticker);

    if (config == null) {
      if (!showEmpty) return const SizedBox.shrink();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE0E0E0),
          border: Border.all(color: const Color(0xFFBDBDBD), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          "—",
          style: TextStyle(
            color: const Color(0xFF9E9E9E),
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      );
    }

    // El borde se pinta como un circulo exterior para poder partirlo en dos colores igual que el fondo (caso de la etiqueta ECO)
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _halves(config.border, config.borderSecondary),
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _halves(config.background, config.backgroundSecondary),
        ),
        alignment: Alignment.center,
        child: Text(
          config.label,
          style: TextStyle(
            color: config.text,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// Divide el circulo en mitad izquierda y mitad derecha, si no hay segundo color, el degradado queda plano
LinearGradient _halves(Color first, Color? second) {
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [first, second ?? first],
    stops: const [0.5, 0.5],
  );
}

class _StickerConfig {
  final String label;
  final Color background;
  final Color border;
  final Color text;
  // Colores de la mitad derecha, solo para las etiquetas de dos tonos
  final Color? backgroundSecondary;
  final Color? borderSecondary;

  const _StickerConfig({
    required this.label,
    required this.background,
    required this.border,
    required this.text,
    this.backgroundSecondary,
    this.borderSecondary,
  });
}

_StickerConfig? _stickerConfig(EnvSticker? sticker) {
  switch (sticker) {
    case EnvSticker.cero:
      return const _StickerConfig(
        label: "0",
        background: Color(0xFF1565C0),
        border: Color(0xFF0D47A1),
        text: Colors.white,
      );
    case EnvSticker.eco:
      return const _StickerConfig(
        label: "ECO",
        background: Color(0xFF1565C0),
        backgroundSecondary: Color(0xFF43A047),
        border: Color(0xFF0D47A1),
        borderSecondary: Color(0xFF2E7D32),
        text: Colors.white,
      );
    case EnvSticker.b:
      return const _StickerConfig(
        label: "B",
        background: Color(0xFFFFD600),
        border: Color(0xFFF9A825),
        text: Color(0xFF1A1A1A),
      );
    case EnvSticker.c:
      return const _StickerConfig(
        label: "C",
        background: Color(0xFF43A047),
        border: Color(0xFF2E7D32),
        text: Colors.white,
      );
    case EnvSticker.hist:
      return const _StickerConfig(
        label: "H",
        background: Color(0xFF795548),
        border: Color(0xFF4E342E),
        text: Colors.white,
      );
    case EnvSticker.all:
    case null:
      return null;
  }
}
