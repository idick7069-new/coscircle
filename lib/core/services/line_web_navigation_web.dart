// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

String? pendingLineWebResult() =>
    Uri.tryParse(Uri.base.fragment)?.queryParameters['line'];
void clearLineWebResult() {
  final route = Uri.tryParse(Uri.base.fragment);
  if (route == null) return;
  final query = Map<String, String>.of(route.queryParameters)..remove('line');
  final clean = Uri.base.replace(
    fragment: route
        .replace(queryParameters: query.isEmpty ? null : query)
        .toString(),
  );
  html.window.history.replaceState(null, '', clean.toString());
}

void redirectToLine(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' ||
      uri.host != 'access.line.me' ||
      uri.userInfo.isNotEmpty) {
    throw StateError('LINE 授權網址無效');
  }
  html.window.location.assign(value);
}
