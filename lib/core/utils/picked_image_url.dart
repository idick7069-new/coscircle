/// Keeps existing uploads usable after the move from the VM IP to HTTPS.
String pickedImageUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      !['34.187.168.222', 'coscircle.app'].contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      !uri.path.startsWith('/uploads/') ||
      (uri.hasPort && uri.port != 80 && uri.port != 443)) {
    return value;
  }
  return uri
      .replace(scheme: 'https', host: 'coscircle.app', port: 443)
      .toString();
}
