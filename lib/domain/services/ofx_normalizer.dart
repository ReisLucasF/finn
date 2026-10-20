const _from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _to = 'aaaaaeeeeiiiiooooouuuucn';

String normalizeDescription(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = _from.indexOf(char);
    buffer.write(index >= 0 ? _to[index] : char);
  }
  final cleaned = buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

bool descriptionsAreSimilar(String left, String right) {
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  return left.contains(right) || right.contains(left);
}
