import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class ApiService {
  /// 聊天接口（支持 Stream 流式响应 + 多模态图片解析）
  Stream<String> generateChatStream(
    List<Message> history,
    String apiKey,
    String baseUrl,
    String model,
  ) async* {
    final url = Uri.parse('$baseUrl/chat/completions');
    
    // 转换消息历史为 OpenAI 标准格式
    final formattedMessages = history.map((msg) => msg.toOpenAiMap()).toList();

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..body = jsonEncode({
        'model': model,
        'messages': formattedMessages,
        'stream': true,
      });

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBytes = await response.stream.toBytes();
        final errorMsg = utf8.decode(errorBytes);
        throw Exception('API 错误码 ${response.statusCode}: $errorMsg');
      }

      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());
      
      await for (final line in stream) {
        if (line.trim().isEmpty) continue;
        if (line.startsWith('data: [DONE]')) {
          break;
        }
        if (line.startsWith('data:')) {
          final dataJson = line.substring(5).trim();
          try {
            final parsed = jsonDecode(dataJson);
            final deltaContent = parsed['choices']?[0]?['delta']?['content'] ?? '';
            if (deltaContent.isNotEmpty) {
              yield deltaContent;
            }
          } catch (e) {
          }
        }
      }
    } finally {
      client.close();
    }
  }

  /// OpenAI 格式生图接口
  Future<String> generateImage(String prompt, String apiKey, String baseUrl, String model, {String size = '1024x1024'}) async {
    final url = Uri.parse('$baseUrl/images/generations');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'prompt': prompt,
        'n': 1,
        'size': size,
        'response_format': 'url',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final imageUrl = data['data']?[0]?['url'];
      if (imageUrl != null) {
        return imageUrl;
      }
      throw Exception('未返回图片 URL');
    } else {
      final errorMsg = utf8.decode(response.bodyBytes);
      throw Exception('生图 API 错误: $errorMsg');
    }
  }
}
