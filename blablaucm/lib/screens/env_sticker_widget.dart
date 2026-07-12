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

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: config.background,
        border: Border.all(color: config.border, width: 1.5),
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
    );
  }
}

class _StickerConfig {
  final String label;
  final Color background;
  final Color border;
  final Color text;

  const _StickerConfig({
    required this.label,
    required this.background,
    required this.border,
    required this.text,
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
        background: Color(0xFF00897B),
        border: Color(0xFF00695C),
        text: Colors.white,
      );
    case EnvSticker.c:
      return const _StickerConfig(
        label: "C",
        background: Color(0xFFFFD600),
        border: Color(0xFFF9A825),
        text: Color(0xFF1A1A1A),
      );
    case EnvSticker.b:
      return const _StickerConfig(
        label: "B",
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
