import 'dart:convert';
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ImageSaveService {
  static Future<void> _ensureAccess() async {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final request = await Gal.requestAccess();
      if (!request) {
        throw Exception('未获得保存图片到相册的权限，请在设置中开启');
      }
    }
  }

  static String _extensionFromMime(String mime) {
    final value = mime.toLowerCase();
    if (value.contains('jpeg') || value.contains('jpg')) return 'jpg';
    if (value.contains('webp')) return 'webp';
    if (value.contains('gif')) return 'gif';
    return 'png';
  }

  static String _extensionFromUrl(String imageUrl) {
    final path = Uri.tryParse(imageUrl)?.path.toLowerCase() ?? '';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'jpg';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'png';
  }

  static Future<void> _saveBytes(List<int> bytes, {String extension = 'png'}) async {
    await _ensureAccess();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes);
    try {
      await Gal.putImage(file.path);
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// 下载网络图片并保存到系统相册。
  static Future<void> saveNetworkImage(String imageUrl) async {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      throw Exception('图片下载失败，状态码: ${response.statusCode}');
    }
    await _saveBytes(response.bodyBytes, extension: _extensionFromUrl(imageUrl));
  }

  /// 保存 data:image/...;base64,... 图片到系统相册。
  static Future<void> saveDataImage(String dataUrl) async {
    final comma = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image') || comma < 0) {
      throw Exception('不是有效的 base64 图片数据');
    }

    final header = dataUrl.substring(0, comma).toLowerCase();
    final payload = dataUrl.substring(comma + 1).replaceAll(RegExp(r'\s+'), '');
    final mime = RegExp(r'data:([^;]+)').firstMatch(header)?.group(1) ?? 'image/png';
    final bytes = base64Decode(payload);
    await _saveBytes(bytes, extension: _extensionFromMime(mime));
  }

  /// 自动识别网络 URL 或 data:image base64，并保存到系统相册。
  static Future<void> saveImage(String image) async {
    if (image.startsWith('data:image') && image.contains('base64,')) {
      await saveDataImage(image);
    } else {
      await saveNetworkImage(image);
    }
  }
}
