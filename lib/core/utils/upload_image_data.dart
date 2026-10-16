import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

class UploadImageData {
  const UploadImageData(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

Future<UploadImageData> readUploadImage(XFile image) async {
  if (await image.length() > 5 * 1024 * 1024) throw Exception('圖片大小不可超過 5MB');
  final bytes = await image.readAsBytes();
  String? mime;
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    mime = 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].asMap().entries.every((e) => bytes[e.key] == e.value)) {
    mime = 'image/png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    mime = 'image/webp';
  }
  if (mime == null) throw Exception('僅支援 JPG、PNG、WebP 圖片');
  return UploadImageData(bytes, mime);
}
