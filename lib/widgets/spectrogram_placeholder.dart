import 'package:flutter/material.dart';

/// A static, illustrative spectrum visualisation drawn via [CustomPaint].
///
/// No real DSP is performed — this is a UI placeholder whose shape is
/// deterministically derived from fixed data so that it looks plausible
/// but never changes. Random() and DateTime are intentionally avoided.
class SpectrogramPlaceholder extends StatelessWidget {
  const SpectrogramPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: CustomPaint(
        painter: _SpectrumPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

/// Fixed normalised bar heights (0.0–1.0) — 64 bins representing a
/// stylised frequency spectrum. Values were hand-crafted to look like a
/// realistic lossless spectrum (full-range energy, gradual high-end roll-off).
const _kBins = <double>[
  0.55, 0.60, 0.72, 0.80, 0.88, 0.92, 0.95, 0.97,
  0.98, 0.99, 1.00, 0.98, 0.96, 0.93, 0.90, 0.88,
  0.85, 0.83, 0.80, 0.78, 0.76, 0.74, 0.72, 0.70,
  0.69, 0.68, 0.67, 0.66, 0.65, 0.64, 0.63, 0.62,
  0.60, 0.59, 0.57, 0.56, 0.55, 0.53, 0.52, 0.50,
  0.49, 0.47, 0.46, 0.44, 0.43, 0.41, 0.40, 0.38,
  0.36, 0.34, 0.32, 0.30, 0.28, 0.26, 0.24, 0.22,
  0.19, 0.17, 0.14, 0.12, 0.10, 0.08, 0.06, 0.04,
];

class _SpectrumPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const bgColor = Color(0xFF0A0C0D);
    const accentBase = Color(0xFF1DB954); // emerald green

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    final count = _kBins.length;
    final barWidth = (size.width / count) * 0.72;
    final gap = (size.width / count) * 0.28;

    for (var i = 0; i < count; i++) {
      final normalised = _kBins[i];
      final barHeight = size.height * normalised * 0.90;

      // Gradient: accent green at top, darker teal at bottom
      final left = i * (barWidth + gap);
      final top = size.height - barHeight;
      final rect = Rect.fromLTWH(left, top, barWidth, barHeight);

      // Fade green → teal toward base
      final fraction = i / (count - 1);
      final alpha = (200 + (55 * (1 - fraction))).toInt().clamp(0, 255);
      final barPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentBase.withAlpha(alpha),
            const Color(0xFF0D3D22).withAlpha((alpha * 0.5).toInt()),
          ],
        ).createShader(rect);

      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rr, barPaint);
    }

    // Frequency axis line at the bottom
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = const Color(0xFF1F4D36)
        ..strokeWidth = 1,
    );

    // "20 Hz" and "20 kHz" tick labels
    _drawAxisLabel(canvas, '20 Hz', const Offset(4, 0), size);
    _drawAxisLabel(
      canvas,
      '20 kHz',
      Offset(size.width - 52, 0),
      size,
      rightAlign: true,
    );
  }

  void _drawAxisLabel(
    Canvas canvas,
    String label,
    Offset position,
    Size size, {
    bool rightAlign = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF565C65),
          fontSize: 9,
          fontFamily: 'monospace',
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final dx = rightAlign ? size.width - tp.width - 4 : position.dx;
    tp.paint(canvas, Offset(dx, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

