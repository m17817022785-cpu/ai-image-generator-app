from pathlib import Path

HOME = Path('lib/screens/home_screen.dart')
text = HOME.read_text(encoding='utf-8')


def patch(old: str, new: str, name: str) -> None:
    global text
    if new in text:
        print(f'already patched: {name}')
        return
    if old not in text:
        print(f'skip missing pattern: {name}')
        return
    text = text.replace(old, new)
    print(f'patched: {name}')

patch(
    "  String _baseUrl = 'https://api.openai.com/v1';\n  String _imageBaseUrl = '';\n  String _chatModel = 'gpt-4o-mini';\n  String _imageModel = 'dall-e-3';\n  String _imageEditModel = 'gpt-image-1';",
    "  String _baseUrl = '';\n  String _imageBaseUrl = '';\n  String _chatModel = '';\n  String _imageModel = '';\n  String _imageEditModel = '';",
    'blank default fields',
)

patch(
    "        _baseUrl = s['baseUrl'] ?? 'https://api.openai.com/v1';\n        _imageBaseUrl = s['imageBaseUrl'] ?? '';\n        _chatModel = s['chatModel'] ?? 'gpt-4o-mini';\n        _imageModel = s['imageModel'] ?? 'dall-e-3';\n        _imageEditModel = s['imageEditModel'] ?? 'gpt-image-1';",
    "        _baseUrl = s['baseUrl'] ?? '';\n        _imageBaseUrl = s['imageBaseUrl'] ?? '';\n        _chatModel = s['chatModel'] ?? '';\n        _imageModel = s['imageModel'] ?? '';\n        _imageEditModel = s['imageEditModel'] ?? '';",
    'blank loaded defaults',
)

patch(
    "                  _baseUrl = base.text.trim().isEmpty ? 'https://api.openai.com/v1' : base.text.trim();\n                  _imageBaseUrl = imageBase.text.trim();\n                  _chatModel = chat.text.trim().isEmpty ? 'gpt-4o-mini' : chat.text.trim();\n                  _imageModel = _api.normalizeImageModel(image.text.trim().isEmpty ? 'dall-e-3' : image.text.trim());\n                  _imageEditModel = _api.normalizeImageEditModel(edit.text.trim().isEmpty ? 'gpt-image-1' : edit.text.trim());",
    "                  _baseUrl = base.text.trim();\n                  _imageBaseUrl = imageBase.text.trim();\n                  _chatModel = chat.text.trim();\n                  _imageModel = image.text.trim();\n                  _imageEditModel = edit.text.trim();",
    'save exact user fields',
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

patch(
    "  Future<void> _openSettings() async {\n    final key = TextEditingController(text: _apiKey);",
    fetch_fn + "  Future<void> _openSettings() async {\n    final key = TextEditingController(text: _apiKey);",
    'insert fetch model helper',
)

patch(
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
    'expand settings dialog model buttons',
)

HOME.write_text(text, encoding='utf-8')
print('Config model home patch applied idempotently.')
