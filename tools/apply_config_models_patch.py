from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new), encoding='utf-8')


# Settings: do not prefill config defaults in saved settings UI.
replace(
    'lib/services/settings_service.dart',
    "    await prefs.setString(_keyImageEditModel, (imageEditModel ?? 'gpt-image-1').trim());",
    "    await prefs.setString(_keyImageEditModel, (imageEditModel ?? '').trim());",
)
replace(
    'lib/services/settings_service.dart',
    "    final baseUrl = prefs.getString(_keyBaseUrl) ?? 'https://api.openai.com/v1';",
    "    final baseUrl = prefs.getString(_keyBaseUrl) ?? '';",
)
replace(
    'lib/services/settings_service.dart',
    "      'chatModel': prefs.getString(_keyChatModel) ?? 'gpt-4o-mini',\n      'imageModel': prefs.getString(_keyImageModel) ?? 'dall-e-3',\n      'imageEditModel': prefs.getString(_keyImageEditModel) ?? 'gpt-image-1',",
    "      'chatModel': prefs.getString(_keyChatModel) ?? '',\n      'imageModel': prefs.getString(_keyImageModel) ?? '',\n      'imageEditModel': prefs.getString(_keyImageEditModel) ?? '',",
)

# ApiService: add OpenAI-compatible /models fetch support.
replace(
    'lib/services/api_service.dart',
    "  bool _useChatImageEndpoint(String baseUrl) {\n    final path = Uri.tryParse(_normalizeBaseUrl(baseUrl))?.path.toLowerCase() ?? '';\n    return path == '/chat' || path.endsWith('/chat/completions') || path.endsWith('/completions');\n  }\n\n  String normalizeChatModel(String model) {",
    "  Uri _modelsEndpoint(String baseUrl) {\n    var normalized = _normalizeBaseUrl(baseUrl);\n    final uri = Uri.tryParse(normalized);\n    final path = (uri?.path ?? '').toLowerCase();\n    const suffixes = ['/chat/completions', '/completions', '/images/generations', '/images/edits', '/chat'];\n    for (final suffix in suffixes) {\n      if (path == suffix || path.endsWith(suffix)) {\n        normalized = normalized.substring(0, normalized.length - suffix.length);\n        break;\n      }\n    }\n    while (normalized.endsWith('/')) {\n      normalized = normalized.substring(0, normalized.length - 1);\n    }\n    return Uri.parse('$normalized/models');\n  }\n\n  bool _useChatImageEndpoint(String baseUrl) {\n    final path = Uri.tryParse(_normalizeBaseUrl(baseUrl))?.path.toLowerCase() ?? '';\n    return path == '/chat' || path.endsWith('/chat/completions') || path.endsWith('/completions');\n  }\n\n  Future<List<String>> fetchModels({required String apiKey, required String baseUrl}) async {\n    final url = _modelsEndpoint(baseUrl);\n    _log.info('models', '开始获取服务商模型', 'GET /models', details: {'endpoint': url.toString()});\n    final response = await http.get(url, headers: {'Accept': 'application/json', if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}'});\n    final bodyText = utf8.decode(response.bodyBytes);\n    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('获取模型失败 ${response.statusCode}: ${_extractError(bodyText)}');\n    final parsed = _decodeJsonObject(bodyText, category: 'models', title: '获取服务商模型响应解析失败', endpoint: url.toString(), model: '', statusCode: response.statusCode);\n    final rawModels = parsed['data'];\n    final models = <String>[];\n    if (rawModels is List) {\n      for (final item in rawModels) {\n        if (item is Map && item['id'] != null) models.add(item['id'].toString());\n        if (item is String) models.add(item);\n      }\n    } else if (parsed['models'] is List) {\n      for (final item in parsed['models'] as List) {\n        if (item is Map && item['id'] != null) models.add(item['id'].toString());\n        if (item is String) models.add(item);\n      }\n    }\n    final unique = models.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();\n    if (unique.isEmpty) throw Exception('服务商没有返回可识别的模型列表。Endpoint: $url');\n    _log.success('models', '服务商模型获取完成', '${unique.length} models', details: {'endpoint': url.toString(), 'models': unique});\n    return unique;\n  }\n\n  String normalizeChatModel(String model) {",
)

# HomeScreen: keep config fields blank until user fills them.
replace(
    'lib/screens/home_screen.dart',
    "  String _baseUrl = 'https://api.openai.com/v1';\n  String _imageBaseUrl = '';\n  String _chatModel = 'gpt-4o-mini';\n  String _imageModel = 'dall-e-3';\n  String _imageEditModel = 'gpt-image-1';",
    "  String _baseUrl = '';\n  String _imageBaseUrl = '';\n  String _chatModel = '';\n  String _imageModel = '';\n  String _imageEditModel = '';",
)
replace(
    'lib/screens/home_screen.dart',
    "        _baseUrl = s['baseUrl'] ?? 'https://api.openai.com/v1';\n        _imageBaseUrl = s['imageBaseUrl'] ?? '';\n        _chatModel = s['chatModel'] ?? 'gpt-4o-mini';\n        _imageModel = s['imageModel'] ?? 'dall-e-3';\n        _imageEditModel = s['imageEditModel'] ?? 'gpt-image-1';",
    "        _baseUrl = s['baseUrl'] ?? '';\n        _imageBaseUrl = s['imageBaseUrl'] ?? '';\n        _chatModel = s['chatModel'] ?? '';\n        _imageModel = s['imageModel'] ?? '';\n        _imageEditModel = s['imageEditModel'] ?? '';",
)
replace(
    'lib/screens/home_screen.dart',
    "                  _baseUrl = base.text.trim().isEmpty ? 'https://api.openai.com/v1' : base.text.trim();\n                  _imageBaseUrl = imageBase.text.trim();\n                  _chatModel = chat.text.trim().isEmpty ? 'gpt-4o-mini' : chat.text.trim();\n                  _imageModel = _api.normalizeImageModel(image.text.trim().isEmpty ? 'dall-e-3' : image.text.trim());\n                  _imageEditModel = _api.normalizeImageEditModel(edit.text.trim().isEmpty ? 'gpt-image-1' : edit.text.trim());",
    "                  _baseUrl = base.text.trim();\n                  _imageBaseUrl = imageBase.text.trim();\n                  _chatModel = chat.text.trim();\n                  _imageModel = image.text.trim();\n                  _imageEditModel = edit.text.trim();",
)

fetch_fn = """  Future<void> _fetchAndFillModel({
    required TextEditingController key,
    required TextEditingController base,
    required TextEditingController target,
    required String title,
    TextEditingController? imageKey,
    TextEditingController? imageBase,
    bool useImageProvider = false,
  }) async {
    final apiKey = useImageProvider && (imageKey?.text.trim().isNotEmpty ?? false) ? imageKey!.text.trim() : key.text.trim();
    final baseUrl = useImageProvider && (imageBase?.text.trim().isNotEmpty ?? false) ? imageBase!.text.trim() : base.text.trim();
    if (baseUrl.isEmpty) {
      _snack('请先填写 Base URL，再获取模型。');
      return;
    }
    try {
      _snack('正在获取服务商模型…');
      final models = await _api.fetchModels(apiKey: apiKey, baseUrl: baseUrl);
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Container(
            height: MediaQuery.of(ctx).size.height * .72,
            padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(ctx).padding.bottom + 16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.96), borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('共获取到 ${models.length} 个模型，点击一个模型回填到输入框。', style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: models.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(models[i], style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
                    onTap: () => Navigator.pop(ctx, models[i]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
      if (selected != null && selected.trim().isNotEmpty) {
        target.text = selected.trim();
        _snack('已选择模型：${selected.trim()}');
      }
    } catch (e) {
      _snack('获取模型失败：$e');
    }
  }

"""
replace(
    'lib/screens/home_screen.dart',
    "  Future<void> _openSettings() async {\n    final key = TextEditingController(text: _apiKey);",
    fetch_fn + "  Future<void> _openSettings() async {\n    final key = TextEditingController(text: _apiKey);",
)

replace(
    'lib/screens/home_screen.dart',
    "          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [_field(key, '聊天 API Key'), _field(base, '聊天 Base URL'), _field(chat, '聊天模型'), _field(imageKey, '图片 API Key（可留空）'), _field(imageBase, '图片 Base URL（可留空）'), _field(image, '文生图模型'), _field(edit, '图生图模型')])),",
    """          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(key, '聊天 API Key'),
              _field(base, '聊天 Base URL'),
              _field(chat, '聊天模型'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _fetchAndFillModel(key: key, base: base, target: chat, title: '选择聊天模型'),
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: const Text('获取聊天模型'),
                ),
              ),
              _field(imageKey, '图片 API Key（可留空）'),
              _field(imageBase, '图片 Base URL（可留空）'),
              _field(image, '文生图模型'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _fetchAndFillModel(key: key, base: base, imageKey: imageKey, imageBase: imageBase, target: image, title: '选择文生图模型', useImageProvider: true),
                  icon: const Icon(Icons.image_search_rounded),
                  label: const Text('获取图片模型'),
                ),
              ),
              _field(edit, '图生图模型'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _fetchAndFillModel(key: key, base: base, imageKey: imageKey, imageBase: imageBase, target: edit, title: '选择图生图模型', useImageProvider: true),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('获取图生图模型'),
                ),
              ),
            ]),
          ),""",
)

print('Config/model patch applied.')
