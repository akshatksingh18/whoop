// One basename policy for Body publication, import and media recovery.
// Preserve safe legacy IDs (including underscores, spaces and Unicode).
bool isBodyPhotoFileName(String name) {
  if (!name.endsWith('.jpg') || name.length > 240) return false;
  final id = name.substring(0, name.length - 4);
  if (id.isEmpty ||
      id == '.' ||
      id == '..' ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(id))
    return false;
  return !RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(id);
}

String bodyPhotoFileName(String id) {
  final name = '$id.jpg';
  if (!isBodyPhotoFileName(name)) {
    throw const FormatException('This photo has an unsupported file name.');
  }
  return name;
}
