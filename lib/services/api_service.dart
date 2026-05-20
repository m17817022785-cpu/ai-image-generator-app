import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/message.dart';
import 'debug_log_service.dart';

enum ToolAction { directAnswer, textToImage, imageToImage }

class ToolDecision {
  final ToolAction action;
  final String prompt;
  final String reply;
  final String size;

  const ToolDecision({
    required this.action,
    required this.prompt,
    required this.reply,
    required this.size,
  });

  bool get shouldCallImageTool => action == ToolAction.textToImage || action == ToolAction.imageToImage;
}

class ApiService {
  final DebugLogService _log = DebugLogService.instance;

  String _normalizeBaseUrl(String baseUrl) {
    var value = baseUrl.trim();
    if (value.isEmpty) value = 'https://api.openai.com/v1';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  bool _pathEndsWithAny(String baseUrl, List<String> suffixes) {
    final normalized = _normalizeBaseUrl(baseUrl);
    final uri = Uri.tryParse(normalized);
    final path = (uri?.path ?? '').toLowerCase();
    return suffixes.any((suffix) => path == suffix || path.endsWith(suffix));
  }

  bool _isFullChatEndpoint(String baseUrl) {
    return _pathEndsWithAny(baseUrl, ['/chat', '/chat/completions', '/completions']);
  }

  bool _isFullImageGenerationEndpoint(String baseUrl) {
    return _pathEndsWithAny(baseUrl, ['/images/generations']);
  }

  bool _isFullImageEditEndpoint(String baseUrl) {
    return _pathEndsWithAny(baseUrl, ['/images/edits']);
  }

  Uri _endpoint(String baseUrl, String path) {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (path == '/chat/completions' && _isFullChatEndpoint(normalized)) {
      return Uri.parse(normalized);
    }
    if (path == '/images/generations' && (_isFullChatEndpoint(normalized) || _isFullImageGenerationEndpoint(normalized))) {
      return Uri.parse(normalized);
    }
    if (path == '/images/edits' && (_isFullChatEndpoint(normalized) || _isFullImageEditEndpoint(normalized))) {
      return Uri.parse(normalized);
    }
    return Uri.parse('$normalized$path');
  }

  bool _shouldUseChatStyleImageEndpoint(String baseUrl) => _isFullChatEndpoint(baseUrl);

  String normalizeChatModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'gpt-4o-mini';
    if (value.toLowerCase() == 'gpt-40') return 'gpt-4o';
    return value;
  }

  /// 文生图模型：OpenAI 通用 /images/generations 通常不能使用聊天模型。
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

  /// 图生图/图片编辑模型：默认使用 gpt-image-1，允许服务商自定义图片模型。
  String normalizeImageEditModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'gpt-image-1';
    final lower = value.toLowerCase();
    if (lower == 'gpt-40' || lower == 'gpt-4o' || lower == 'gpt-4o-mini') {
      return 'gpt-image-1';
    }
    return value;
  }

  bool _looksLikeHtml(String body) {
    final value = body.trimLeft().toLowerCase();
    return value.startsWith('<!doctype html') || value.startsWith('<html') || value.startsWith('<');
  }

  String _shortBody(String body, {int maxLength = 800}) {
    final trimmed = body.trim();
    if (trimmed.length <= maxLength) return trimmed;
    return '${trimmed.substring(0, maxLength)}... <truncated, length=${trimmed.length}>';
  }

  Map<String, dynamic> _decodeJsonObjectOrThrow(
    String body, {
    required String category,
    required String title,
    required String endpoint,
    required String model,
    int? statusCode,
  }) {
    if (_looksLikeHtml(body)) {
      _log.error(category, title, '接口返回了 HTML，不是 JSON', details: {
        'endpoint': endpoint,
        'model': model,
        'statusCode': statusCode,
        'responsePreview': _shortBody(body),
      });
      throw Exception('接口返回了 HTML 页面，不是 OpenAI 兼容 JSON。请检查 Base URL 是否填到了网页地址、控制台/中转站首页，或该服务商路径是否正确。Endpoint: $endpoint');
    }

    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
      _log.error(category, title, '接口返回 JSON 但不是对象', details: {
        'endpoint': endpoint,
        'model': model,
        'statusCode': statusCode,
        'responsePreview': _shortBody(body),
      });
      throw Exception('接口返回 JSON 但不是对象，请查看控制台原始响应。Endpoint: $endpoint');
    } catch (e) {
      if (e is FormatException) {
        _log.error(category, title, 'JSON 解析失败', details: {
          'endpoint': endpoint,
          'model': model,
          'statusCode': statusCode,
          'responsePreview': _shortBody(body),
          'error': e.toString(),
        });
        throw Exception('接口返回内容不是合法 JSON，请检查 Base URL、模型供应商兼容性或反代配置。Endpoint: $endpoint。详情见控制台。');
      }
      rethrow;
    }
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
    if (_looksLikeHtml(body)) {
      return '接口返回 HTML 页面，不是 JSON。请检查 Base URL 是否正确。响应预览：${_shortBody(body, maxLength: 300)}';
    }
    return body;
  }

  String _friendlyImageError(String rawError, String requestedModel, String actualModel, String endpointName) {
    final shortError = _extractOpenAiError(rawError);
    final lower = shortError.toLowerCase();
    if (lower.contains('model not found') || lower.contains('no available channel')) {
      return '$endpointName 模型不可用。当前实际请求模型是：$actualModel。请在图片工具配置中填写服务商支持的图片模型。原始错误：$shortError';
    }
    if (lower.contains('not found') || lower.contains('404') || lower.contains('no route')) {
      return '$endpointName 接口不可用。请确认图片 Base URL 是否支持对应接口。原始错误：$shortError';
    }
    if (requestedModel.trim() != actualModel) {
      return '检测到模型配置不适合图片工具，已从“$requestedModel”自动改用“$actualModel”，但接口仍返回错误：$shortError';
    }
    return shortError;
  }

  Map<String, dynamic> _imageContentMessage(String role, String text, String? base64Image) {
    if (base64Image != null && base64Image.isNotEmpty) {
      return {
        'role': role,
        'content': [
          {'type': 'text', 'text': text},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
          }
        ]
      };
    }
    return {'role': role, 'content': text};
  }

  Future<ToolDecision> decideTool({
    required String userText,
    required String? base64Image,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = normalizeChatModel(model);
    final hasImage = base64Image != null && base64Image.isNotEmpty;
    const systemPrompt = '''你是 Luna AI 的工具决策器。你需要根据用户文本和可选图片决定下一步动作。
只能输出 JSON，不要输出 Markdown，不要输出解释文字。

动作 action 只能是：
1. direct_answer：普通聊天、解释、问答、图片理解、图片分析、写文案、总结，不需要生成新图片。
2. text_to_image：用户想从文字创建一张新图片，且不依赖上传图片。
3. image_to_image：用户上传了图片，并要求修改、重绘、换风格、换背景、修复、变清晰、参考原图生成、扩图、局部编辑等，输出新图片。

JSON 格式：
{"action":"direct_answer|text_to_image|image_to_image","prompt":"给图片工具使用的英文或中文优化提示词，没有则为空","reply":"给用户看的简短回复。direct_answer 时这里就是回答内容","size":"1024x1024"}

规则：
- 如果用户只是问图片里有什么、让你分析图片、评价图片、写标题或文案，必须 direct_answer。
- 如果用户要求“把这张图改成...”“换背景”“去掉/添加元素”“转风格”“高清修复”“参考这张图生成”，且有上传图片，必须 image_to_image。
- 如果用户要求“画一张”“生成图片”“设计海报/logo/壁纸”等且没有上传图片，使用 text_to_image。
- 如果没有上传图片，不要使用 image_to_image。
- size 默认 1024x1024。''';

    _log.info('tool_decision', '开始 LLM 工具决策', 'POST /chat/completions', details: {
      'endpoint': url.toString(),
      'model': actualModel,
      'hasImage': hasImage,
      'userText': userText,
    });

    final body = {
      'model': actualModel,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        _imageContentMessage('user', userText.isEmpty ? '请根据上传图片继续处理' : userText, base64Image),
      ],
      'stream': false,
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: jsonEncode(body),
    );
    final bodyText = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log.error('tool_decision', 'LLM 工具决策失败', 'HTTP ${response.statusCode}', details: {
        'endpoint': url.toString(),
        'model': actualModel,
        'statusCode': response.statusCode,
        'response': bodyText,
      });
      throw Exception('工具决策失败 ${response.statusCode}: ${_extractOpenAiError(bodyText)}');
    }

    final parsed = _decodeJsonObjectOrThrow(
      bodyText,
      category: 'tool_decision',
      title: 'LLM 工具决策响应解析失败',
      endpoint: url.toString(),
      model: actualModel,
      statusCode: response.statusCode,
    );
    final rawContent = parsed['choices']?[0]?['message']?['content']?.toString() ?? '';
    final decision = _parseDecision(rawContent, userText: userText, hasImage: hasImage);
    _log.success('tool_decision', 'LLM 工具决策完成', decision.action.name, details: {
      'rawContent': rawContent,
      'action': decision.action.name,
      'prompt': decision.prompt,
      'reply': decision.reply,
      'size': decision.size,
    });
    return decision;
  }

  ToolDecision _parseDecision(String raw, {required String userText, required bool hasImage}) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceAll(RegExp(r'^```json\s*', multiLine: true), '').replaceAll(RegExp(r'^```\s*', multiLine: true), '').replaceAll(RegExp(r'```\s*$', multiLine: true), '').trim();
    }
    try {
      final data = jsonDecode(cleaned);
      final actionText = data['action']?.toString() ?? 'direct_answer';
      final action = switch (actionText) {
        'text_to_image' => ToolAction.textToImage,
        'image_to_image' => hasImage ? ToolAction.imageToImage : ToolAction.textToImage,
        _ => ToolAction.directAnswer,
      };
      final prompt = data['prompt']?.toString().trim() ?? userText.trim();
      final reply = data['reply']?.toString().trim() ?? '';
      final size = data['size']?.toString().trim().isNotEmpty == true ? data['size'].toString().trim() : '1024x1024';
      return ToolDecision(action: action, prompt: prompt.isEmpty ? userText : prompt, reply: reply, size: size);
    } catch (e) {
      _log.warning('tool_decision', 'LLM 决策 JSON 解析失败', '使用兜底逻辑', details: {'rawContent': raw, 'error': e.toString()});
      if (!hasImage && _looksLikeImagePrompt(userText)) {
        return ToolDecision(action: ToolAction.textToImage, prompt: userText, reply: '我会为你生成图片。', size: '1024x1024');
      }
      return ToolDecision(action: ToolAction.directAnswer, prompt: '', reply: raw.trim().isEmpty ? '我暂时无法判断你的意图，请换个说法。' : raw.trim(), size: '1024x1024');
    }
  }

  bool _looksLikeImagePrompt(String text) {
    final value = text.trim().toLowerCase();
    const prefixes = ['/image', '/img', '/draw', '画图', '绘图', '生图', '生成图片', '生成一张', '帮我画', '画一张', '做一张图', '出一张图', 'create an image', 'generate an image', 'draw '];
    if (prefixes.any(value.startsWith)) return true;
    const imageWords = ['图片', '图像', '插画', '海报', '头像', '壁纸', 'logo', 'poster', 'illustration', 'wallpaper'];
    const actionWords = ['生成', '画', '绘制', '设计', 'create', 'generate', 'draw', 'design'];
    return imageWords.any(value.contains) && actionWords.any(value.contains);
  }

  Stream<String> generateChatStream(
    List<Message> history,
    String apiKey,
    String baseUrl,
    String model,
  ) async* {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = normalizeChatModel(model);
    final formattedMessages = history.map((msg) => msg.toOpenAiMap()).toList();
    final hasImage = history.any((m) => m.base64Image != null && m.base64Image!.isNotEmpty);

    _log.info('chat', '开始聊天请求', 'POST /chat/completions', details: {
      'endpoint': url.toString(),
      'model': actualModel,
      'messageCount': history.length,
      'hasImage': hasImage,
      'stream': true,
    });

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream, application/json'
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..body = jsonEncode({
        'model': actualModel,
        'messages': formattedMessages,
        'stream': true,
      });

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBytes = await response.stream.toBytes();
        final errorMsg = utf8.decode(errorBytes);
        _log.error('chat', '聊天请求失败', 'HTTP ${response.statusCode}', details: {
          'endpoint': url.toString(),
          'model': actualModel,
          'statusCode': response.statusCode,
          'response': errorMsg,
        });
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
          } catch (_) {}
        } else {
          jsonBuffer.writeln(trimmed);
        }
      }

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
      _log.success('chat', '聊天请求完成', '流式响应已结束', details: {'endpoint': url.toString(), 'model': actualModel});
    } finally {
      client.close();
    }
  }

  Future<String> generateImage(
    String prompt,
    String apiKey,
    String baseUrl,
    String model, {
    String size = '1024x1024',
  }) async {
    if (_shouldUseChatStyleImageEndpoint(baseUrl)) {
      return _callChatStyleImageTool(
        prompt: prompt,
        base64Image: null,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        size: size,
        category: 'text_to_image',
        title: '文生图',
      );
    }

    final url = _endpoint(baseUrl, '/images/generations');
    final imageModel = normalizeImageModel(model);

    _log.info('text_to_image', '开始文生图工具调用', 'POST /images/generations', details: {
      'endpoint': url.toString(),
      'model': imageModel,
      'prompt': prompt,
      'size': size,
    });

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
      _log.error('text_to_image', '文生图工具调用失败', 'HTTP ${response.statusCode}', details: {
        'endpoint': url.toString(),
        'model': imageModel,
        'statusCode': response.statusCode,
        'response': bodyText,
      });
      throw Exception(_friendlyImageError(bodyText, model, imageModel, '文生图'));
    }

    final result = _extractImageResult(bodyText, endpoint: url.toString(), model: imageModel, category: 'text_to_image');
    _log.success('text_to_image', '文生图工具调用成功', result.startsWith('data:image') ? '返回 base64 图片' : '返回图片 URL', details: {'endpoint': url.toString(), 'model': imageModel});
    return result;
  }

  Future<String> editImage(
    String prompt,
    File imageFile,
    String apiKey,
    String baseUrl,
    String model, {
    String size = '1024x1024',
  }) async {
    if (_shouldUseChatStyleImageEndpoint(baseUrl)) {
      final base64Image = base64Encode(await imageFile.readAsBytes());
      return _callChatStyleImageTool(
        prompt: prompt,
        base64Image: base64Image,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        size: size,
        category: 'image_to_image',
        title: '图生图 / 图片编辑',
      );
    }

    final url = _endpoint(baseUrl, '/images/edits');
    final editModel = normalizeImageEditModel(model);
    final bytes = await imageFile.length();

    _log.info('image_to_image', '开始图生图工具调用', 'POST /images/edits multipart/form-data', details: {
      'endpoint': url.toString(),
      'model': editModel,
      'prompt': prompt,
      'size': size,
      'imagePath': imageFile.path,
      'imageSizeBytes': bytes,
    });

    final request = http.MultipartRequest('POST', url)
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..fields['model'] = editModel
      ..fields['prompt'] = prompt
      ..fields['n'] = '1'
      ..fields['size'] = size
      ..files.add(await http.MultipartFile.fromPath('image', imageFile.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final bodyText = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log.error('image_to_image', '图生图工具调用失败', 'HTTP ${response.statusCode}', details: {
        'endpoint': url.toString(),
        'model': editModel,
        'statusCode': response.statusCode,
        'response': bodyText,
      });
      throw Exception(_friendlyImageError(bodyText, model, editModel, '图生图 / 图片编辑'));
    }

    final result = _extractImageResult(bodyText, endpoint: url.toString(), model: editModel, category: 'image_to_image');
    _log.success('image_to_image', '图生图工具调用成功', result.startsWith('data:image') ? '返回 base64 图片' : '返回图片 URL', details: {'endpoint': url.toString(), 'model': editModel});
    return result;
  }

  Future<String> _callChatStyleImageTool({
    required String prompt,
    required String? base64Image,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String size,
    required String category,
    required String title,
  }) async {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = model.trim().isEmpty ? normalizeChatModel(model) : model.trim();
    final hasImage = base64Image != null && base64Image.isNotEmpty;
    final instruction = hasImage
        ? '$prompt\n\n请根据上传图片进行生成/编辑，返回图片 URL 或 base64 图片数据。尺寸：$size。'
        : '$prompt\n\n请生成图片，返回图片 URL 或 base64 图片数据。尺寸：$size。';

    _log.info(category, '开始$title自定义 /chat 接口调用', 'POST ${url.path}', details: {
      'endpoint': url.toString(),
      'model': actualModel,
      'prompt': prompt,
      'size': size,
      'hasImage': hasImage,
    });

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: jsonEncode({
        'model': actualModel,
        'messages': [
          {
            'role': 'system',
            'content': '你是图片生成/编辑工具。请只返回最终图片 URL 或 data:image/...;base64,...，不要输出多余解释。',
          },
          _imageContentMessage('user', instruction, base64Image),
        ],
        'stream': false,
      }),
    );

    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log.error(category, '$title自定义 /chat 接口调用失败', 'HTTP ${response.statusCode}', details: {
        'endpoint': url.toString(),
        'model': actualModel,
        'statusCode': response.statusCode,
        'response': bodyText,
      });
      throw Exception(_friendlyImageError(bodyText, model, actualModel, title));
    }

    final result = _extractImageResultFlexible(bodyText, endpoint: url.toString(), model: actualModel, category: category);
    _log.success(category, '$title自定义 /chat 接口调用成功', result.startsWith('data:image') ? '返回 base64 图片' : '返回图片 URL', details: {
      'endpoint': url.toString(),
      'model': actualModel,
    });
    return result;
  }

  String _extractImageResultFlexible(
    String bodyText, {
    required String endpoint,
    required String model,
    required String category,
  }) {
    final data = _decodeJsonObjectOrThrow(
      bodyText,
      category: category,
      title: '图片接口响应解析失败',
      endpoint: endpoint,
      model: model,
    );

    final fromData = _tryExtractOpenAiImageData(data);
    if (fromData != null) return fromData;

    final content = data['choices']?[0]?['message']?['content']?.toString() ?? data['choices']?[0]?['text']?.toString() ?? '';
    final fromContent = _tryExtractImageFromText(content);
    if (fromContent != null) return fromContent;

    final directUrl = data['url']?.toString();
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;
    final directB64 = data['b64_json']?.toString() ?? data['base64']?.toString() ?? data['image']?.toString();
    if (directB64 != null && directB64.isNotEmpty) {
      if (directB64.startsWith('data:image')) return directB64;
      return 'data:image/png;base64,$directB64';
    }

    throw Exception('图片接口未返回图片 URL 或 base64。Endpoint: $endpoint。响应预览：${_shortBody(bodyText)}');
  }

  String? _tryExtractImageFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final dataMatch = RegExp(r'data:image/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=\r\n]+').firstMatch(trimmed);
    if (dataMatch != null) return dataMatch.group(0)!.replaceAll(RegExp(r'\s+'), '');

    final markdownImage = RegExp(r'!\[[^\]]*\]\((https?://[^\s)]+)\)').firstMatch(trimmed);
    if (markdownImage != null) return markdownImage.group(1)!;

    final markdownLink = RegExp(r'\[[^\]]*\]\((https?://[^\s)]+)\)').firstMatch(trimmed);
    if (markdownLink != null) return markdownLink.group(1)!;

    final urlMatch = RegExp(r'''https?://[^\s"'<>）)]+''').firstMatch(trimmed);
    if (urlMatch != null) return urlMatch.group(0)!;
    return null;
  }

  String? _tryExtractOpenAiImageData(Map<String, dynamic> data) {
    final first = data['data']?[0];
    final imageUrl = first?['url'];
    if (imageUrl != null && imageUrl.toString().isNotEmpty) {
      return imageUrl.toString();
    }

    final b64 = first?['b64_json'];
    if (b64 != null && b64.toString().isNotEmpty) {
      return 'data:image/png;base64,${b64.toString()}';
    }
    return null;
  }

  String _extractImageResult(
    String bodyText, {
    required String endpoint,
    required String model,
    required String category,
  }) {
    final data = _decodeJsonObjectOrThrow(
      bodyText,
      category: category,
      title: '图片接口响应解析失败',
      endpoint: endpoint,
      model: model,
    );
    final first = data['data']?[0];
    final imageUrl = first?['url'];
    if (imageUrl != null && imageUrl.toString().isNotEmpty) {
      return imageUrl.toString();
    }

    final b64 = first?['b64_json'];
    if (b64 != null && b64.toString().isNotEmpty) {
      return 'data:image/png;base64,${b64.toString()}';
    }

    throw Exception('图片接口未返回 data[0].url 或 data[0].b64_json');
  }
}
