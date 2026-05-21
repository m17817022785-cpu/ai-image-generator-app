import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message.dart';
import '../services/api_service.dart';
import '../services/debug_log_service.dart';
import '../services/image_save_service.dart';
import '../services/settings_service.dart';
import 'debug_console_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _bgA = Color(0xFFF8F6FF);
  static const _bgB = Color(0xFFEAF1FF);
  static const _bgC = Color(0xFFF1ECFF);
  static const _glass = Color(0xDFFFFFFF);
  static const _primary = Color(0xFF756BFF);
  static const _primary2 = Color(0xFF58A6FF);
  static const _cyan = Color(0xFF5BC8D7);
  static const _text = Color(0xFF24213F);
  static const _muted = Color(0xFF746F91);
  static const _line = Color(0xFFE4DFFF);
  static const _soft = Color(0xFFF3F0FF);

  final _api = ApiService();
  final _settings = SettingsService();
  final _log = DebugLogService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Message> _messages = [];

  bool _loading = false;
  bool _forceImage = false;
  bool _enhanceImagePrompt = true;
  File? _attachedFile;
  String? _attachedBase64;

  String _apiKey = '';
  String _imageApiKey = '';
  String _baseUrl = 'https://api.openai.com/v1';
  String _imageBaseUrl = '';
  String _chatModel = 'gpt-4o-mini';
  String _imageModel = 'dall-e-3';
  String _imageEditModel = 'gpt-image-1';
  String _imageAspectRatio = '1:1';
  String _imageQuality = 'auto';

  static const _aspectOptions = ['1:1', '16:9', '9:16', '4:3', '3:4'];
  static const _qualityOptions = ['auto', 'standard', 'hd', 'low', 'medium', 'high'];

  String get _effectiveImageApiKey => _imageApiKey.trim().isEmpty ? _apiKey : _imageApiKey.trim();
  String get _effectiveImageBaseUrl => _imageBaseUrl.trim().isEmpty ? _baseUrl : _imageBaseUrl.trim();
  String get _effectiveImageModel => _api.normalizeImageModel(_imageModel);
  String get _effectiveImageEditModel => _api.normalizeImageEditModel(_imageEditModel);
  String get _selectedSize => _sizeForRatio(_imageAspectRatio);

  String _sizeForRatio(String ratio) => switch (ratio) {
        '16:9' => '1792x1024',
        '9:16' => '1024x1792',
        '4:3' => '1024x768',
        '3:4' => '768x1024',
        _ => '1024x1024',
      };

  String _qualityLabel(String value) => switch (value) {
        'standard' => '标准',
        'hd' => 'HD',
        'low' => '低',
        'medium' => '中',
        'high' => '高',
        _ => '自动',
      };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _settings.getSettings();
      if (!mounted) return;
      setState(() {
        _apiKey = s['apiKey'] ?? '';
        _imageApiKey = s['imageApiKey'] ?? '';
        _baseUrl = s['baseUrl'] ?? 'https://api.openai.com/v1';
        _imageBaseUrl = s['imageBaseUrl'] ?? '';
        _chatModel = s['chatModel'] ?? 'gpt-4o-mini';
        _imageModel = s['imageModel'] ?? 'dall-e-3';
        _imageEditModel = s['imageEditModel'] ?? 'gpt-image-1';
        _imageAspectRatio = _aspectOptions.contains(s['imageAspectRatio']) ? s['imageAspectRatio']! : '1:1';
        _imageQuality = _qualityOptions.contains(s['imageQuality']) ? s['imageQuality']! : 'auto';
        _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';
      });
    } catch (e) {
      _snack('读取设置失败：$e');
    }
  }

  Future<void> _saveAllSettings() => _settings.saveSettings(
        apiKey: _apiKey,
        imageApiKey: _imageApiKey,
        baseUrl: _baseUrl,
        imageBaseUrl: _imageBaseUrl,
        chatModel: _chatModel,
        imageModel: _imageModel,
        imageEditModel: _imageEditModel,
        imageAspectRatio: _imageAspectRatio,
        imageQuality: _imageQuality,
        enhanceImagePrompt: _enhanceImagePrompt,
      );

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;
    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _attachedFile = file;
      _attachedBase64 = base64Encode(bytes);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final file = _attachedFile;
    final b64 = _attachedBase64;
    if (text.isEmpty && file == null) return;
    if (_apiKey.trim().isEmpty) {
      _snack('请先配置聊天 API Key');
      return;
    }
    final content = text.isEmpty ? '请根据这张图片继续处理' : text;
    final user = Message(id: DateTime.now().microsecondsSinceEpoch.toString(), role: 'user', content: content, localFilePath: file?.path, base64Image: b64);
    setState(() {
      _messages.add(user);
      _input.clear();
      _attachedFile = null;
      _attachedBase64 = null;
      _loading = true;
    });
    _scrollBottom();
    _log.info('user_input', '用户发送消息', _forceImage ? '图片工具模式' : '自动模式', details: {'text': content, 'hasImage': file != null, 'aspectRatio': _imageAspectRatio, 'size': _selectedSize, 'quality': _imageQuality, 'enhanceImagePrompt': _enhanceImagePrompt});
    try {
      if (_forceImage) {
        await _replyImage(prompt: content, imageFile: file, base64Image: b64, quality: _imageQuality);
      } else {
        await _replyAuto(userMessage: user, imageFile: file, base64Image: b64);
      }
    } catch (e) {
      _log.error('send', '发送失败', e.toString());
      _snack('发送失败：$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _forceImage = false;
      });
      _scrollBottom();
    }
  }

  Future<void> _replyAuto({required Message userMessage, required File? imageFile, required String? base64Image}) async {
    final placeholder = _assistantPlaceholder('正在理解你的创作意图…');
    final decision = await _api.decideTool(userText: userMessage.content, base64Image: base64Image, apiKey: _apiKey, baseUrl: _baseUrl, model: _chatModel);
    if (decision.action == ToolAction.directAnswer) {
      placeholder.content = '';
      final stream = _api.generateChatStream(_messages.where((m) => m.id != placeholder.id).toList(), _apiKey, _baseUrl, _chatModel);
      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() => placeholder.content += chunk);
        _scrollBottom();
      }
      if (!mounted) return;
      setState(() {
        placeholder.content = placeholder.content.trim().isEmpty ? (decision.reply.isEmpty ? '我已经理解你的需求。' : decision.reply) : placeholder.content;
        placeholder.isGenerating = false;
      });
      return;
    }
    await _finishImageMessage(
      placeholder: placeholder,
      prompt: decision.prompt.isEmpty ? userMessage.content : decision.prompt,
      imageFile: decision.action == ToolAction.imageToImage ? imageFile : null,
      base64Image: base64Image,
      quality: _imageQuality == 'auto' ? decision.quality : _imageQuality,
    );
  }

  Future<void> _replyImage({required String prompt, required File? imageFile, required String? base64Image, required String quality}) async {
    final placeholder = _assistantPlaceholder(imageFile == null ? '正在构建画面…' : '正在分析参考图并生成新画面…');
    await _finishImageMessage(placeholder: placeholder, prompt: prompt, imageFile: imageFile, base64Image: base64Image, quality: quality);
  }

  Message _assistantPlaceholder(String text) {
    final msg = Message(id: '${DateTime.now().microsecondsSinceEpoch + 1}', role: 'assistant', content: text, isGenerating: true);
    setState(() => _messages.add(msg));
    _scrollBottom();
    return msg;
  }

  Future<void> _finishImageMessage({required Message placeholder, required String prompt, required File? imageFile, required String? base64Image, required String quality}) async {
    var finalPrompt = prompt;
    if (_enhanceImagePrompt) {
      if (mounted) setState(() => placeholder.content = '正在优化提示词与画面细节…');
      finalPrompt = await _api.refineImagePrompt(userText: prompt, base64Image: base64Image, apiKey: _apiKey, baseUrl: _baseUrl, model: _chatModel, aspectRatio: _imageAspectRatio, size: _selectedSize, quality: quality, isEdit: imageFile != null);
    }
    if (mounted) setState(() => placeholder.content = imageFile == null ? '正在生成 $_imageAspectRatio 画面…' : '正在编辑 $_imageAspectRatio 参考图…');
    final image = imageFile == null
        ? await _api.generateImage(finalPrompt, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageModel, size: _selectedSize, quality: quality)
        : await _api.editImage(finalPrompt, imageFile, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageEditModel, size: _selectedSize, quality: quality);
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == placeholder.id);
      if (index >= 0) _messages[index] = Message(id: placeholder.id, role: 'assistant', content: image, type: MessageType.image);
    });
  }

  Future<void> _saveImage(String url) async {
    try {
      _snack('正在保存图片…');
      await ImageSaveService.saveNetworkImage(url);
      _snack('图片已保存到相册');
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: _primary));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgA,
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Luna AI Studio', style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: .2)),
          SizedBox(height: 2),
          Text('Anime Image Generator', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .7)),
        ]),
        actions: [
          _roundIcon(Icons.terminal_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugConsoleScreen()))),
          _roundIcon(Icons.settings_rounded, _openSettings),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_bgA, _bgB, _bgC])),
        child: Stack(children: [
          const Positioned(top: -90, left: -70, child: _GlowBall(size: 220, color: Color(0x55756BFF))),
          const Positioned(top: 90, right: -90, child: _GlowBall(size: 240, color: Color(0x4458A6FF))),
          const Positioned(bottom: 90, left: -80, child: _GlowBall(size: 220, color: Color(0x33B7A8FF))),
          SafeArea(top: false, child: Column(children: [_studioHeader(), Expanded(child: _messages.isEmpty ? _emptyState() : _messageList()), if (_loading) const LinearProgressIndicator(color: _primary, backgroundColor: Color(0x22756BFF), minHeight: 2), _composer()])),
        ]),
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) => Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: IconButton(onPressed: onTap, icon: Icon(icon, color: _text), style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.72), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))));

  Widget _studioHeader() => _glassPanel(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        padding: const EdgeInsets.all(14),
        radius: 28,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_primary, _primary2]), boxShadow: [BoxShadow(color: _primary.withOpacity(.28), blurRadius: 22, offset: const Offset(0, 10))]), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_forceImage ? '图像创作模式' : '智能创作模式', style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)}画质', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700))])),
            _statusChip(),
          ]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _modeButton(Icons.auto_awesome, '自动', !_forceImage, () => setState(() => _forceImage = false))), const SizedBox(width: 8), Expanded(child: _modeButton(Icons.brush_rounded, '生图', _forceImage, () => setState(() => _forceImage = true))), const SizedBox(width: 8), Expanded(child: _modeButton(Icons.add_photo_alternate_rounded, '参考图', _attachedFile != null, _pickImage))]),
          const SizedBox(height: 10),
          InkWell(onTap: _openImageParams, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(.58), borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)), child: Row(children: [const Icon(Icons.tune_rounded, color: _primary), const SizedBox(width: 8), Expanded(child: Text('图片参数 · $_imageAspectRatio · ${_qualityLabel(_imageQuality)} · ${_enhanceImagePrompt ? '润色开' : '润色关'}', style: const TextStyle(color: _text, fontWeight: FontWeight.w900))), const Icon(Icons.keyboard_arrow_up_rounded, color: _muted)]))),
        ]),
      );

  Widget _statusChip() => InkWell(onTap: _openSettings, borderRadius: BorderRadius.circular(999), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: _apiKey.isEmpty ? const Color(0xFFFFF4D6) : const Color(0xFFE4FFFB), borderRadius: BorderRadius.circular(999), border: Border.all(color: _apiKey.isEmpty ? const Color(0xFFFFCC6A) : _cyan)), child: Text(_apiKey.isEmpty ? '未配置' : '已配置', style: TextStyle(color: _apiKey.isEmpty ? Colors.orange.shade900 : const Color(0xFF167A83), fontWeight: FontWeight.w900, fontSize: 12))));

  Widget _modeButton(IconData icon, String text, bool active, VoidCallback onTap) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(gradient: active ? const LinearGradient(colors: [_primary, _primary2]) : null, color: active ? null : Colors.white.withOpacity(0.58), borderRadius: BorderRadius.circular(18), border: Border.all(color: active ? Colors.white : _line)), child: Column(children: [Icon(icon, color: active ? Colors.white : _primary), const SizedBox(height: 4), Text(text, style: TextStyle(color: active ? Colors.white : _text, fontSize: 12, fontWeight: FontWeight.w900))])));

  Future<void> _openImageParams() async {
    await showModalBottomSheet<void>(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (ctx, sheetSetState) {
          Future<void> apply(Future<void> Function() fn) async {
            await fn();
            sheetSetState(() {});
            if (mounted) setState(() {});
          }
          return ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: Container(padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).padding.bottom + 18), decoration: BoxDecoration(color: Colors.white.withOpacity(.88), borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), border: Border.all(color: Colors.white.withOpacity(.7))), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                const Text('图片参数', style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('当前尺寸：$_selectedSize。比例会作为图片接口 size 参数传入。', style: const TextStyle(color: _muted, height: 1.35)),
                const SizedBox(height: 18),
                const Text('画面比例', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: _aspectOptions.map((v) => _choice(v, _imageAspectRatio == v, () => apply(() async { _imageAspectRatio = v; await _saveAllSettings(); }))).toList()),
                const SizedBox(height: 18),
                const Text('清晰度', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: _qualityOptions.map((v) => _choice(_qualityLabel(v), _imageQuality == v, () => apply(() async { _imageQuality = v; await _saveAllSettings(); }))).toList()),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('LLM 润色提示词后再生成', style: TextStyle(color: _text, fontWeight: FontWeight.w900)), subtitle: const Text('开启后会把比例、尺寸、画质一起交给聊天模型润色提示词', style: TextStyle(color: _muted)), activeColor: _primary, value: _enhanceImagePrompt, onChanged: (v) => apply(() async { _enhanceImagePrompt = v; await _saveAllSettings(); })),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.check_rounded), label: const Text('完成'), style: FilledButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))))),
              ]))));
        }));
  }

  Widget _choice(String label, bool active, VoidCallback onTap) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(999), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(gradient: active ? const LinearGradient(colors: [_primary, _primary2]) : null, color: active ? null : Colors.white.withOpacity(.68), borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? Colors.white : _line)), child: Text(label, style: TextStyle(color: active ? Colors.white : _text, fontWeight: FontWeight.w900))));

  Widget _emptyState() => ListView(padding: const EdgeInsets.all(24), children: const [SizedBox(height: 28), Icon(Icons.auto_awesome_rounded, color: _primary, size: 72), SizedBox(height: 10), Text('今天想创作什么？', textAlign: TextAlign.center, style: TextStyle(color: _text, fontSize: 25, fontWeight: FontWeight.w900)), SizedBox(height: 10), Text('描述角色、场景、画风与细节，或上传参考图进行二次创作。上方可调整画幅、清晰度和提示词润色。', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.55, fontWeight: FontWeight.w600)), SizedBox(height: 18), _PromptExample()]);

  Widget _messageList() => ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), itemCount: _messages.length, itemBuilder: (_, i) => _bubble(_messages[i]));

  Widget _bubble(Message msg) {
    final user = msg.role == 'user';
    return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86), margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: user ? const LinearGradient(colors: [_primary, _primary2]) : null, color: user ? null : Colors.white.withOpacity(.82), borderRadius: BorderRadius.only(topLeft: const Radius.circular(22), topRight: const Radius.circular(22), bottomLeft: Radius.circular(user ? 22 : 8), bottomRight: Radius.circular(user ? 8 : 22)), border: Border.all(color: user ? Colors.white.withOpacity(.55) : _line), boxShadow: [BoxShadow(color: _primary.withOpacity(0.10), blurRadius: 18, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (msg.type == MessageType.image) _imageMessage(msg.content) else MarkdownBody(data: msg.content.isEmpty && msg.isGenerating ? '●' : msg.content, styleSheet: MarkdownStyleSheet(p: TextStyle(color: user ? Colors.white : _text, height: 1.45, fontWeight: FontWeight.w600))), if (msg.localFilePath != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('参考图：${msg.localFilePath!.split('/').last}', style: TextStyle(color: user ? Colors.white70 : _muted, fontSize: 12)))])));
  }

  Widget _imageMessage(String url) {
    final isData = url.startsWith('data:image') && url.contains('base64,');
    final image = isData ? Image.memory(base64Decode(url.substring(url.indexOf('base64,') + 7)), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('图片解析失败', style: TextStyle(color: Colors.redAccent))) : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('图片加载失败', style: TextStyle(color: Colors.redAccent)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: BorderRadius.circular(20), child: image), const SizedBox(height: 10), if (!isData) FilledButton.icon(onPressed: () => _saveImage(url), icon: const Icon(Icons.download_rounded), label: const Text('保存图片'), style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))) else const Text('base64 图片已直接显示', style: TextStyle(color: _muted, fontSize: 12))]);
  }

  Widget _composer() => _glassPanel(margin: const EdgeInsets.fromLTRB(12, 4, 12, 12), padding: const EdgeInsets.all(10), radius: 28, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_attachedFile != null) Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0xFFEFFFFD), borderRadius: BorderRadius.circular(18), border: Border.all(color: _cyan.withOpacity(.8))), child: ListTile(dense: true, leading: const Icon(Icons.image_rounded, color: _cyan), title: Text(_attachedFile!.path.split('/').last, style: const TextStyle(color: _text, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis), trailing: IconButton(onPressed: () => setState(() { _attachedFile = null; _attachedBase64 = null; }), icon: const Icon(Icons.close, color: _primary)))),
        Row(children: [_smallButton(Icons.add_photo_alternate_rounded, _pickImage, _cyan), const SizedBox(width: 6), _smallButton(_forceImage ? Icons.brush_rounded : Icons.auto_awesome_outlined, () => setState(() => _forceImage = !_forceImage), _forceImage ? _primary : _primary2), const SizedBox(width: 6), Expanded(child: TextField(controller: _input, style: const TextStyle(color: _text, fontWeight: FontWeight.w700), minLines: 1, maxLines: 5, decoration: InputDecoration(hintText: _forceImage ? '描述要生成或编辑的画面…' : '输入聊天内容，或描述想生成的图片…', hintStyle: const TextStyle(color: _muted), filled: true, fillColor: Colors.white.withOpacity(.68), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)))), const SizedBox(width: 6), _smallButton(Icons.arrow_upward_rounded, _loading ? null : _send, _primary)]),
      ]));

  Widget _smallButton(IconData icon, VoidCallback? onTap, Color color) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17), child: Container(width: 46, height: 46, decoration: BoxDecoration(gradient: onTap == null ? null : LinearGradient(colors: [color, color == _primary ? _primary2 : color.withOpacity(.78)]), color: onTap == null ? Colors.grey.shade300 : null, borderRadius: BorderRadius.circular(17), boxShadow: onTap == null ? null : [BoxShadow(color: color.withOpacity(.22), blurRadius: 14, offset: const Offset(0, 7))]), child: Icon(icon, color: Colors.white)));

  Widget _glassPanel({required EdgeInsets margin, required EdgeInsets padding, required double radius, required Widget child}) => ClipRRect(borderRadius: BorderRadius.circular(radius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: Container(margin: margin, padding: padding, decoration: BoxDecoration(color: _glass, borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.white.withOpacity(.72), width: 1.4), boxShadow: [BoxShadow(color: _primary.withOpacity(0.13), blurRadius: 26, offset: const Offset(0, 12))]), child: child)));

  Future<void> _openSettings() async {
    final key = TextEditingController(text: _apiKey);
    final imageKey = TextEditingController(text: _imageApiKey);
    final base = TextEditingController(text: _baseUrl);
    final imageBase = TextEditingController(text: _imageBaseUrl);
    final chat = TextEditingController(text: _chatModel);
    final image = TextEditingController(text: _imageModel);
    final edit = TextEditingController(text: _imageEditModel);
    try {
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.white.withOpacity(.96), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)), title: const Text('API 配置', style: TextStyle(color: _text, fontWeight: FontWeight.w900)), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [_field(key, '聊天 API Key'), _field(base, '聊天 Base URL'), _field(chat, '聊天模型'), _field(imageKey, '图片 API Key（可留空）'), _field(imageBase, '图片 Base URL（可留空）'), _field(image, '文生图模型'), _field(edit, '图生图模型')])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: _primary), onPressed: () async { setState(() { _apiKey = key.text.trim(); _imageApiKey = imageKey.text.trim(); _baseUrl = base.text.trim().isEmpty ? 'https://api.openai.com/v1' : base.text.trim(); _imageBaseUrl = imageBase.text.trim(); _chatModel = chat.text.trim().isEmpty ? 'gpt-4o-mini' : chat.text.trim(); _imageModel = _api.normalizeImageModel(image.text.trim().isEmpty ? 'dall-e-3' : image.text.trim()); _imageEditModel = _api.normalizeImageEditModel(edit.text.trim().isEmpty ? 'gpt-image-1' : edit.text.trim()); }); await _saveAllSettings(); if (mounted) Navigator.pop(ctx); _snack('设置已保存'); }, child: const Text('保存'))]));
    } finally {
      key.dispose(); imageKey.dispose(); base.dispose(); imageBase.dispose(); chat.dispose(); image.dispose(); edit.dispose();
    }
  }

  Widget _field(TextEditingController c, String label) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, style: const TextStyle(color: _text, fontWeight: FontWeight.w700), decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: _muted), filled: true, fillColor: _soft, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _primary, width: 2)))));
}

class _GlowBall extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBall({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => IgnorePointer(child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 70, spreadRadius: 20)])));
}

class _PromptExample extends StatelessWidget {
  const _PromptExample();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(.72), borderRadius: BorderRadius.circular(22), border: Border.all(color: _HomeScreenState._line)), child: const Text('示例：银发少女，夜晚城市天台，蓝紫色光影，精致动漫插画风，电影感构图。', textAlign: TextAlign.center, style: TextStyle(color: _HomeScreenState._muted, height: 1.5, fontWeight: FontWeight.w700)));
}
