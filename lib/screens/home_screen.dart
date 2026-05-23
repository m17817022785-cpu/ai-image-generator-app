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
  static const _primary = Color(0xFF756BFF);
  static const _primary2 = Color(0xFF58A6FF);
  static const _cyan = Color(0xFF5BC8D7);
  static const _bg = Color(0xFFF8F6FF);
  static const _card = Color(0xEEFFFFFF);
  static const _text = Color(0xFF24213F);
  static const _muted = Color(0xFF746F91);
  static const _line = Color(0xFFE4DFFF);

  final _api = ApiService();
  final _settings = SettingsService();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final List<Message> _messages = [];
  final List<File> _attachedFiles = [];
  final List<String> _attachedBase64Images = [];
  List<ChatHistoryEntry> _history = [];
  String? _currentSessionId;

  bool _loading = false;
  bool _forceImage = false;
  bool _studioHeaderCollapsed = true;
  bool _enhanceImagePrompt = true;
  int _imageCount = 1;

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
  String get _selectedSize => switch (_imageAspectRatio) {
        '16:9' => '1792x1024',
        '9:16' => '1024x1792',
        '4:3' => '1024x768',
        '3:4' => '768x1024',
        _ => '1024x1024',
      };

  String _qualityLabel(String v) => switch (v) {
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
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
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
      _studioHeaderCollapsed = (s['studioHeaderCollapsed'] ?? 'true') == 'true';
      _imageCount = int.tryParse(s['imageCount'] ?? '1')?.clamp(1, 4).toInt() ?? 1;
    });
  }

  Future<void> _saveSettings() => _settings.saveSettings(
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
        studioHeaderCollapsed: _studioHeaderCollapsed,
      );

  Future<void> _loadHistory() async {
    final items = await _settings.getChatHistory();
    if (!mounted) return;
    setState(() => _history = items);
  }

  String _sessionTitle(List<Message> messages) {
    String? firstUser;
    for (final message in messages) {
      if (message.role == 'user' && message.content.trim().isNotEmpty) {
        firstUser = message.content.trim();
        break;
      }
    }
    final raw = firstUser ?? (messages.any((m) => m.type == MessageType.image) ? '图片创作会话' : '未命名会话');
    return raw.length > 22 ? '${raw.substring(0, 22)}…' : raw;
  }

  Future<void> _persistCurrentSession() async {
    if (_messages.isEmpty || _messages.any((m) => m.isGenerating)) return;
    final cleanMessages = _messages.where((m) => m.content.trim().isNotEmpty || m.type == MessageType.image || m.effectiveLocalFilePaths.isNotEmpty).toList();
    if (cleanMessages.isEmpty) return;
    final id = _currentSessionId ?? DateTime.now().microsecondsSinceEpoch.toString();
    _currentSessionId = id;
    await _settings.upsertChatHistory(ChatHistoryEntry(
      id: id,
      title: _sessionTitle(cleanMessages),
      updatedAt: DateTime.now(),
      messages: cleanMessages,
    ));
    await _loadHistory();
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('RangeError')) {
      return '发送失败：服务器返回内容为空或格式异常，请稍后重试。';
    }
    if (raw.contains('SocketException') || raw.contains('connection reset') || raw.contains('read_response_body_failed')) {
      return '发送失败：网络连接中断或服务器提前断开，请稍后重试。';
    }
    if (raw.contains('TimeoutException')) {
      return '发送失败：请求超时，请稍后重试。';
    }
    return '发送失败：$raw';
  }

  Future<void> _confirmNewSession() async {
    if (_loading) {
      _snack('正在发送中，请等待当前请求结束后再新建会话');
      return;
    }
    if (_messages.isEmpty && _input.text.trim().isEmpty && _attachedFiles.isEmpty) {
      _startNewSession();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: .96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('开始新会话？', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        content: const Text('当前聊天会先保存到历史记录，然后从界面中清空；API 配置、图片参数和面板状态会保留。', style: TextStyle(color: _muted, height: 1.45)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: _primary), child: const Text('新会话')),
        ],
      ),
    );
    if (confirmed == true) {
      await _persistCurrentSession();
      _startNewSession();
    }
  }

  void _startNewSession() {
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = false;
      _forceImage = false;
      _currentSessionId = null;
    });
    _scrollBottom();
    _snack('已开始新会话');
  }

  Future<void> _setStudioHeaderCollapsed(bool collapsed) async {
    if (!mounted) return;
    setState(() => _studioHeaderCollapsed = collapsed);
    await _saveSettings();
    if (!mounted) return;
    _snack(collapsed ? '已收起创作面板' : '已展开创作面板');
  }

  Future<void> _pickImages() async {
    final remaining = _maxReferenceImages - _attachedFiles.length;
    if (remaining <= 0) {
      _snack('最多支持 $_maxReferenceImages 张参考图，请先删除部分图片。');
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;
    final selected = picked.take(remaining).toList();
    final files = <File>[];
    final b64s = <String>[];
    for (final item in selected) {
      final file = File(item.path);
      files.add(file);
      b64s.add(base64Encode(await file.readAsBytes()));
    }
    if (!mounted) return;
    setState(() {
      _attachedFiles.addAll(files);
      _attachedBase64Images.addAll(b64s);
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

  void _clearAttachedImages() => setState(() {
        _attachedFiles.clear();
        _attachedBase64Images.clear();
      });

  Future<void> _send() async {
    final text = _input.text.trim();
    final files = List<File>.from(_attachedFiles);
    final b64s = List<String>.from(_attachedBase64Images);
    if (text.isEmpty && files.isEmpty) return;
    if (_apiKey.trim().isEmpty) {
      _snack('请先配置聊天 API Key。点击右上角设置。');
      return;
    }

    final content = text.isEmpty ? (files.length > 1 ? '请根据这些图片继续处理' : '请根据这张图片继续处理') : text;
    final user = Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      content: content,
      localFilePaths: files.map((e) => e.path).toList(),
      base64Images: b64s,
    );

    setState(() {
      _messages.add(user);
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = true;
    });
    _scrollBottom();

    try {
      if (_forceImage) {
        await _replyImage(prompt: content, imageFiles: files, base64Images: b64s, quality: _imageQuality);
      } else {
        await _replyAuto(userMessage: user, imageFiles: files, base64Images: b64s);
      }
    } catch (e) {
      final friendly = _friendlyError(e);
      _markLastGeneratingAsFailed(friendly);
      _snack(friendly);
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _forceImage = false;
      });
      await _persistCurrentSession();
      _scrollBottom();
    }
  }

  void _markLastGeneratingAsFailed(String message) {
    if (!mounted) return;
    final index = _messages.lastIndexWhere((m) => m.role == 'assistant' && m.isGenerating);
    if (index < 0) return;
    setState(() {
      final old = _messages[index];
      _messages[index] = Message(id: old.id, role: 'assistant', content: message, isGenerating: false);
    });
  }

  Future<void> _replyAuto({required Message userMessage, required List<File> imageFiles, required List<String> base64Images}) async {
    final placeholder = _assistantPlaceholder('正在理解你的创作意图…');
    final decision = await _api.decideTool(
      userText: userMessage.content,
      base64Image: null,
      base64Images: base64Images,
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      model: _chatModel,
    );

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
      try {
        finalPrompt = await _api.refineImagePrompt(
          userText: prompt,
          base64Image: null,
          base64Images: base64Images,
          apiKey: _apiKey,
          baseUrl: _baseUrl,
          model: _chatModel,
          aspectRatio: _imageAspectRatio,
          size: _selectedSize,
          quality: quality,
          isEdit: imageFiles.isNotEmpty,
        );
      } catch (e) {
        finalPrompt = prompt;
        if (mounted) {
          _snack('提示词润色失败，已使用原始提示词继续生成。');
          setState(() => placeholder.content = '提示词润色失败，已使用原始提示词继续生成…');
        }
      }
    }

    final total = _imageCount.clamp(1, 4).toInt();
    final generated = <String>[];
    for (var i = 0; i < total; i++) {
      if (mounted) {
        setState(() {
          placeholder.content = imageFiles.isEmpty
              ? '正在生成第 ${i + 1} / $total 张 $_imageAspectRatio 画面，图片生成可能需要数分钟…'
              : '正在参考 ${imageFiles.length} 张图生成第 ${i + 1} / $total 张 $_imageAspectRatio 画面，图片生成可能需要数分钟…';
        });
      }
      try {
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
      } catch (e) {
        if (generated.isNotEmpty) {
          _snack('已生成 ${generated.length} / $total 张，后续生成失败：$e');
          return;
        }
        rethrow;
      }
    }
    if (generated.length > 1) _snack('已生成 ${generated.length} 张图片');
  }

  Future<void> _saveImage(String url) async {
    try {
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: _primary));
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Luna AI Studio', style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900)),
          Text('Anime Image Generator', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(
            tooltip: '历史记录',
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded, color: _text),
          ),
          IconButton(
            tooltip: '新会话',
            onPressed: _confirmNewSession,
            icon: const Icon(Icons.add_comment_rounded, color: _text),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded, color: _text),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_bg, Color(0xFFEAF1FF), Color(0xFFF1ECFF)])),
        child: SafeArea(
          top: false,
          child: Column(children: [
            _studioHeader(),
            Expanded(child: _messages.isEmpty ? _emptyState() : _messageList()),
            if (_loading) const LinearProgressIndicator(color: _primary, minHeight: 2),
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: keyboard),
              child: _composer(),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openHistory() async {
    await _persistCurrentSession();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sheetSetState) {
        Future<void> refresh() async {
          final items = await _settings.getChatHistory();
          if (!mounted) return;
          setState(() => _history = items);
          sheetSetState(() {});
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.of(ctx).padding.bottom + 18),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * .72,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.history_rounded, color: _primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('历史记录', style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w900))),
                  if (_history.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await _settings.clearChatHistory();
                        await refresh();
                        if (mounted) _snack('历史记录已清空');
                      },
                      child: const Text('清空'),
                    ),
                ]),
                const SizedBox(height: 10),
                Expanded(
                  child: _history.isEmpty
                      ? const Center(child: Text('暂无历史记录\n发送消息后会自动保存', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.5, fontWeight: FontWeight.w700)))
                      : ListView.separated(
                          itemCount: _history.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final item = _history[i];
                            final time = '${item.updatedAt.month.toString().padLeft(2, '0')}-${item.updatedAt.day.toString().padLeft(2, '0')} ${item.updatedAt.hour.toString().padLeft(2, '0')}:${item.updatedAt.minute.toString().padLeft(2, '0')}';
                            return Material(
                              color: const Color(0xFFF7F4FF),
                              borderRadius: BorderRadius.circular(18),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                leading: Container(width: 42, height: 42, decoration: BoxDecoration(gradient: const LinearGradient(colors: [_primary, _primary2]), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.chat_bubble_rounded, color: Colors.white)),
                                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
                                subtitle: Text('$time · ${item.messages.length} 条消息', style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
                                onTap: () {
                                  setState(() {
                                    _currentSessionId = item.id;
                                    _messages
                                      ..clear()
                                      ..addAll(item.messages.map((m) => Message.fromJson(m.toJson())));
                                    _attachedFiles.clear();
                                    _attachedBase64Images.clear();
                                    _loading = false;
                                    _forceImage = false;
                                  });
                                  Navigator.pop(ctx);
                                  _scrollBottom();
                                  _snack('已恢复历史会话');
                                },
                                trailing: IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline_rounded, color: _muted),
                                  onPressed: () async {
                                    await _settings.deleteChatHistory(item.id);
                                    if (_currentSessionId == item.id && mounted) setState(() => _currentSessionId = null);
                                    await refresh();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _studioHeader() {
    if (_studioHeaderCollapsed) return _collapsedStudioHeader();
    return _panel(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: _primary, size: 30),
            const SizedBox(width: 10),
            Expanded(child: Text('画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)} · $_imageCount 张', style: const TextStyle(color: _text, fontWeight: FontWeight.w900))),
            TextButton.icon(onPressed: _openImageParams, icon: const Icon(Icons.tune_rounded), label: const Text('图片参数')),
            _roundPanelButton(
              icon: Icons.keyboard_arrow_up_rounded,
              tooltip: '收起创作面板',
              onTap: () => _setStudioHeaderCollapsed(true),
            ),
          ]),
          Row(children: [
            Expanded(child: _modeButton(Icons.auto_awesome, '自动', !_forceImage, () => setState(() => _forceImage = false))),
            const SizedBox(width: 8),
            Expanded(child: _modeButton(Icons.brush_rounded, '生图', _forceImage, () => setState(() => _forceImage = true))),
            const SizedBox(width: 8),
            Expanded(child: _modeButton(Icons.add_photo_alternate_rounded, '参考图', _attachedFiles.isNotEmpty, _pickImages)),
          ]),
        ]),
      );
  }

  Widget _collapsedStudioHeader() => _panel(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: () => _setStudioHeaderCollapsed(false),
          borderRadius: BorderRadius.circular(18),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: _primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_forceImage ? '图像创作模式' : '智能创作模式', style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)} · $_imageCount 张', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              ]),
            ),
            _roundPanelButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: '展开创作面板',
              onTap: () => _setStudioHeaderCollapsed(false),
            ),
          ]),
        ),
      );

  Widget _roundPanelButton({required IconData icon, required String tooltip, required VoidCallback onTap}) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_primary, _primary2]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: _primary.withValues(alpha: .22), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      );

  Widget _modeButton(IconData icon, String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [_primary, _primary2]) : null,
            color: active ? null : Colors.white.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? Colors.white : _line),
          ),
          child: Column(children: [Icon(icon, color: active ? Colors.white : _primary), const SizedBox(height: 4), Text(label, style: TextStyle(color: active ? Colors.white : _text, fontWeight: FontWeight.w900))]),
        ),
      );

  Future<void> _openImageParams() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sheetSetState) {
        Future<void> apply(Future<void> Function() fn) async {
          await fn();
          sheetSetState(() {});
          if (mounted) setState(() {});
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('图片参数', style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              const Text('画面比例', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
              Wrap(spacing: 8, children: _aspectOptions.map((v) => _choice(v, _imageAspectRatio == v, () => apply(() async { _imageAspectRatio = v; await _saveSettings(); }))).toList()),
              const SizedBox(height: 14),
              const Text('清晰度', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
              Wrap(spacing: 8, children: _qualityOptions.map((v) => _choice(_qualityLabel(v), _imageQuality == v, () => apply(() async { _imageQuality = v; await _saveSettings(); }))).toList()),
              const SizedBox(height: 14),
              const Text('生成数量', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
              Wrap(spacing: 8, children: _imageCountOptions.map((v) => _choice('$v 张', _imageCount == v, () => apply(() async { _imageCount = v; await _saveSettings(); }))).toList()),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('LLM 润色提示词后再生成', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                subtitle: const Text('润色失败时会自动使用原始提示词继续生成', style: TextStyle(color: _muted)),
                value: _enhanceImagePrompt,
                onChanged: (v) => apply(() async { _enhanceImagePrompt = v; await _saveSettings(); }),
              ),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成'))),
            ]),
          ),
        );
      }),
    );
  }

  Widget _choice(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ChoiceChip(label: Text(label), selected: active, onSelected: (_) => onTap(), selectedColor: _primary, labelStyle: TextStyle(color: active ? Colors.white : _text, fontWeight: FontWeight.w800)),
      );

  Widget _emptyState() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.auto_awesome_rounded, color: _primary, size: 72),
          const SizedBox(height: 12),
          const Text('今天想创作什么？', textAlign: TextAlign.center, style: TextStyle(color: _text, fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('可上传多张参考图，设置生成数量后一次连续生成多张图片。', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _confirmNewSession,
                style: FilledButton.styleFrom(backgroundColor: _primary),
                icon: const Icon(Icons.add_comment_rounded),
                label: const Text('开新会话'),
              ),
              OutlinedButton.icon(
                onPressed: _openHistory,
                icon: const Icon(Icons.history_rounded),
                label: const Text('历史记录'),
              ),
            ],
          ),
        ],
      );

  Widget _messageList() => ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), itemCount: _messages.length, itemBuilder: (_, i) => _bubble(_messages[i]));

  Widget _bubble(Message msg) {
    final user = msg.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: user ? const LinearGradient(colors: [_primary, _primary2]) : null,
          color: user ? null : _card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: user ? Colors.white54 : _line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.type == MessageType.image) _imageMessage(msg.content) else MarkdownBody(data: msg.content.isEmpty && msg.isGenerating ? '●' : msg.content, styleSheet: MarkdownStyleSheet(p: TextStyle(color: user ? Colors.white : _text, height: 1.45, fontWeight: FontWeight.w600))),
          if (msg.effectiveLocalFilePaths.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('参考图：${msg.effectiveLocalFilePaths.length} 张', style: TextStyle(color: user ? Colors.white70 : _muted, fontSize: 12))),
        ]),
      ),
    );
  }

  Widget _imageMessage(String url) {
    final isData = url.startsWith('data:image') && url.contains('base64,');
    final image = isData
        ? Image.memory(base64Decode(url.substring(url.indexOf('base64,') + 7)), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('图片解析失败', style: TextStyle(color: Colors.redAccent)))
        : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('图片加载失败', style: TextStyle(color: Colors.redAccent)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(18), child: image),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: () => _saveImage(url), icon: const Icon(Icons.download_rounded), label: const Text('保存图片')),
    ]);
  }

  Widget _attachedPreviewStrip() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFEFFFFD), borderRadius: BorderRadius.circular(18), border: Border.all(color: _cyan.withValues(alpha: .8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.image_rounded, color: _cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('参考图 ${_attachedFiles.length} / $_maxReferenceImages，可继续追加或单张删除', style: const TextStyle(color: _text, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
            TextButton(onPressed: _clearAttachedImages, child: const Text('清空')),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _attachedFiles.length + (_attachedFiles.length < _maxReferenceImages ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == _attachedFiles.length) {
                  return InkWell(onTap: _pickImages, borderRadius: BorderRadius.circular(16), child: Container(width: 74, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)), child: const Icon(Icons.add_photo_alternate_rounded, color: _primary)));
                }
                return Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_attachedFiles[i], width: 74, height: 78, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 74, height: 78, color: Colors.white, child: const Icon(Icons.broken_image_rounded, color: _muted)))),
                  Positioned(top: 3, right: 3, child: InkWell(onTap: () => _removeAttachedImage(i), child: Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 16)))),
                ]);
              },
            ),
          ),
        ]),
      );

  Widget _composer() => _panel(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_attachedFiles.isNotEmpty) _attachedPreviewStrip(),
          Row(children: [
            _smallButton(Icons.add_photo_alternate_rounded, _pickImages, _cyan),
            const SizedBox(width: 6),
            _smallButton(_forceImage ? Icons.brush_rounded : Icons.auto_awesome_outlined, () => setState(() => _forceImage = !_forceImage), _forceImage ? _primary : _primary2),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onTap: _scrollBottom,
                style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: _forceImage ? '描述要生成或编辑的画面…' : '输入聊天内容，或描述想生成的图片…',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .72),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _smallButton(Icons.arrow_upward_rounded, _loading ? null : _send, _primary),
          ]),
        ]),
      );

  Widget _smallButton(IconData icon, VoidCallback? onTap, Color color) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(width: 46, height: 46, decoration: BoxDecoration(gradient: onTap == null ? null : LinearGradient(colors: [color, color.withValues(alpha: .78)]), color: onTap == null ? Colors.grey.shade300 : null, borderRadius: BorderRadius.circular(17)), child: Icon(icon, color: Colors.white)),
      );

  Widget _panel({required EdgeInsets margin, required EdgeInsets padding, required Widget child}) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: .72)), boxShadow: [BoxShadow(color: _primary.withValues(alpha: .10), blurRadius: 22, offset: const Offset(0, 10))]),
        child: child,
      );

  Future<void> _openSettings() async {
    final key = TextEditingController(text: _apiKey);
    final imageKey = TextEditingController(text: _imageApiKey);
    final base = TextEditingController(text: _baseUrl);
    final imageBase = TextEditingController(text: _imageBaseUrl);
    final chat = TextEditingController(text: _chatModel);
    final image = TextEditingController(text: _imageModel);
    final edit = TextEditingController(text: _imageEditModel);
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          title: const Text('API 配置'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [_field(key, '聊天 API Key'), _field(base, '聊天 Base URL'), _field(chat, '聊天模型'), _field(imageKey, '图片 API Key（可留空）'), _field(imageBase, '图片 Base URL（可留空）'), _field(image, '文生图模型'), _field(edit, '图生图模型')])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _apiKey = key.text.trim();
                  _imageApiKey = imageKey.text.trim();
                  _baseUrl = base.text.trim();
                  _imageBaseUrl = imageBase.text.trim();
                  _chatModel = chat.text.trim();
                  _imageModel = image.text.trim();
                  _imageEditModel = edit.text.trim();
                });
                await _saveSettings();
                if (mounted) Navigator.pop(ctx);
                _snack('设置已保存');
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      key.dispose();
      imageKey.dispose();
      base.dispose();
      imageBase.dispose();
      chat.dispose();
      image.dispose();
      edit.dispose();
    }
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
      );
}
