import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

class ImageSaveService {
  static Future<void> saveNetworkImage(String imageUrl) async {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) await Gal.requestAccess();
    
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) throw Exception('下载失败');

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(response.bodyBytes);

    await Gal.putImage(file.path);
    if (await file.exists()) await file.delete();
  }
}
