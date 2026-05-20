import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/message.dart';

class ApiService {
  String _normalizeBaseUrl(String baseUrl) {
    var value = baseUrl.trim();
    if (value.isEmpty) value = 'https://api.openai.com/v1';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Uri _endpoint(String baseUrl, String path) {
    return Uri.parse('${_normalizeBaseUrl(baseUrl)}$path');
  }

  String normalizeChatModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'gpt-4o-mini';
    // 常见误填：gpt-40 是数字 0，不是字母 o；OpenAI 通常是 gpt-4o。
    if (value.toLowerCase() == 'gpt-40') return 'gpt-4o';
    return value;
  }

  /// OpenAI 通用 /images/generations 需要图片模型，不能使用聊天模型。
  String normalizeImageModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'dall-e-3';

    final lower = value.toLowerCase();
    final isKnownImageModel = lower.startsWith('dall-e') || lower.contains('image');
    final isKnownChatModel = lower == 'gpt-40' ||
        lower == 'gpt-4o' ||
        lower == 'gpt-4o-mini' ||
        lower.startsWith('gpt-4') ||
        lower.startsWith('gpt-3.5') ||
        lower.startsWith('claude') ||
        lower.startsWith('gemini') ||
        lower.startsWith('deepseek') ||
        lower.startsWith('qwen') ||
        lower.startsWith('glm');

    if (isKnownChatModel && !isKnownImageModel) {
      return 'dall-e-3';
    }
    return value;
  }

  String _extractOpenAiError(String body) {
    try {
      final parsed = jsonDecode(body);
      final error = parsed['error'];
      if (error is Map) {
        final message = error['message']?.toString();
        final code = error['code']?.toString();
        if (message != null && message.isNotEmpty) {
          return code == null || code.isEmpty ? message : '$message ($code)';
        }
      }
    } catch (_) {}
    return body;
  }

  String _friendlyImageError(String rawError, String requestedModel, String actualModel) {
    final shortError = _extractOpenAiError(rawError);
    final lower = shortError.toLowerCase();
    if (lower.contains('model not found') || lower.contains('no available channel')) {
      return '生图模型不可用。当前实际请求的生图模型是：$actualModel。'
          'gpt-40 / gpt-4o / gpt-4o-mini 是聊天模型，不能用于 OpenAI 通用 /images/generations 生图接口。'
          '请把“生图模型”填写为 dall-e-3、dall-e-2、gpt-image-1，或服务商支持的图片模型。'
          '原始错误：$shortError';
    }
    if (requestedModel.trim() != actualModel) {
      return '检测到生图模型配置不适合画图，已从“$requestedModel”自动改用“$actualModel”，但接口仍返回错误：$shortError';
    }
    return shortError;
  }

  /// OpenAI 通用聊天接口：POST /chat/completions
  /// 请求体格式：{ model, messages, stream }
  Stream<String> generateChatStream(
    List<Message> history,
    String apiKey,
    String baseUrl,
    String model,
  ) async* {
    final url = _endpoint(baseUrl, '/chat/completions');
    final formattedMessages = history.map((msg) => msg.toOpenAiMap()).toList();

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream, application/json'
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..body = jsonEncode({
        'model': normalizeChatModel(model),
        'messages': formattedMessages,
        'stream': true,
      });

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBytes = await response.stream.toBytes();
        final errorMsg = utf8.decode(errorBytes);
        throw Exception('API 错误码 ${response.statusCode}: ${_extractOpenAiError(errorMsg)}');
      }

      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());
      final jsonBuffer = StringBuffer();

      await for (final line in stream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed == 'data: [DONE]' || trimmed == '[DONE]') break;

        if (trimmed.startsWith('data:')) {
          final dataJson = trimmed.substring(5).trim();
          if (dataJson == '[DONE]') break;
          try {
            final parsed = jsonDecode(dataJson);
            final deltaContent = parsed['choices']?[0]?['delta']?['content'] ?? '';
            if (deltaContent.toString().isNotEmpty) {
              yield deltaContent.toString();
            }
          } catch (_) {
            // 忽略无法解析的 SSE 行。
          }
        } else {
          jsonBuffer.writeln(trimmed);
        }
      }

      // 兼容非流式 JSON 返回：{ choices: [{ message: { content } }] }
      final buffered = jsonBuffer.toString().trim();
      if (buffered.isNotEmpty) {
        try {
          final parsed = jsonDecode(buffered);
          final content = parsed['choices']?[0]?['message']?['content'] ?? '';
          if (content.toString().isNotEmpty) {
            yield content.toString();
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  /// OpenAI 通用生图接口：POST /images/generations
  /// 请求体格式：{ model, prompt, n, size }
  /// 兼容返回：data[0].url 或 data[0].b64_json。
  Future<String> generateImage(
    String prompt,
    String apiKey,
    String baseUrl,
    String model, {
    String size = '1024x1024',
  }) async {
    final url = _endpoint(baseUrl, '/images/generations');
    final imageModel = normalizeImageModel(model);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: jsonEncode({
        'model': imageModel,
        'prompt': prompt,
        'n': 1,
        'size': size,
      }),
    );

    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_friendlyImageError(bodyText, model, imageModel));
    }

    final data = jsonDecode(bodyText);
    final first = data['data']?[0];
    final imageUrl = first?['url'];
    if (imageUrl != null && imageUrl.toString().isNotEmpty) {
      return imageUrl.toString();
    }

    final b64 = first?['b64_json'];
    if (b64 != null && b64.toString().isNotEmpty) {
      return 'data:image/png;base64,${b64.toString()}';
    }

    throw Exception('OpenAI 生图接口未返回 data[0].url 或 data[0].b64_json');
  }
}
