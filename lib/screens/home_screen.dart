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
  bool _studioHeaderCollapsed = false;
  int _imageCount = 1;
  final List<File> _attachedFiles = [];
  final List<String> _attachedBase64Images = [];

  String _apiKey = '';
  String _imageApiKey = '';
  String _baseUrl = '';
  String _imageBaseUrl = '';
  String _chatModel = '';
  String _imageModel = '';
  String _imageEditModel = '';
  String _imageAspectRatio = '1:1';
  String _imageQuality = 'auto';

  static const _aspectOptions = ['1:1', '16:9', '9:16', '4:3', '3:4'];
  static const _qualityOptions = ['auto', 'standard', 'hd', 'low', 'medium', 'high'];
  static const _imageCountOptions = [1, 2, 3, 4];
  static const _maxReferenceImages = 8;

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
        _baseUrl = s['baseUrl'] ?? '';
        _imageBaseUrl = s['imageBaseUrl'] ?? '';
        _chatModel = s['chatModel'] ?? '';
        _imageModel = s['imageModel'] ?? '';
        _imageEditModel = s['imageEditModel'] ?? '';
        _imageAspectRatio = _aspectOptions.contains(s['imageAspectRatio']) ? s['imageAspectRatio']! : '1:1';
        _imageQuality = _qualityOptions.contains(s['imageQuality']) ? s['imageQuality']! : 'auto';
        _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';
        _imageCount = int.tryParse(s['imageCount'] ?? '1')?.clamp(1, 4).toInt() ?? 1;
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
        imageCount: _imageCount,
      );

  Future<void> _pickImage() async {
    final remaining = _maxReferenceImages - _attachedFiles.length;
    if (remaining <= 0) {
      _snack('最多支持 $_maxReferenceImages 张参考图，请先删除部分图片。');
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;
    final files = <File>[];
    final images = <String>[];
    for (final item in picked.take(remaining)) {
      final file = File(item.path);
      files.add(file);
      images.add(base64Encode(await file.readAsBytes()));
    }
    if (!mounted) return;
    setState(() {
      _attachedFiles.addAll(files);
      _attachedBase64Images.addAll(images);
    });
    if (picked.length > remaining) _snack('最多支持 $_maxReferenceImages 张参考图，已添加前 $remaining 张。');
  }

  void _removeAttachedImage(int index) {
    if (index < 0 || index >= _attachedFiles.length) return;
    setState(() {
      _attachedFiles.removeAt(index);
      if (index < _attachedBase64Images.length) _attachedBase64Images.removeAt(index);
    });
  }

  void _clearAttachedImages() {
    setState(() {
      _attachedFiles.clear();
      _attachedBase64Images.clear();
    });
  }

  Future<void> _send() async {
    _setStudioHeaderCollapsed(true);
    final text = _input.text.trim();
    final files = List<File>.from(_attachedFiles);
    final b64s = List<String>.from(_attachedBase64Images);
    if (text.isEmpty && files.isEmpty) return;
    if (_apiKey.trim().isEmpty) {
      _snack('请先配置聊天 API Key');
      return;
    }
    final content = text.isEmpty ? (files.length > 1 ? '请根据这些图片继续处理' : '请根据这张图片继续处理') : text;
    final user = Message(id: DateTime.now().microsecondsSinceEpoch.toString(), role: 'user', content: content, localFilePaths: files.map((e) => e.path).toList(), base64Images: b64s);
    setState(() {
      _messages.add(user);
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = true;
    });
    _scrollBottom();
    _log.info('user_input', '用户发送消息', _forceImage ? '图片工具模式' : '自动模式', details: {'text': content, 'referenceImageCount': files.length, 'generateImageCount': _imageCount, 'aspectRatio': _imageAspectRatio, 'size': _selectedSize, 'quality': _imageQuality, 'enhanceImagePrompt': _enhanceImagePrompt});
    try {
      if (_forceImage) {
        await _replyImage(prompt: content, imageFiles: files, base64Images: b64s, quality: _imageQuality);
      } else {
        await _replyAuto(userMessage: user, imageFiles: files, base64Images: b64s);
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

  Future<void> _replyAuto({required Message userMessage, required List<File> imageFiles, required List<String> base64Images}) async {
    final placeholder = _assistantPlaceholder('正在理解你的创作意图…');
    final decision = await _api.decideTool(userText: userMessage.content, base64Image: null, base64Images: base64Images, apiKey: _apiKey, baseUrl: _baseUrl, model: _chatModel);
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
      imageFiles: decision.action == ToolAction.imageToImage ? imageFiles : const <File>[],
      base64Images: decision.action == ToolAction.imageToImage ? base64Images : const <String>[],
      quality: _imageQuality == 'auto' ? decision.quality : _imageQuality,
    );
  }

  Future<void> _replyImage({required String prompt, required List<File> imageFiles, required List<String> base64Images, required String quality}) async {
    final placeholder = _assistantPlaceholder(imageFiles.isEmpty ? '正在构建画面…' : '正在读取参考图并生成新画面…');
    await _finishImageMessage(placeholder: placeholder, prompt: prompt, imageFiles: imageFiles, base64Images: base64Images, quality: quality);
  }

  Message _assistantPlaceholder(String text) {
    final msg = Message(id: '${DateTime.now().microsecondsSinceEpoch + 1}', role: 'assistant', content: text, isGenerating: true);
    setState(() => _messages.add(msg));
    _scrollBottom();
    return msg;
  }

  Future<void> _finishImageMessage({required Message placeholder, required String prompt, required List<File> imageFiles, required List<String> base64Images, required String quality}) async {
    var finalPrompt = prompt;
    if (_enhanceImagePrompt) {
      if (mounted) setState(() => placeholder.content = '正在优化提示词与画面细节…');
      finalPrompt = await _api.refineImagePrompt(userText: prompt, base64Image: null, base64Images: base64Images, apiKey: _apiKey, baseUrl: _baseUrl, model: _chatModel, aspectRatio: _imageAspectRatio, size: _selectedSize, quality: quality, isEdit: imageFiles.isNotEmpty);
    }
    final total = _imageCount.clamp(1, 4).toInt();
    final generated = <String>[];
    try {
      for (var i = 0; i < total; i++) {
        if (mounted) setState(() => placeholder.content = imageFiles.isEmpty ? '正在生成第 ${i + 1} / $total 张 $_imageAspectRatio 画面…' : '正在参考 ${imageFiles.length} 张图生成第 ${i + 1} / $total 张 $_imageAspectRatio 画面…');
        final image = imageFiles.isEmpty
            ? await _api.generateImage(finalPrompt, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageModel, size: _selectedSize, quality: quality)
            : await _api.editImages(finalPrompt, imageFiles, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageEditModel, size: _selectedSize, quality: quality);
        generated.add(image);
        if (!mounted) return;
        setState(() {
          if (i == 0) {
            final index = _messages.indexWhere((m) => m.id == placeholder.id);
            if (index >= 0) _messages[index] = Message(id: placeholder.id, role: 'assistant', content: image, type: MessageType.image);
          } else {
            _messages.add(Message(id: '${DateTime.now().microsecondsSinceEpoch + i}', role: 'assistant', content: image, type: MessageType.image));
          }
        });
        _scrollBottom();
      }
      if (generated.length > 1) _snack('已生成 ${generated.length} 张图片');
    } catch (e) {
      if (generated.isNotEmpty) {
        _snack('已生成 ${generated.length} / $total 张，后续生成失败：$e');
        return;
      }
      rethrow;
    }
  }

  Future<void> _saveImage(String url) async {
    try {
      _snack('正在保存图片…');
      await ImageSaveService.saveImage(url);
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

  void _startNewSession() {
    setState(() {
      _messages.clear();
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = false;
      _forceImage = false;
      _studioHeaderCollapsed = false;
    });
    _snack('已开启新会话');
  }

  Future<void> _confirmNewSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开新会话'),
        content: const Text('清空当前聊天记录、输入内容和参考图？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始')),
        ],
      ),
    );
    if (ok == true) _startNewSession();
  }

  void _setStudioHeaderCollapsed(bool value) {
    if (_studioHeaderCollapsed != value) setState(() => _studioHeaderCollapsed = value);
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
          _roundIcon(Icons.add_comment_rounded, _confirmNewSession),
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
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_forceImage ? '图像创作模式' : '智能创作模式', style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 2), InkWell(onTap: () => _setStudioHeaderCollapsed(!_studioHeaderCollapsed), child: Text(_studioHeaderCollapsed ? '展开创作面板' : '收起创作面板', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w800))), const SizedBox(height: 4), Text('画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)}画质 · $_imageCount 张', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700))])),
            _statusChip(),
          ]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _modeButton(Icons.auto_awesome, '自动', !_forceImage, () => setState(() => _forceImage = false))), const SizedBox(width: 8), Expanded(child: _modeButton(Icons.brush_rounded, '生图', _forceImage, () => setState(() => _forceImage = true))), const SizedBox(width: 8), Expanded(child: _modeButton(Icons.add_photo_alternate_rounded, '参考图', _attachedFiles.isNotEmpty, _pickImage))]),
          const SizedBox(height: 10),
          InkWell(onTap: _openImageParams, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(.58), borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)), child: Row(children: [const Icon(Icons.tune_rounded, color: _primary), const SizedBox(width: 8), Expanded(child: Text('图片参数 · $_imageAspectRatio · ${_qualityLabel(_imageQuality)} · $_imageCount 张 · ${_enhanceImagePrompt ? '润色开' : '润色关'}', style: const TextStyle(color: _text, fontWeight: FontWeight.w900))), const Icon(Icons.keyboard_arrow_up_rounded, color: _muted)]))),
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
                const SizedBox(height: 18),
                const Text('生成数量', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: _imageCountOptions.map((v) => _choice('$v 张', _imageCount == v, () => apply(() async { _imageCount = v; await _saveAllSettings(); }))).toList()),
                const SizedBox(height: 6),
                const Text('选择多张时会自动连续生成，并保留已成功的图片。', style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
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
    return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86), margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: user ? const LinearGradient(colors: [_primary, _primary2]) : null, color: user ? null : Colors.white.withOpacity(.82), borderRadius: BorderRadius.only(topLeft: const Radius.circular(22), topRight: const Radius.circular(22), bottomLeft: Radius.circular(user ? 22 : 8), bottomRight: Radius.circular(user ? 8 : 22)), border: Border.all(color: user ? Colors.white.withOpacity(.55) : _line), boxShadow: [BoxShadow(color: _primary.withOpacity(0.10), blurRadius: 18, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (msg.type == MessageType.image) _imageMessage(msg.content) else MarkdownBody(data: msg.content.isEmpty && msg.isGenerating ? '●' : msg.content, styleSheet: MarkdownStyleSheet(p: TextStyle(color: user ? Colors.white : _text, height: 1.45, fontWeight: FontWeight.w600))), if (msg.effectiveLocalFilePaths.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('参考图：${msg.effectiveLocalFilePaths.length} 张', style: TextStyle(color: user ? Colors.white70 : _muted, fontSize: 12)))])));
  }

  Widget _attachedPreviewStrip() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFEFFFFD), borderRadius: BorderRadius.circular(18), border: Border.all(color: _cyan.withOpacity(.8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.image_rounded, color: _cyan), const SizedBox(width: 8), Expanded(child: Text('参考图 ${_attachedFiles.length} / $_maxReferenceImages，可继续追加或单张删除', style: const TextStyle(color: _text, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)), TextButton(onPressed: _clearAttachedImages, child: const Text('清空'))]),
          const SizedBox(height: 6),
          SizedBox(height: 78, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _attachedFiles.length + (_attachedFiles.length < _maxReferenceImages ? 1 : 0), separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) {
            if (i == _attachedFiles.length) return InkWell(onTap: _pickImage, borderRadius: BorderRadius.circular(16), child: Container(width: 74, decoration: BoxDecoration(color: Colors.white.withOpacity(.72), borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)), child: const Icon(Icons.add_photo_alternate_rounded, color: _primary)));
            return Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_attachedFiles[i], width: 74, height: 78, fit: BoxFit.cover)), Positioned(top: 3, right: 3, child: InkWell(onTap: () => _removeAttachedImage(i), child: Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.black.withOpacity(.55), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 16))))]);
          })),
        ]),
      );

  Widget _imageMessage(String url) {
    final isData = url.startsWith('data:image') && url.contains('base64,');
    final image = isData ? Image.memory(base64Decode(url.substring(url.indexOf('base64,') + 7)), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('图片解析失败', style: TextStyle(color: Colors.redAccent))) : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('图片加载失败', style: TextStyle(color: Colors.redAccent)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: BorderRadius.circular(20), child: image), const SizedBox(height: 10), FilledButton.icon(onPressed: () => _saveImage(url), icon: const Icon(Icons.download_rounded), label: const Text('保存图片'), style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))), if (isData) const Padding(padding: EdgeInsets.only(top: 6), child: Text('base64 图片已直接显示，可保存到相册', style: TextStyle(color: _muted, fontSize: 12)))]);
  }

  Widget _composer() => _glassPanel(margin: const EdgeInsets.fromLTRB(12, 4, 12, 12), padding: const EdgeInsets.all(10), radius: 28, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_attachedFiles.isNotEmpty) _attachedPreviewStrip(),
        Row(children: [_smallButton(Icons.add_photo_alternate_rounded, _pickImage, _cyan), const SizedBox(width: 6), _smallButton(_forceImage ? Icons.brush_rounded : Icons.auto_awesome_outlined, () => setState(() => _forceImage = !_forceImage), _forceImage ? _primary : _primary2), const SizedBox(width: 6), Expanded(child: TextField(controller: _input, style: const TextStyle(color: _text, fontWeight: FontWeight.w700), minLines: 1, maxLines: 5, decoration: InputDecoration(hintText: _forceImage ? '描述要生成或编辑的画面…' : '输入聊天内容，或描述想生成的图片…', hintStyle: const TextStyle(color: _muted), filled: true, fillColor: Colors.white.withOpacity(.68), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)))), const SizedBox(width: 6), _smallButton(Icons.arrow_upward_rounded, _loading ? null : _send, _primary)]),
      ]));

  Widget _smallButton(IconData icon, VoidCallback? onTap, Color color) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17), child: Container(width: 46, height: 46, decoration: BoxDecoration(gradient: onTap == null ? null : LinearGradient(colors: [color, color == _primary ? _primary2 : color.withOpacity(.78)]), color: onTap == null ? Colors.grey.shade300 : null, borderRadius: BorderRadius.circular(17), boxShadow: onTap == null ? null : [BoxShadow(color: color.withOpacity(.22), blurRadius: 14, offset: const Offset(0, 7))]), child: Icon(icon, color: Colors.white)));

  Widget _glassPanel({required EdgeInsets margin, required EdgeInsets padding, required double radius, required Widget child}) => ClipRRect(borderRadius: BorderRadius.circular(radius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: Container(margin: margin, padding: padding, decoration: BoxDecoration(color: _glass, borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.white.withOpacity(.72), width: 1.4), boxShadow: [BoxShadow(color: _primary.withOpacity(0.13), blurRadius: 26, offset: const Offset(0, 12))]), child: child)));

  Future<void> _fetchAndFillModel({
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

  Future<void> _openSettings() async {
    final key = TextEditingController(text: _apiKey);
    final imageKey = TextEditingController(text: _imageApiKey);
    final base = TextEditingController(text: _baseUrl);
    final imageBase = TextEditingController(text: _imageBaseUrl);
    final chat = TextEditingController(text: _chatModel);
    final image = TextEditingController(text: _imageModel);
    final edit = TextEditingController(text: _imageEditModel);
    try {
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.white.withOpacity(.96), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)), title: const Text('API 配置', style: TextStyle(color: _text, fontWeight: FontWeight.w900)), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
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
  _field(edit, '图生图模型'),
  Align(
    alignment: Alignment.centerRight,
    child: Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: () => _fetchAndFillModel(key: key, base: base, target: image, title: '选择文生图模型', imageKey: imageKey, imageBase: imageBase, useImageProvider: true),
          icon: const Icon(Icons.image_search_rounded),
          label: const Text('获取文生图模型'),
        ),
        TextButton.icon(
          onPressed: () => _fetchAndFillModel(key: key, base: base, target: edit, title: '选择图生图模型', imageKey: imageKey, imageBase: imageBase, useImageProvider: true),
          icon: const Icon(Icons.auto_fix_high_rounded),
          label: const Text('获取图生图模型'),
        ),
      ],
    ),
  ),
])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(style: FilledButton.styleFrom(backgroundColor: _primary), onPressed: () async { setState(() { _apiKey = key.text.trim(); _imageApiKey = imageKey.text.trim(); _baseUrl = base.text.trim().isEmpty ? 'https://api.openai.com/v1' : base.text.trim(); _imageBaseUrl = imageBase.text.trim(); _chatModel = chat.text.trim().isEmpty ? 'gpt-4o-mini' : chat.text.trim(); _imageModel = _api.normalizeImageModel(image.text.trim().isEmpty ? 'dall-e-3' : image.text.trim()); _imageEditModel = _api.normalizeImageEditModel(edit.text.trim().isEmpty ? 'gpt-image-1' : edit.text.trim()); }); await _saveAllSettings(); if (mounted) Navigator.pop(ctx); _snack('设置已保存'); }, child: const Text('保存'))]));
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
