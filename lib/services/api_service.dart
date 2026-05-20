import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class ApiService {
  Stream<String> generateChatStream(
    List<Message> history,
    String apiKey,
    String baseUrl,
    String model,
  ) async* {
    final url = Uri.parse('$baseUrl/chat/completions');
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
        throw Exception('API 错误码 ${response.statusCode}: ${utf8.decode(errorBytes)}');
      }
      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in stream) {
        if (line.trim().isEmpty) continue;
        if (line.startsWith('data: [DONE]')) break;
        if (line.startsWith('data:')) {
          final dataJson = line.substring(5).trim();
          try {
            final parsed = jsonDecode(dataJson);
            final deltaContent = parsed['choices']?[0]?['delta']?['content'] ?? '';
            if (deltaContent.isNotEmpty) yield deltaContent;
          } catch (e) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Future<String> generateImage(String prompt, String apiKey, String baseUrl, String model) async {
    final url = Uri.parse('$baseUrl/images/generations');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
      body: jsonEncode({'model': model, 'prompt': prompt, 'n': 1, 'size': '1024x1024'}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['data'][0]['url'];
    }
    throw Exception('生图失败: ${utf8.decode(response.bodyBytes)}');
  }
}
