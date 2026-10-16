String? extractAppQrCode(String? value, String route, {int minimumLength = 4}) {
  final text = value?.trim() ?? '';
  final pattern = RegExp('^[a-zA-Z0-9_-]{$minimumLength,80}\$');
  if (pattern.hasMatch(text)) return text;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == 'coscircle' && uri.host == route) {
    final code = uri.pathSegments.firstOrNull;
    return code != null && pattern.hasMatch(code) ? code : null;
  }
  final target = uri.fragment.startsWith('/')
      ? Uri.tryParse(uri.fragment)
      : uri;
  final segments = target?.pathSegments ?? const <String>[];
  final index = segments.indexOf(route);
  if (index < 0 || index + 1 >= segments.length) return null;
  final code = segments[index + 1];
  return pattern.hasMatch(code) ? code : null;
}
