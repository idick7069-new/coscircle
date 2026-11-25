import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../api/api_client.dart';

bool isProtectedMedia(String value) {
  final uri = Uri.tryParse(value);
  return uri?.scheme == 'https' &&
      uri?.host == 'coscircle.app' &&
      uri!.path.startsWith('/uploads/');
}

class SecureMediaImage extends ImageProvider<SecureMediaImage> {
  SecureMediaImage(this.url)
    : sessionVersion = ApiClient.mediaClient?.sessionVersion ?? 0;
  final String url;
  final int sessionVersion;

  @override
  Future<SecureMediaImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    SecureMediaImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    var uri = Uri.parse(url);
    final client = ApiClient.mediaClient;
    final expires = int.tryParse(uri.queryParameters['e'] ?? '') ?? 0;
    if (expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30) {
      if (client == null) throw StateError('圖片連線尚未準備完成');
      final response = await client.post('/media/sign', data: {'url': url});
      if (client.sessionVersion != sessionVersion) throw StateError('登入狀態已變更');
      uri = Uri.parse((response.data as Map)['url'] as String);
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final response = await dio.get<List<int>>(
        uri.toString(),
        options: Options(responseType: ResponseType.bytes),
      );
      if (client != null && client.sessionVersion != sessionVersion) {
        throw StateError('登入狀態已變更');
      }
      return decode(
        await ui.ImmutableBuffer.fromUint8List(
          Uint8List.fromList(response.data!),
        ),
      );
    } finally {
      dio.close();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SecureMediaImage &&
      other.url == url &&
      other.sessionVersion == sessionVersion;
  @override
  int get hashCode => Object.hash(url, sessionVersion);
}
