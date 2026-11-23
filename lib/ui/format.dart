/// Formatação de valores para a interface. "-" indica valor ausente.
library;

String fmt(double? value, [int digits = 2, String unit = '']) {
  if (value == null || !value.isFinite) return '-';
  return unit.isEmpty ? value.toStringAsFixed(digits) : '${value.toStringAsFixed(digits)} $unit';
}

String formatDuration(double ms) {
  final total = (ms / 1000).floor().clamp(0, 1 << 31);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String formatDateTime(double ms) {
  final d = DateTime.fromMicrosecondsSinceEpoch((ms * 1000).round());
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
