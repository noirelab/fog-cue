import 'package:flutter/material.dart';

import 'theme.dart';

class ChartSeries {
  const ChartSeries(this.label, this.color, this.values);
  final String label;
  final Color color;
  final List<double> values;
}

/// Desenhar mais pontos que isso não muda nada visível em tela de celular.
const _maxPoints = 120;

List<double> _downsample(List<double> v) {
  if (v.length <= _maxPoints) return v;
  final step = v.length / _maxPoints;
  return [for (var i = 0; i < _maxPoints; i++) v[(i * step).floor()]];
}

/// Gráfico de linhas mínimo (CustomPainter). Escala Y automática pelos dados
/// visíveis; valores NaN são ignorados.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.series, required this.unit, this.height = 120, this.minRange = 1});

  final List<ChartSeries> series;
  final String unit;
  final double height;

  /// Faixa vertical mínima, para não ampliar ruído de sensor parado até
  /// parecer sinal.
  final double minRange;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sampled = [for (final s in series) ChartSeries(s.label, s.color, _downsample(s.values))];
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final s in sampled) {
      for (final v in s.values) {
        if (!v.isFinite) continue;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    final hasData = lo.isFinite;
    if (hasData && hi - lo < minRange) {
      final mid = (hi + lo) / 2;
      lo = mid - minRange / 2;
      hi = mid + minRange / 2;
    }
    final muted = TextStyle(color: p.textMuted, fontSize: 12, fontFeatures: tabular);

    final range = hasData ? '${lo.toStringAsFixed(2)} a ${hi.toStringAsFixed(2)} $unit' : 'sem dados';

    // O leitor de tela não enxerga o CustomPaint: resume o gráfico em texto.
    return Semantics(
      label: 'Gráfico de ${series.map((s) => s.label).join(', ')}, faixa $range',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: CustomPaint(painter: _ChartPainter(sampled, hasData ? lo : 0, hasData ? hi : 1, p.grid)),
          ),
          const SizedBox(height: 8),
          // Wrap em vez de Row: com fonte grande a legenda quebra de linha.
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 3,
                      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 6),
                    Text(s.label, style: muted),
                  ],
                ),
              Text(range, style: muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.series, this.lo, this.hi, this.gridColor);

  final List<ChartSeries> series;
  final double lo;
  final double hi;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final f in const [0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), grid);
    }
    const pad = 6.0;
    double y(double v) => pad + (1 - (v - lo) / (hi - lo)) * (size.height - 2 * pad);

    for (final s in series) {
      final n = s.values.length;
      if (n < 2) continue;
      final path = Path();
      var penDown = false;
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (!v.isFinite) {
          penDown = false;
          continue;
        }
        final point = Offset(i / (n - 1) * size.width, y(v));
        penDown ? path.lineTo(point.dx, point.dy) : path.moveTo(point.dx, point.dy);
        penDown = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..strokeWidth = 1.75
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
