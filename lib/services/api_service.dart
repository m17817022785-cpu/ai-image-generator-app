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
  final String quality;

  const ToolDecision({required this.action, required this.prompt, required this.reply, required this.size, this.quality = 'auto'});

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

  Uri _endpoint(String baseUrl, String path) {
    final normalized = _normalizeBaseUrl(baseUrl);
    final uri = Uri.tryParse(normalized);
    final currentPath = (uri?.path ?? '').toLowerCase();
    final isChat = currentPath == '/chat' || currentPath.endsWith('/chat/completions') || currentPath.endsWith('/completions');
    final isGeneration = currentPath.endsWith('/images/generations');
    final isEdit = currentPath.endsWith('/images/edits');
    if (path == '/chat/completions' && isChat) return Uri.parse(normalized);
    if (path == '/images/generations' && (isChat || isGeneration)) return Uri.parse(normalized);
    if (path == '/images/edits' && (isChat || isEdit)) return Uri.parse(normalized);
    return Uri.parse('$normalized$path');
  }

  bool _useChatImageEndpoint(String baseUrl) {
    final path = Uri.tryParse(_normalizeBaseUrl(baseUrl))?.path.toLowerCase() ?? '';
    return path == '/chat' || path.endsWith('/chat/completions') || path.endsWith('/completions');
  }

  String normalizeChatModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'gpt-4o-mini';
    if (value.toLowerCase() == 'gpt-40') return 'gpt-4o';
    return value;
  }

  String normalizeImageModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'dall-e-3';
    final lower = value.toLowerCase();
    final image = lower.startsWith('dall-e') || lower.contains('image');
    final chat = lower == 'gpt-40' || lower == 'gpt-4o' || lower == 'gpt-4o-mini' || lower.startsWith('gpt-4') || lower.startsWith('gpt-3.5') || lower.startsWith('claude') || lower.startsWith('gemini') || lower.startsWith('deepseek') || lower.startsWith('qwen') || lower.startsWith('glm');
    return chat && !image ? 'dall-e-3' : value;
  }

  String normalizeImageEditModel(String model) {
    final value = model.trim();
    if (value.isEmpty) return 'gpt-image-1';
    final lower = value.toLowerCase();
    if (lower == 'gpt-40' || lower == 'gpt-4o' || lower == 'gpt-4o-mini') return 'gpt-image-1';
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

  Map<String, dynamic> _decodeJsonObject(String body, {required String category, required String title, required String endpoint, required String model, int? statusCode}) {
    if (_looksLikeHtml(body)) {
      _log.error(category, title, '接口返回了 HTML，不是 JSON', details: {'endpoint': endpoint, 'model': model, 'statusCode': statusCode, 'responsePreview': _shortBody(body)});
      throw Exception('接口返回了 HTML 页面，不是 OpenAI 兼容 JSON。请检查 Base URL。Endpoint: $endpoint');
    }
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
      throw Exception('接口返回 JSON 但不是对象。Endpoint: $endpoint');
    } catch (e) {
      if (e is FormatException) {
        _log.error(category, title, 'JSON 解析失败', details: {'endpoint': endpoint, 'model': model, 'statusCode': statusCode, 'responsePreview': _shortBody(body), 'error': e.toString()});
        throw Exception('接口返回内容不是合法 JSON。Endpoint: $endpoint。详情见控制台。');
      }
      rethrow;
    }
  }

  String _extractError(String body) {
    try {
      final parsed = jsonDecode(body);
      final error = parsed['error'];
      if (error is Map) {
        final message = error['message']?.toString();
        final code = error['code']?.toString();
        if (message != null && message.isNotEmpty) {
          final base = code == null || code.isEmpty ? message : '$message ($code)';
          final lower = base.toLowerCase();
          if (lower.contains('auth_not_found') || lower.contains('no auth available')) {
            return '$base。提示：服务端没有该 provider/model 的可用授权，或模型被中转站路由到了未配置的渠道。请检查聊天模型、文生图模型、图生图模型三个字段。';
          }
          return base;
        }
      }
    } catch (_) {}
    if (_looksLikeHtml(body)) return '接口返回 HTML 页面，不是 JSON。响应预览：${_shortBody(body, maxLength: 300)}';
    return body;
  }

  String _friendlyImageError(String raw, String requestedModel, String actualModel, String endpointName) {
    final msg = _extractError(raw);
    final lower = msg.toLowerCase();
    if (lower.contains('model not found') || lower.contains('no available channel')) return '$endpointName 模型不可用。当前实际请求模型是：$actualModel。请填写服务商支持的图片模型。原始错误：$msg';
    if (lower.contains('not found') || lower.contains('404') || lower.contains('no route')) return '$endpointName 接口不可用。请确认图片 Base URL 是否支持对应接口。原始错误：$msg';
    if (requestedModel.trim() != actualModel) return '检测到模型配置不适合图片工具，已从“$requestedModel”自动改用“$actualModel”，但接口仍返回错误：$msg';
    return msg;
  }

  Map<String, dynamic> _imageContentMessage(String role, String text, String? base64Image) {
    if (base64Image != null && base64Image.isNotEmpty) {
      return {
        'role': role,
        'content': [
          {'type': 'text', 'text': text},
          {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}}
        ]
      };
    }
    return {'role': role, 'content': text};
  }

  Future<ToolDecision> decideTool({required String userText, required String? base64Image, required String apiKey, required String baseUrl, required String model}) async {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = normalizeChatModel(model);
    final hasImage = base64Image != null && base64Image.isNotEmpty;
    const systemPrompt = '''你是 Luna AI 的工具决策器。只能输出 JSON，不要 Markdown。
action 只能是 direct_answer、text_to_image、image_to_image。
JSON：{"action":"direct_answer|text_to_image|image_to_image","prompt":"给图片工具使用的优化提示词","reply":"给用户看的简短回复","size":"1024x1024","quality":"auto|standard|hd|low|medium|high"}
规则：图片分析/问答/写文案使用 direct_answer；无图生成新图使用 text_to_image；有上传图并要求修改/重绘/换风格/修复/参考图生成使用 image_to_image；没有上传图不要 image_to_image。size 默认 1024x1024，横图可 1792x1024，竖图可 1024x1792。quality 默认 auto，高清可 hd/high。''';
    _log.info('tool_decision', '开始 LLM 工具决策', 'POST /chat/completions', details: {'endpoint': url.toString(), 'model': actualModel, 'hasImage': hasImage, 'userText': userText});
    final response = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'Authorization': 'Bearer ${apiKey.trim()}'}, body: jsonEncode({'model': actualModel, 'messages': [{'role': 'system', 'content': systemPrompt}, _imageContentMessage('user', userText.isEmpty ? '请根据上传图片继续处理' : userText, base64Image)], 'stream': false}));
    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('工具决策失败 ${response.statusCode}: ${_extractError(bodyText)}');
    final parsed = _decodeJsonObject(bodyText, category: 'tool_decision', title: 'LLM 工具决策响应解析失败', endpoint: url.toString(), model: actualModel, statusCode: response.statusCode);
    final raw = parsed['choices']?[0]?['message']?['content']?.toString() ?? '';
    final decision = _parseDecision(raw, userText: userText, hasImage: hasImage);
    _log.success('tool_decision', 'LLM 工具决策完成', decision.action.name, details: {'rawContent': raw, 'action': decision.action.name, 'prompt': decision.prompt, 'size': decision.size, 'quality': decision.quality});
    return decision;
  }

  ToolDecision _parseDecision(String raw, {required String userText, required bool hasImage}) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) cleaned = cleaned.replaceAll(RegExp(r'^```json\s*', multiLine: true), '').replaceAll(RegExp(r'^```\s*', multiLine: true), '').replaceAll(RegExp(r'```\s*$', multiLine: true), '').trim();
    try {
      final data = jsonDecode(cleaned);
      final text = data['action']?.toString() ?? 'direct_answer';
      final action = switch (text) {'text_to_image' => ToolAction.textToImage, 'image_to_image' => hasImage ? ToolAction.imageToImage : ToolAction.textToImage, _ => ToolAction.directAnswer};
      final prompt = data['prompt']?.toString().trim() ?? userText.trim();
      final reply = data['reply']?.toString().trim() ?? '';
      final size = data['size']?.toString().trim().isNotEmpty == true ? data['size'].toString().trim() : '1024x1024';
      final quality = data['quality']?.toString().trim().isNotEmpty == true ? data['quality'].toString().trim() : 'auto';
      return ToolDecision(action: action, prompt: prompt.isEmpty ? userText : prompt, reply: reply, size: size, quality: quality);
    } catch (e) {
      _log.warning('tool_decision', 'LLM 决策 JSON 解析失败', '使用兜底逻辑', details: {'rawContent': raw, 'error': e.toString()});
      if (!hasImage && _looksLikeImagePrompt(userText)) return ToolDecision(action: ToolAction.textToImage, prompt: userText, reply: '我会为你生成图片。', size: '1024x1024');
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

  String? _normalizeImageQuality(String quality, String model) {
    final value = quality.trim().toLowerCase();
    if (value.isEmpty || value == 'auto') return null;
    final lowerModel = model.toLowerCase();
    if (lowerModel.startsWith('dall-e-3')) return value == 'hd' || value == 'high' ? 'hd' : 'standard';
    if (lowerModel.contains('gpt-image')) {
      if (value == 'hd') return 'high';
      if (value == 'standard') return 'medium';
      if (value == 'low' || value == 'medium' || value == 'high') return value;
      return null;
    }
    if (value == 'hd' || value == 'standard' || value == 'low' || value == 'medium' || value == 'high') return value;
    return null;
  }

  String _qualityLabel(String quality) => switch (quality.trim().toLowerCase()) {'hd' || 'high' => '高清/高质量', 'medium' => '中高质量', 'low' => '快速/低成本', 'standard' => '标准质量', _ => '自动'};

  Future<String> refineImagePrompt({required String userText, required String? base64Image, required String apiKey, required String baseUrl, required String model, required String aspectRatio, required String size, required String quality, required bool isEdit}) async {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = normalizeChatModel(model);
    const systemPrompt = '''你是专业图片生成提示词优化器。请把用户要求润色为更适合图片生成/图片编辑模型的提示词。只能输出最终提示词，不要 Markdown，不要解释。保留用户核心意图，补充构图、光线、镜头、质感、细节、色彩、背景和氛围。图生图/编辑时强调参考原图一致性和需要修改的部分，不要编造冲突元素。''';
    final userInstruction = '原始要求：$userText\n生成模式：${isEdit ? '图生图/图片编辑' : '文生图'}\n目标比例：$aspectRatio\n目标尺寸：$size\n清晰度/质量：${_qualityLabel(quality)}\n请润色为高质量图片生成提示词。';
    final response = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'Authorization': 'Bearer ${apiKey.trim()}'}, body: jsonEncode({'model': actualModel, 'messages': [{'role': 'system', 'content': systemPrompt}, _imageContentMessage('user', userInstruction, base64Image)], 'stream': false}));
    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('提示词润色失败 ${response.statusCode}: ${_extractError(bodyText)}');
    final parsed = _decodeJsonObject(bodyText, category: 'prompt_refine', title: 'LLM 润色提示词响应解析失败', endpoint: url.toString(), model: actualModel, statusCode: response.statusCode);
    final refined = parsed['choices']?[0]?['message']?['content']?.toString().trim() ?? '';
    return refined.isEmpty ? userText : refined;
  }

  Stream<String> generateChatStream(List<Message> history, String apiKey, String baseUrl, String model) async* {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = normalizeChatModel(model);
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream, application/json'
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..body = jsonEncode({'model': actualModel, 'messages': history.map((msg) => msg.toOpenAiMap()).toList(), 'stream': true});
    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorMsg = utf8.decode(await response.stream.toBytes());
        throw Exception('API 错误码 ${response.statusCode}: ${_extractError(errorMsg)}');
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
            final delta = parsed['choices']?[0]?['delta']?['content'] ?? '';
            if (delta.toString().isNotEmpty) yield delta.toString();
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
          if (content.toString().isNotEmpty) yield content.toString();
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  Future<String> generateImage(String prompt, String apiKey, String baseUrl, String model, {String size = '1024x1024', String quality = 'auto'}) async {
    if (_useChatImageEndpoint(baseUrl)) return _callChatStyleImageTool(prompt: prompt, base64Image: null, apiKey: apiKey, baseUrl: baseUrl, model: model, size: size, quality: quality, category: 'text_to_image', title: '文生图');
    final url = _endpoint(baseUrl, '/images/generations');
    final imageModel = normalizeImageModel(model);
    final qualityValue = _normalizeImageQuality(quality, imageModel);
    final body = <String, dynamic>{'model': imageModel, 'prompt': prompt, 'n': 1, 'size': size, if (qualityValue != null) 'quality': qualityValue};
    final response = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'Authorization': 'Bearer ${apiKey.trim()}'}, body: jsonEncode(body));
    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_friendlyImageError(bodyText, model, imageModel, '文生图'));
    return _extractImageResult(bodyText, endpoint: url.toString(), model: imageModel, category: 'text_to_image');
  }

  Future<String> editImage(String prompt, File imageFile, String apiKey, String baseUrl, String model, {String size = '1024x1024', String quality = 'auto'}) async {
    if (_useChatImageEndpoint(baseUrl)) {
      final base64Image = base64Encode(await imageFile.readAsBytes());
      return _callChatStyleImageTool(prompt: prompt, base64Image: base64Image, apiKey: apiKey, baseUrl: baseUrl, model: model, size: size, quality: quality, category: 'image_to_image', title: '图生图 / 图片编辑');
    }
    final url = _endpoint(baseUrl, '/images/edits');
    final editModel = normalizeImageEditModel(model);
    final qualityValue = _normalizeImageQuality(quality, editModel);
    final request = http.MultipartRequest('POST', url)
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..fields['model'] = editModel
      ..fields['prompt'] = prompt
      ..fields['n'] = '1'
      ..fields['size'] = size;
    if (qualityValue != null) request.fields['quality'] = qualityValue;
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    final response = await http.Response.fromStream(await request.send());
    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_friendlyImageError(bodyText, model, editModel, '图生图 / 图片编辑'));
    return _extractImageResult(bodyText, endpoint: url.toString(), model: editModel, category: 'image_to_image');
  }

  Future<String> _callChatStyleImageTool({required String prompt, required String? base64Image, required String apiKey, required String baseUrl, required String model, required String size, String quality = 'auto', required String category, required String title}) async {
    final url = _endpoint(baseUrl, '/chat/completions');
    final actualModel = model.trim().isEmpty ? normalizeChatModel(model) : model.trim();
    final instruction = base64Image != null && base64Image.isNotEmpty ? '$prompt\n\n请根据上传图片进行生成/编辑，返回图片 URL 或 base64 图片数据。尺寸：$size。清晰度/质量：${_qualityLabel(quality)}。' : '$prompt\n\n请生成图片，返回图片 URL 或 base64 图片数据。尺寸：$size。清晰度/质量：${_qualityLabel(quality)}。';
    final response = await http.post(url, headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'Authorization': 'Bearer ${apiKey.trim()}'}, body: jsonEncode({'model': actualModel, 'messages': [{'role': 'system', 'content': '你是图片生成/编辑工具。请只返回最终图片 URL 或 data:image/...;base64,...，不要输出多余解释。'}, _imageContentMessage('user', instruction, base64Image)], 'stream': false}));
    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_friendlyImageError(bodyText, model, actualModel, title));
    return _extractImageResultFlexible(bodyText, endpoint: url.toString(), model: actualModel, category: category);
  }

  String _extractImageResultFlexible(String bodyText, {required String endpoint, required String model, required String category}) {
    final data = _decodeJsonObject(bodyText, category: category, title: '图片接口响应解析失败', endpoint: endpoint, model: model);
    final fromData = _tryExtractOpenAiImageData(data);
    if (fromData != null) return fromData;
    final content = data['choices']?[0]?['message']?['content']?.toString() ?? data['choices']?[0]?['text']?.toString() ?? '';
    final fromContent = _tryExtractImageFromText(content);
    if (fromContent != null) return fromContent;
    final directUrl = data['url']?.toString();
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;
    final b64 = data['b64_json']?.toString() ?? data['base64']?.toString() ?? data['image']?.toString();
    if (b64 != null && b64.isNotEmpty) return b64.startsWith('data:image') ? b64 : 'data:image/png;base64,$b64';
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
    return urlMatch?.group(0);
  }

  String? _tryExtractOpenAiImageData(Map<String, dynamic> data) {
    final first = data['data']?[0];
    final imageUrl = first?['url'];
    if (imageUrl != null && imageUrl.toString().isNotEmpty) return imageUrl.toString();
    final b64 = first?['b64_json'];
    if (b64 != null && b64.toString().isNotEmpty) return 'data:image/png;base64,${b64.toString()}';
    return null;
  }

  String _extractImageResult(String bodyText, {required String endpoint, required String model, required String category}) {
    final data = _decodeJsonObject(bodyText, category: category, title: '图片接口响应解析失败', endpoint: endpoint, model: model);
    final result = _tryExtractOpenAiImageData(data);
    if (result != null) return result;
    throw Exception('图片接口未返回 data[0].url 或 data[0].b64_json');
  }
}
