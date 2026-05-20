import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message.dart';
import '../services/api_service.dart';
import '../services/image_save_service.dart';
import '../services/settings_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _bgTop = Color(0xFF111827);
  static const _bgBottom = Color(0xFF050816);
  static const _surface = Color(0xFF182033);
  static const _surface2 = Color(0xFF222B3F);
  static const _primary = Color(0xFF7C3AED);
  static const _secondary = Color(0xFF06B6D4);
  static const _success = Color(0xFF10B981);
  static const _text = Color(0xFFF8FAFC);
  static const _muted = Color(0xFFCBD5E1);

  final _apiService = ApiService();
  final _settingsService = SettingsService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Message> _messages = [];

  bool _isLoading = false;
  bool _forceImage = false;
  File? _attachedFile;
  String? _attachedBase64;

  String _apiKey = '';
  String _imageApiKey = '';
  String _baseUrl = 'https://api.openai.com/v1';
  String _imageBaseUrl = '';
  String _chatModel = 'gpt-4o-mini';
  String _imageModel = 'dall-e-3';

  String get _effectiveImageApiKey => _imageApiKey.trim().isEmpty ? _apiKey : _imageApiKey.trim();
  String get _effectiveImageBaseUrl => _imageBaseUrl.trim().isEmpty ? _baseUrl : _imageBaseUrl.trim();
  String get _effectiveImageModel => _apiService.normalizeImageModel(_imageModel);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.getSettings();
      if (!mounted) return;
      setState(() {
        _apiKey = settings['apiKey'] ?? '';
        _imageApiKey = settings['imageApiKey'] ?? '';
        _baseUrl = settings['baseUrl'] ?? 'https://api.openai.com/v1';
        _imageBaseUrl = settings['imageBaseUrl'] ?? '';
        _chatModel = settings['chatModel'] ?? 'gpt-4o-mini';
        _imageModel = settings['imageModel'] ?? 'dall-e-3';
      });
    } catch (e) {
      _snack('读取设置失败: $e');
    }
  }

  bool _isImagePrompt(String text) {
    final value = text.trim().toLowerCase();
    if (value.isEmpty) return false;
    const prefixes = [
      '/image', '/img', '/draw', '画图', '绘图', '生图', '生成图片', '生成一张', '帮我画', '画一张',
      '做一张图', '出一张图', 'create an image', 'generate an image', 'draw '
    ];
    if (prefixes.any(value.startsWith)) return true;
    const imageWords = ['图片', '图像', '插画', '海报', '头像', '壁纸', 'logo', 'poster', 'illustration', 'wallpaper'];
    const actionWords = ['生成', '画', '绘制', '设计', 'create', 'generate', 'draw', 'design'];
    return imageWords.any(value.contains) && actionWords.any(value.contains);
  }

  String _cleanImagePrompt(String text) {
    var prompt = text.trim();
    const prefixes = ['/image', '/img', '/draw', '画图', '绘图', '生图', '生成图片'];
    for (final prefix in prefixes) {
      if (prompt.toLowerCase().startsWith(prefix.toLowerCase())) {
        prompt = prompt.substring(prefix.length).trimLeft();
        if (prompt.startsWith(':') || prompt.startsWith('：')) prompt = prompt.substring(1).trimLeft();
        break;
      }
    }
    return prompt.isEmpty ? text.trim() : prompt;
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty && _attachedFile == null) return;
    if (_apiKey.isEmpty) {
      _snack('请先在设置中配置 API Key');
      return;
    }

    final shouldImage = _attachedFile == null && (_forceImage || _isImagePrompt(text));
    final content = shouldImage ? _cleanImagePrompt(text) : (text.isEmpty ? '请分析这张图片' : text);
    final userMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: content,
      localFilePath: _attachedFile?.path,
      base64Image: _attachedBase64,
    );

    setState(() {
      _messages.add(userMessage);
      _inputController.clear();
      _attachedFile = null;
      _attachedBase64 = null;
      _forceImage = false;
      _isLoading = true;
    });
    _scrollBottom();

    try {
      if (shouldImage) {
        await _replyImage(content);
      } else {
        await _replyChat(userMessage);
      }
    } catch (e) {
      _snack('发送失败: $e');
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _scrollBottom();
    }
  }

  Future<void> _replyImage(String prompt) async {
    final placeholder = Message(
      id: '${DateTime.now().millisecondsSinceEpoch + 1}',
      role: 'assistant',
      content: '正在根据你的描述生成图片…',
      isGenerating: true,
    );
    setState(() => _messages.add(placeholder));
    _scrollBottom();

    final url = await _apiService.generateImage(prompt, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageModel);
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == placeholder.id);
      if (index >= 0) {
        _messages[index] = Message(id: placeholder.id, role: 'assistant', content: url, type: MessageType.image);
      }
    });
  }

  Future<void> _replyChat(Message userMessage) async {
    final assistant = Message(
      id: '${DateTime.now().millisecondsSinceEpoch + 1}',
      role: 'assistant',
      content: '',
      isGenerating: true,
    );
    setState(() => _messages.add(assistant));
    _scrollBottom();

    final model = _apiService.normalizeChatModel(_chatModel);
    final stream = _apiService.generateChatStream(_messages.sublist(0, _messages.length - 1), _apiKey, _baseUrl, model);
    await for (final chunk in stream) {
      if (!mounted) return;
      setState(() => assistant.content += chunk);
      _scrollBottom();
    }
    if (!mounted) return;
    setState(() => assistant.isGenerating = false);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _attachedFile = File(picked.path);
      _attachedBase64 = base64Encode(bytes);
      _forceImage = false;
    });
  }

  Future<void> _saveImage(String url) async {
    try {
      _snack('正在保存图片...');
      await ImageSaveService.saveNetworkImage(url);
      _snack('图片已保存到相册');
    } catch (e) {
      _snack('保存失败: $e');
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: _bgBottom,
      appBar: AppBar(
        titleSpacing: 18,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            _gradientBox(child: const Icon(Icons.auto_awesome, color: Colors.white, size: 19), size: 34, radius: 12),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Luna AI', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Chat · Vision · Image', style: TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          _topButton(Icons.delete_outline, _confirmClear),
          const SizedBox(width: 6),
          _topButton(Icons.settings_rounded, _openSettings),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_bgTop, _bgBottom]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _heroPanel(),
              Expanded(child: _messages.isEmpty ? _emptyState() : _messageList()),
              if (_isLoading) _loadingBar(),
              _composer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topButton(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: _text, size: 21),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withOpacity(0.08))),
          ),
        ),
      );

  Widget _heroPanel() => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: _glassDecoration(24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _forceImage ? '画图模式已开启，下一条将生成图片' : '聊天与生图已合并，像聊天一样创作',
                    style: const TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                _pill(_apiKey.isEmpty ? Icons.key_off_rounded : Icons.verified_user_rounded, _apiKey.isEmpty ? '未配置' : '已配置',
                    _apiKey.isEmpty ? Colors.orangeAccent : _success, _openSettings),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _quick(Icons.chat_bubble_outline_rounded, '聊天', '直接提问', _secondary, () => setState(() => _forceImage = false))),
                const SizedBox(width: 10),
                Expanded(child: _quick(Icons.brush_rounded, '生图', '描述画面', _primary, () => setState(() => _forceImage = true))),
                const SizedBox(width: 10),
                Expanded(child: _quick(Icons.image_search_rounded, '看图', '上传分析', _success, _pickImage)),
              ],
            ),
          ],
        ),
      );

  Widget _quick(IconData icon, String title, String sub, Color color, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(color: _surface.withOpacity(0.72), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color, size: 19)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800)),
            Text(sub, style: const TextStyle(color: _muted, fontSize: 11)),
          ]),
        ),
      );

  Widget _emptyState() {
    final suggestions = ['总结一下今天的待办', '画一张星空下的未来城市', '帮我写一个短视频脚本'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_primary.withOpacity(0.20), _secondary.withOpacity(0.12)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(children: [
            _gradientBox(child: const Icon(Icons.auto_awesome, color: Colors.white, size: 38), size: 74, radius: 40),
            const SizedBox(height: 18),
            const Text('今天想创造什么？', textAlign: TextAlign.center, style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('同一个输入框即可聊天、生成图片、上传图片分析。', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 14, height: 1.5)),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded, color: _text),
              label: const Text('打开 API 设置', style: TextStyle(color: _text, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('试试这些灵感', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...suggestions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withOpacity(0.08))),
                tileColor: Colors.white.withOpacity(0.06),
                leading: const Icon(Icons.north_west_rounded, color: _muted, size: 18),
                title: Text(s, style: const TextStyle(color: _text, fontSize: 14)),
                onTap: () {
                  _inputController.text = s;
                  _inputController.selection = TextSelection.collapsed(offset: s.length);
                },
              ),
            )),
      ],
    );
  }

  Widget _messageList() => ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: _messages.length,
        itemBuilder: (_, index) => _messageBubble(_messages[index]),
      );

  Widget _messageBubble(Message msg) {
    final user = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!user) _avatar(false),
          if (!user) const SizedBox(width: 10),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              padding: EdgeInsets.all(msg.type == MessageType.image ? 10 : 14),
              decoration: BoxDecoration(
                gradient: user ? const LinearGradient(colors: [_primary, Color(0xFF5B21B6)]) : null,
                color: user ? null : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(user ? 22 : 6),
                  bottomRight: Radius.circular(user ? 6 : 22),
                ),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (msg.type == MessageType.image)
                  _imageMessage(msg.content)
                else
                  MarkdownBody(
                    data: msg.content.isEmpty && msg.isGenerating ? '●' : msg.content,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: _text, fontSize: 15.5, height: 1.5),
                      code: const TextStyle(color: Color(0xFFFBBF24), backgroundColor: Colors.black26),
                      codeblockDecoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                if (msg.localFilePath != null) _fileChip(msg.localFilePath!),
              ]),
            ),
          ),
          if (user) const SizedBox(width: 10),
          if (user) _avatar(true),
        ],
      ),
    );
  }

  Widget _avatar(bool user) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          gradient: user ? null : const LinearGradient(colors: [_secondary, _success]),
          color: user ? Colors.white.withOpacity(0.12) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(user ? Icons.person_rounded : Icons.auto_awesome, color: Colors.white, size: 18),
      );

  Widget _imageMessage(String url) {
    final isDataImage = url.startsWith('data:image') && url.contains('base64,');
    Widget image;
    if (isDataImage) {
      try {
        final b64 = url.substring(url.indexOf('base64,') + 'base64,'.length);
        image = Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Text('图片解析失败，请检查接口返回内容。', style: TextStyle(color: Colors.redAccent)),
        );
      } catch (_) {
        image = const Text('图片解析失败，请检查接口返回内容。', style: TextStyle(color: Colors.redAccent));
      }
    } else {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Text('图片加载失败，请检查网络连接或 API Key。', style: TextStyle(color: Colors.redAccent)),
        loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: _secondary))),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(18), child: image),
      const SizedBox(height: 10),
      if (!isDataImage)
        FilledButton.icon(
          onPressed: () => _saveImage(url),
          icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
          label: const Text('保存到相册', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(backgroundColor: _success),
        )
      else
        const Text('图片由接口以 base64 返回，已直接显示。', style: TextStyle(color: _muted, fontSize: 12)),
    ]);
  }

  Widget _fileChip(String path) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Chip(
          avatar: const Icon(Icons.image_rounded, color: _secondary, size: 15),
          label: Text(path.split('/').last, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontSize: 12)),
          backgroundColor: Colors.white.withOpacity(0.10),
          side: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
      );

  Widget _loadingBar() => const Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(999)), child: LinearProgressIndicator(minHeight: 3, color: _secondary, backgroundColor: Colors.white10)),
      );

  Widget _composer() => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _surface.withOpacity(0.96), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white10)),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_attachedFile != null) _attachmentPreview(),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _inputButton(Icons.add_photo_alternate_rounded, _secondary, _pickImage),
              const SizedBox(width: 6),
              _inputButton(_forceImage ? Icons.brush_rounded : Icons.brush_outlined, _forceImage ? _primary : _muted,
                  _attachedFile == null ? () => setState(() => _forceImage = !_forceImage) : null),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46, maxHeight: 138),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _forceImage ? _primary.withOpacity(0.42) : Colors.white10),
                  ),
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(color: _text, fontSize: 15),
                    cursorColor: _secondary,
                    decoration: InputDecoration(
                      hintText: _forceImage ? '描述你想生成的图片...' : '输入消息，或说“画一张…”',
                      hintStyle: const TextStyle(color: _muted, fontSize: 14),
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isLoading ? null : _send,
                child: _gradientBox(child: Icon(_isLoading ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded, color: Colors.white), size: 48, radius: 18),
              ),
            ]),
          ]),
        ),
      );

  Widget _inputButton(IconData icon, Color color, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: onTap == null ? Colors.white.withOpacity(0.04) : color.withOpacity(0.12), borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white10)),
          child: Icon(icon, color: onTap == null ? Colors.white24 : color, size: 21),
        ),
      );

  Widget _attachmentPreview() => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _success.withOpacity(0.10), borderRadius: BorderRadius.circular(18), border: Border.all(color: _success.withOpacity(0.28))),
        child: Row(children: [
          const Icon(Icons.image_rounded, color: _success),
          const SizedBox(width: 10),
          Expanded(child: Text('已选择待分析图片：${_attachedFile!.path.split('/').last}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text))),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
            onPressed: () => setState(() {
              _attachedFile = null;
              _attachedBase64 = null;
            }),
          ),
        ]),
      );

  Widget _pill(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.38))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 15), const SizedBox(width: 5), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12))]),
        ),
      );

  Widget _gradientBox({required Widget child, required double size, required double radius}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [_primary, _secondary]), borderRadius: BorderRadius.circular(radius)),
        child: Center(child: child),
      );

  BoxDecoration _glassDecoration(double radius) => BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 24, offset: const Offset(0, 12))],
      );

  void _confirmClear() {
    if (_messages.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('清空对话', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        content: const Text('确定要清空当前所有聊天记录吗？', style: TextStyle(color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: _muted))),
          TextButton(
            onPressed: () {
              setState(_messages.clear);
              Navigator.pop(dialogContext);
            },
            child: const Text('清空', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final settings = await _settingsService.getSettings();
      if (!mounted) return;
      await _showSettingsDialog(
        apiKey: settings['apiKey'] ?? _apiKey,
        imageApiKey: settings['imageApiKey'] ?? _imageApiKey,
        baseUrl: settings['baseUrl'] ?? _baseUrl,
        imageBaseUrl: settings['imageBaseUrl'] ?? _imageBaseUrl,
        chatModel: settings['chatModel'] ?? _chatModel,
        imageModel: settings['imageModel'] ?? _imageModel,
      );
    } catch (_) {
      if (!mounted) return;
      await _showSettingsDialog(apiKey: _apiKey, imageApiKey: _imageApiKey, baseUrl: _baseUrl, imageBaseUrl: _imageBaseUrl, chatModel: _chatModel, imageModel: _imageModel);
    }
  }

  Future<void> _showSettingsDialog({
    required String apiKey,
    required String imageApiKey,
    required String baseUrl,
    required String imageBaseUrl,
    required String chatModel,
    required String imageModel,
  }) async {
    final keyCtrl = TextEditingController(text: apiKey);
    final imageKeyCtrl = TextEditingController(text: imageApiKey);
    final urlCtrl = TextEditingController(text: baseUrl);
    final imageUrlCtrl = TextEditingController(text: imageBaseUrl);
    final chatCtrl = TextEditingController(text: chatModel);
    final imageCtrl = TextEditingController(text: imageModel);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          title: const Row(children: [Icon(Icons.settings_rounded, color: _secondary), SizedBox(width: 10), Text('API 配置参数', style: TextStyle(color: _text, fontWeight: FontWeight.w900))]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(keyCtrl, '聊天 API Key', 'sk-xxxx'),
              _field(imageKeyCtrl, '生图 API Key（可留空沿用聊天令牌）', 'sk-image-xxxx'),
              _field(urlCtrl, '聊天 Base URL', 'https://api.openai.com/v1'),
              _field(imageUrlCtrl, '生图 Base URL（可留空沿用聊天接口）', 'https://api.openai.com/v1'),
              _field(chatCtrl, '聊天模型', 'gpt-4o-mini'),
              _field(imageCtrl, '生图模型', 'dall-e-3 / gpt-image-1'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: _muted))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _primary),
              onPressed: () async {
                final newImageKey = imageKeyCtrl.text.trim();
                final newBase = urlCtrl.text.trim().isEmpty ? 'https://api.openai.com/v1' : urlCtrl.text.trim();
                final newImageBase = imageUrlCtrl.text.trim();
                final newChat = chatCtrl.text.trim().isEmpty ? 'gpt-4o-mini' : chatCtrl.text.trim();
                final rawImageModel = imageCtrl.text.trim().isEmpty ? 'dall-e-3' : imageCtrl.text.trim();
                final newImage = _apiService.normalizeImageModel(rawImageModel);
                await _settingsService.saveSettings(
                  apiKey: keyCtrl.text.trim(),
                  imageApiKey: newImageKey,
                  baseUrl: newBase,
                  imageBaseUrl: newImageBase,
                  chatModel: newChat,
                  imageModel: newImage,
                );
                if (!mounted) return;
                setState(() {
                  _apiKey = keyCtrl.text.trim();
                  _imageApiKey = newImageKey;
                  _baseUrl = newBase;
                  _imageBaseUrl = newImageBase;
                  _chatModel = newChat;
                  _imageModel = newImage;
                });
                Navigator.pop(dialogContext);
                final imageKeyTip = newImageKey.isEmpty ? '生图令牌沿用聊天令牌' : '聊天/生图令牌已分开';
                final imageUrlTip = newImageBase.isEmpty ? '生图接口沿用聊天接口' : '聊天/生图接口已分开';
                _snack('设置已保存，$imageKeyTip，$imageUrlTip');
              },
              child: const Text('保存修改', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    } finally {
      keyCtrl.dispose();
      imageKeyCtrl.dispose();
      urlCtrl.dispose();
      imageUrlCtrl.dispose();
      chatCtrl.dispose();
      imageCtrl.dispose();
    }
  }

  Widget _field(TextEditingController controller, String label, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          style: const TextStyle(color: _text),
          cursorColor: _secondary,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(color: _muted),
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.10))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _secondary)),
          ),
        ),
      );
}
