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

    // 转换消息历史为 OpenAI 标准格式（包括多模态格式）
    final formattedMessages = history.map((msg) => msg.toOpenAiMap()).toList();

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..body = jsonEncode({
        'model': model.trim().isEmpty ? 'gpt-4o-mini' : model.trim(),
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

      // 逐行解析 SSE (Server-Sent Events) 流
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
            // 忽略格式错误的行
          }
        }
      }
    } finally {
      client.close();
    }
  }

  /// 避免用户把聊天模型误填到生图模型。
  ///
  /// 你的报错里出现了 `model gpt-40 not found`，说明当前“生图模型”被配置成了聊天模型。
  /// OpenAI 格式的 /images/generations 通常应使用 dall-e-3、dall-e-2 或兼容服务提供的图片模型。
  String _normalizeImageModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'dall-e-3';

    final lower = value.toLowerCase();
    final isChatModel = lower == 'gpt-40' ||
        lower == 'gpt-4o' ||
        lower == 'gpt-4o-mini' ||
        lower.startsWith('gpt-4') ||
        lower.startsWith('gpt-3.5');

    // gpt-image-1 这类是真生图模型，不能误拦截。
    final isImageModel = lower.contains('image') || lower.startsWith('dall-e');

    if (isChatModel && !isImageModel) {
      return 'dall-e-3';
    }
    return value;
  }

  String _friendlyImageError(String rawError, String requestedModel, String actualModel) {
    final lower = rawError.toLowerCase();
    if (lower.contains('model not found') || lower.contains('no available channel')) {
      return '生图模型不可用。当前请求模型: $actualModel。'
          '如果你在设置里填了 gpt-40 / gpt-4o / gpt-4o-mini，这些是聊天模型，不能用于 /images/generations 生图。'
          '请把“生图模型”改成 dall-e-3、dall-e-2、gpt-image-1，或你的 API 服务商支持的图片模型。'
          '原始错误: $rawError';
    }
    if (requestedModel.trim() != actualModel) {
      return '已检测到生图模型配置可能不正确，已从 `$requestedModel` 自动改用 `$actualModel`，但接口仍返回错误: $rawError';
    }
    return rawError;
  }

  /// OpenAI 格式生图接口 (支持模型选择)
  Future<String> generateImage(
    String prompt,
    String apiKey,
    String baseUrl,
    String model, {
    String size = '1024x1024',
  }) async {
    final url = Uri.parse('$baseUrl/images/generations');
    final imageModel = _normalizeImageModel(model);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': imageModel,
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
      throw Exception(_friendlyImageError(errorMsg, model, imageModel));
    }
  }
}
