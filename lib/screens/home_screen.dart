import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import '../services/api_service.dart';
import '../services/image_save_service.dart';
import '../services/settings_service.dart';
import 'debug_console_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _primary = Color(0xFF756BFF);
  static const _primary2 = Color(0xFFB044FF);
  static const _cyan = Color(0xFF5BC8D7);
  static const _rose = Color(0xFFFF7AB4);
  static const _amber = Color(0xFFFFC24A);
  static const _bg = Color(0xFFFFFAFD);
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
  List<ArtworkEntry> _artworks = [];
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
  static const _qualityOptions = [
    'auto',
    'standard',
    'hd',
    'low',
    'medium',
    'high'
  ];
  static const _imageCountOptions = [1, 2, 3, 4];
  static const _maxReferenceImages = 8;

  String get _effectiveImageApiKey =>
      _imageApiKey.trim().isEmpty ? _apiKey : _imageApiKey.trim();
  String get _effectiveImageBaseUrl =>
      _imageBaseUrl.trim().isEmpty ? _baseUrl : _imageBaseUrl.trim();
  String get _effectiveImageModel => _api.normalizeImageModel(_imageModel);
  String get _effectiveImageEditModel =>
      _api.normalizeImageEditModel(_imageEditModel);
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
    _loadArtworks();
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
      _imageAspectRatio = _aspectOptions.contains(s['imageAspectRatio'])
          ? s['imageAspectRatio']!
          : '1:1';
      _imageQuality = _qualityOptions.contains(s['imageQuality'])
          ? s['imageQuality']!
          : 'auto';
      _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';
      _studioHeaderCollapsed = (s['studioHeaderCollapsed'] ?? 'true') == 'true';
      _imageCount =
          int.tryParse(s['imageCount'] ?? '1')?.clamp(1, 4).toInt() ?? 1;
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

  Future<void> _loadArtworks() async {
    final items = await _settings.getArtworkLibrary();
    if (!mounted) return;
    setState(() => _artworks = items);
  }

  String _sessionTitle(List<Message> messages) {
    String? firstUser;
    for (final message in messages) {
      if (message.role == 'user' && message.content.trim().isNotEmpty) {
        firstUser = message.content.trim();
        break;
      }
    }
    final raw = firstUser ??
        (messages.any((m) => m.type == MessageType.image) ? '图片创作会话' : '未命名会话');
    return raw.length > 22 ? '${raw.substring(0, 22)}…' : raw;
  }

  Future<void> _persistCurrentSession() async {
    if (_messages.isEmpty || _messages.any((m) => m.isGenerating)) return;
    final cleanMessages = _messages
        .where((m) =>
            m.content.trim().isNotEmpty ||
            m.type == MessageType.image ||
            m.effectiveLocalFilePaths.isNotEmpty)
        .toList();
    if (cleanMessages.isEmpty) return;
    final id =
        _currentSessionId ?? DateTime.now().microsecondsSinceEpoch.toString();
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
    if (raw.contains('SocketException') ||
        raw.contains('connection reset') ||
        raw.contains('read_response_body_failed')) {
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
    if (_messages.isEmpty &&
        _input.text.trim().isEmpty &&
        _attachedFiles.isEmpty) {
      _startNewSession();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: .96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('开始新会话？',
            style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        content: const Text('当前聊天会先保存到历史记录，然后从界面中清空；API 配置、图片参数和面板状态会保留。',
            style: TextStyle(color: _muted, height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('新会话')),
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
      _forceImage = true;
    });
    if (picked.length > remaining)
      _snack('最多支持 $_maxReferenceImages 张参考图，已添加前 $remaining 张。');
  }

  void _removeAttachedImage(int index) {
    if (index < 0 || index >= _attachedFiles.length) return;
    setState(() {
      _attachedFiles.removeAt(index);
      if (index < _attachedBase64Images.length)
        _attachedBase64Images.removeAt(index);
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
    final needsChatApi = !_forceImage || _enhanceImagePrompt;
    if (needsChatApi && _apiKey.trim().isEmpty) {
      _snack('请先配置聊天 API Key。点击右上角设置。');
      return;
    }
    if (_forceImage && _effectiveImageApiKey.trim().isEmpty) {
      _snack('请先配置图片 API Key，或让图片 API Key 留空以沿用聊天 API Key。');
      return;
    }

    final content = text.isEmpty
        ? (files.length > 1 ? '请根据这些图片继续处理' : '请根据这张图片继续处理')
        : text;
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
        await _replyImage(
            prompt: content,
            imageFiles: files,
            base64Images: b64s,
            quality: _imageQuality);
      } else {
        await _replyAuto(
            userMessage: user, imageFiles: files, base64Images: b64s);
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
    final index = _messages
        .lastIndexWhere((m) => m.role == 'assistant' && m.isGenerating);
    if (index < 0) return;
    setState(() {
      final old = _messages[index];
      _messages[index] = Message(
          id: old.id, role: 'assistant', content: message, isGenerating: false);
    });
  }

  Future<void> _replyAuto(
      {required Message userMessage,
      required List<File> imageFiles,
      required List<String> base64Images}) async {
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
      final stream = _api.generateChatStream(
          _messages.where((m) => m.id != placeholder.id).toList(),
          _apiKey,
          _baseUrl,
          _chatModel);
      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() => placeholder.content += chunk);
        _scrollBottom();
      }
      if (!mounted) return;
      setState(() {
        placeholder.content = placeholder.content.trim().isEmpty
            ? (decision.reply.isEmpty ? '我已经理解你的需求。' : decision.reply)
            : placeholder.content;
        placeholder.isGenerating = false;
      });
      return;
    }

    await _finishImageMessage(
      placeholder: placeholder,
      prompt: _enhanceImagePrompt && decision.prompt.isNotEmpty
          ? decision.prompt
          : userMessage.content,
      imageFiles: decision.action == ToolAction.imageToImage
          ? imageFiles
          : const <File>[],
      base64Images: decision.action == ToolAction.imageToImage
          ? base64Images
          : const <String>[],
      quality: _imageQuality == 'auto' ? decision.quality : _imageQuality,
    );
  }

  Future<void> _replyImage(
      {required String prompt,
      required List<File> imageFiles,
      required List<String> base64Images,
      required String quality}) async {
    final placeholder = _assistantPlaceholder(
        imageFiles.isEmpty ? '正在构建画面…' : '正在读取参考图并生成新画面…');
    await _finishImageMessage(
        placeholder: placeholder,
        prompt: prompt,
        imageFiles: imageFiles,
        base64Images: base64Images,
        quality: quality);
  }

  Message _assistantPlaceholder(String text) {
    final msg = Message(
        id: '${DateTime.now().microsecondsSinceEpoch + 1}',
        role: 'assistant',
        content: text,
        isGenerating: true);
    setState(() => _messages.add(msg));
    _scrollBottom();
    return msg;
  }

  Future<void> _finishImageMessage(
      {required Message placeholder,
      required String prompt,
      required List<File> imageFiles,
      required List<String> base64Images,
      required String quality}) async {
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
            ? await _api.generateImage(finalPrompt, _effectiveImageApiKey,
                _effectiveImageBaseUrl, _effectiveImageModel,
                size: _selectedSize, quality: quality)
            : await _api.editImages(
                finalPrompt,
                imageFiles,
                _effectiveImageApiKey,
                _effectiveImageBaseUrl,
                _effectiveImageEditModel,
                size: _selectedSize,
                quality: quality);
        final storedImage = await _persistGeneratedImageIfNeeded(image);
        generated.add(storedImage);
        if (!mounted) return;
        setState(() {
          final imageMessage = Message(
            id: i == 0
                ? placeholder.id
                : '${DateTime.now().microsecondsSinceEpoch + i}',
            role: 'assistant',
            content: storedImage,
            type: MessageType.image,
            imagePrompt: finalPrompt,
            originalPrompt: prompt,
            imageModel: imageFiles.isEmpty
                ? _effectiveImageModel
                : _effectiveImageEditModel,
            imageSize: _selectedSize,
            imageQuality: quality,
            imageAspectRatio: _imageAspectRatio,
            referenceImagePaths: imageFiles.map((e) => e.path).toList(),
          );
          if (i == 0) {
            final index = _messages.indexWhere((m) => m.id == placeholder.id);
            if (index >= 0) _messages[index] = imageMessage;
          } else {
            _messages.add(imageMessage);
          }
        });
        await _saveArtworkFromImage(
          image: storedImage,
          prompt: finalPrompt,
          originalPrompt: prompt,
          model: imageFiles.isEmpty
              ? _effectiveImageModel
              : _effectiveImageEditModel,
          referenceImagePaths: imageFiles.map((e) => e.path).toList(),
          quality: quality,
        );
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

  Future<void> _saveArtworkFromImage({
    required String image,
    required String prompt,
    required String originalPrompt,
    required String model,
    required List<String> referenceImagePaths,
    required String quality,
  }) async {
    await _settings.upsertArtwork(ArtworkEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      image: image,
      prompt: prompt,
      originalPrompt: originalPrompt,
      model: model,
      size: _selectedSize,
      quality: quality,
      aspectRatio: _imageAspectRatio,
      referenceImagePaths: referenceImagePaths,
      createdAt: DateTime.now(),
    ));
    await _loadArtworks();
  }

  Future<String> _persistGeneratedImageIfNeeded(String image) async {
    if (!image.startsWith('data:image') || !image.contains('base64,')) {
      return image;
    }
    final comma = image.indexOf(',');
    final header = image.substring(0, comma).toLowerCase();
    final payload = image.substring(comma + 1).replaceAll(RegExp(r'\s+'), '');
    final mime =
        RegExp(r'data:([^;]+)').firstMatch(header)?.group(1) ?? 'image/png';
    final extension = mime.contains('jpeg') || mime.contains('jpg')
        ? 'jpg'
        : mime.contains('webp')
            ? 'webp'
            : 'png';
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/luna_artworks');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(
        '${dir.path}/image_${DateTime.now().microsecondsSinceEpoch}.$extension');
    await file.writeAsBytes(base64Decode(payload));
    return file.path;
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
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _primary));
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
        title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Luna AI Studio',
                  style: TextStyle(
                      color: _text, fontSize: 20, fontWeight: FontWeight.w900)),
              Text('Anime Image Generator',
                  style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
        actions: [
          IconButton(
            tooltip: '历史记录',
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded, color: _text),
          ),
          IconButton(
            tooltip: '作品库',
            onPressed: _openArtworkLibrary,
            icon: const Icon(Icons.photo_library_rounded, color: _text),
          ),
          IconButton(
            tooltip: '新会话',
            onPressed: _confirmNewSession,
            icon: const Icon(Icons.add_comment_rounded, color: _text),
          ),
          IconButton(
            tooltip: '调试控制台',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DebugConsoleScreen())),
            icon: const Icon(Icons.terminal_rounded, color: _text),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded, color: _text),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _bg,
              Color(0xFFFFEFF7),
              Color(0xFFEFF8FF),
              Color(0xFFF3EEFF)
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(children: [
            _studioHeader(),
            Expanded(child: _messages.isEmpty ? _emptyState() : _messageList()),
            if (_loading)
              const LinearProgressIndicator(color: _primary, minHeight: 2),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
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
            padding: EdgeInsets.fromLTRB(
                18, 8, 18, MediaQuery.of(ctx).padding.bottom + 18),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * .72,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.history_rounded, color: _primary),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('历史记录',
                              style: TextStyle(
                                  color: _text,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900))),
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
                          ? const Center(
                              child: Text('暂无历史记录\n发送消息后会自动保存',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: _muted,
                                      height: 1.5,
                                      fontWeight: FontWeight.w700)))
                          : ListView.separated(
                              itemCount: _history.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final item = _history[i];
                                final time =
                                    '${item.updatedAt.month.toString().padLeft(2, '0')}-${item.updatedAt.day.toString().padLeft(2, '0')} ${item.updatedAt.hour.toString().padLeft(2, '0')}:${item.updatedAt.minute.toString().padLeft(2, '0')}';
                                return Material(
                                  color: const Color(0xFFF7F4FF),
                                  borderRadius: BorderRadius.circular(18),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(18)),
                                    leading: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                                colors: [_primary, _primary2]),
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        child: const Icon(
                                            Icons.chat_bubble_rounded,
                                            color: Colors.white)),
                                    title: Text(item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: _text,
                                            fontWeight: FontWeight.w900)),
                                    subtitle: Text(
                                        '$time · ${item.messages.length} 条消息',
                                        style: const TextStyle(
                                            color: _muted,
                                            fontWeight: FontWeight.w700)),
                                    onTap: () {
                                      setState(() {
                                        _currentSessionId = item.id;
                                        _messages
                                          ..clear()
                                          ..addAll(item.messages.map((m) =>
                                              Message.fromJson(m.toJson())));
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
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: _muted),
                                      onPressed: () async {
                                        await _settings
                                            .deleteChatHistory(item.id);
                                        if (_currentSessionId == item.id &&
                                            mounted)
                                          setState(
                                              () => _currentSessionId = null);
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
          Expanded(
              child: Text(
                  '画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)} · $_imageCount 张',
                  style: const TextStyle(
                      color: _text, fontWeight: FontWeight.w900))),
          TextButton.icon(
              onPressed: _openImageParams,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('图片参数')),
          _roundPanelButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: '收起创作面板',
            onTap: () => _setStudioHeaderCollapsed(true),
          ),
        ]),
        Row(children: [
          Expanded(
              child: _modeButton(Icons.auto_awesome, '自动', !_forceImage,
                  () => setState(() => _forceImage = false))),
          const SizedBox(width: 8),
          Expanded(
              child: _modeButton(Icons.brush_rounded, '生图', _forceImage,
                  () => setState(() => _forceImage = true))),
          const SizedBox(width: 8),
          Expanded(
              child: _modeButton(Icons.add_photo_alternate_rounded, '参考图',
                  _attachedFiles.isNotEmpty, _pickImages)),
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
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_forceImage ? '图像创作模式' : '智能创作模式',
                        style: const TextStyle(
                            color: _text, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                        '画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)} · $_imageCount 张',
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
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

  Widget _roundPanelButton(
          {required IconData icon,
          required String tooltip,
          required VoidCallback onTap}) =>
      Tooltip(
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
              boxShadow: [
                BoxShadow(
                    color: _primary.withValues(alpha: .22),
                    blurRadius: 14,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      );

  Widget _modeButton(
          IconData icon, String label, bool active, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(colors: [_primary, _primary2])
                : null,
            color: active ? null : Colors.white.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? Colors.white : _line),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: _primary.withValues(alpha: .18),
                        blurRadius: 16,
                        offset: const Offset(0, 7))
                  ]
                : null,
          ),
          child: Column(children: [
            Icon(icon, color: active ? Colors.white : _primary),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : _text,
                    fontWeight: FontWeight.w900))
          ]),
        ),
      );

  Future<void> _openImageParams() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sheetSetState) {
        Future<void> apply(Future<void> Function() fn) async {
          await fn();
          sheetSetState(() {});
          if (mounted) setState(() {});
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              18,
              8,
              18,
              MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  18),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('图片参数',
                      style: TextStyle(
                          color: _text,
                          fontSize: 21,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  const Text('画面比例',
                      style:
                          TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  Wrap(
                      spacing: 8,
                      children: _aspectOptions
                          .map((v) => _choice(
                              v,
                              _imageAspectRatio == v,
                              () => apply(() async {
                                    _imageAspectRatio = v;
                                    await _saveSettings();
                                  })))
                          .toList()),
                  const SizedBox(height: 14),
                  const Text('清晰度',
                      style:
                          TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  Wrap(
                      spacing: 8,
                      children: _qualityOptions
                          .map((v) => _choice(
                              _qualityLabel(v),
                              _imageQuality == v,
                              () => apply(() async {
                                    _imageQuality = v;
                                    await _saveSettings();
                                  })))
                          .toList()),
                  const SizedBox(height: 14),
                  const Text('生成数量',
                      style:
                          TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  Wrap(
                      spacing: 8,
                      children: _imageCountOptions
                          .map((v) => _choice(
                              '$v 张',
                              _imageCount == v,
                              () => apply(() async {
                                    _imageCount = v;
                                    await _saveSettings();
                                  })))
                          .toList()),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('LLM 润色提示词后再生成',
                        style: TextStyle(
                            color: _text, fontWeight: FontWeight.w900)),
                    subtitle: const Text('润色失败时会自动使用原始提示词继续生成',
                        style: TextStyle(color: _muted)),
                    value: _enhanceImagePrompt,
                    onChanged: (v) => apply(() async {
                      _enhanceImagePrompt = v;
                      await _saveSettings();
                    }),
                  ),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('完成'))),
                ]),
          ),
        );
      }),
    );
  }

  Widget _choice(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ChoiceChip(
            label: Text(label),
            selected: active,
            onSelected: (_) => onTap(),
            selectedColor: _primary,
            backgroundColor: const Color(0xFFF8F3FF),
            checkmarkColor: Colors.white,
            side:
                BorderSide(color: active ? _primary : const Color(0xFFDCD2F1)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            labelStyle: TextStyle(
                color: active ? Colors.white : _text,
                fontWeight: FontWeight.w900)),
      );

  Widget _animeIntroCard() => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
                color: _primary.withValues(alpha: .10),
                blurRadius: 24,
                offset: const Offset(0, 10))
          ],
        ),
        child: Row(children: [
          Container(
            width: 104,
            height: 124,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEADFFF)),
              gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF5FB), Color(0xFFE9F9FF)]),
            ),
            child: Stack(alignment: Alignment.center, children: [
              Positioned(
                  bottom: 14,
                  child: Container(
                      width: 74,
                      height: 28,
                      decoration: BoxDecoration(
                          color: _primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999)))),
              Container(
                width: 58,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _text, width: 2.4),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 10,
                        offset: Offset(0, 5))
                  ],
                ),
              ),
              Positioned(
                  top: 32,
                  child: Container(
                      width: 54,
                      height: 22,
                      decoration: const BoxDecoration(
                          color: _amber,
                          borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(5),
                              bottomRight: Radius.circular(5))))),
              Positioned(
                  bottom: 34,
                  child: Container(
                      width: 48,
                      height: 26,
                      decoration: const BoxDecoration(
                          color: Color(0xFFFFD4EA),
                          borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20))))),
              Positioned(
                  top: 48,
                  left: 38,
                  child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                          color: _text, shape: BoxShape.circle))),
              Positioned(
                  top: 48,
                  right: 38,
                  child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                          color: _text, shape: BoxShape.circle))),
              const Positioned(
                  top: 16,
                  right: 17,
                  child: Icon(Icons.auto_awesome_rounded,
                      color: _amber, size: 18)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('角色设定先行，画面自动展开',
                  style: TextStyle(
                      color: _text,
                      fontSize: 19,
                      height: 1.15,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('更像二次元创作台，同时保留参数、参考图和控制台入口。',
                  style: TextStyle(
                      color: _muted,
                      height: 1.45,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: const [
                _MiniTag(label: 'Anime', hot: true),
                _MiniTag(label: '角色一致性'),
                _MiniTag(label: '批量生成'),
              ]),
            ]),
          ),
        ]),
      );

  Widget _emptyState() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _animeIntroCard(),
          const SizedBox(height: 40),
          const Icon(Icons.auto_awesome_rounded, color: _primary, size: 72),
          const SizedBox(height: 12),
          const Text('今天想创作什么？',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _text, fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('可上传多张参考图，设置生成数量后一次连续生成多张图片。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _muted, height: 1.5, fontWeight: FontWeight.w600)),
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

  Widget _messageList() => ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]));

  Widget _bubble(Message msg) {
    final user = msg.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient:
              user ? const LinearGradient(colors: [_primary, _primary2]) : null,
          color: user ? null : _card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: user ? Colors.white54 : _line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.type == MessageType.image)
            _imageMessage(msg)
          else
            MarkdownBody(
                data:
                    msg.content.isEmpty && msg.isGenerating ? '●' : msg.content,
                styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                        color: user ? Colors.white : _text,
                        height: 1.45,
                        fontWeight: FontWeight.w600))),
          if (msg.effectiveLocalFilePaths.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('参考图：${msg.effectiveLocalFilePaths.length} 张',
                    style: TextStyle(
                        color: user ? Colors.white70 : _muted, fontSize: 12))),
        ]),
      ),
    );
  }

  Widget _imageMessage(Message msg) {
    final url = msg.content;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
          onTap: () => _openImageViewer(msg),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _previewImage(url, fit: BoxFit.cover))),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: () => _saveImage(url),
            icon: const Icon(Icons.download_rounded),
            label: const Text('保存')),
        OutlinedButton.icon(
            onPressed: () => _openImageViewer(msg),
            icon: const Icon(Icons.open_in_full_rounded),
            label: const Text('查看')),
        if ((msg.imagePrompt ?? '').trim().isNotEmpty)
          OutlinedButton.icon(
              onPressed: () => _copyText(msg.imagePrompt!),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('提示词')),
      ]),
    ]);
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('已复制');
  }

  void _reusePrompt(String prompt, {bool forceImage = true}) {
    if (prompt.trim().isEmpty) return;
    setState(() {
      _input.text = prompt.trim();
      _forceImage = forceImage;
    });
    _inputFocus.requestFocus();
    _snack('已回填到输入框');
  }

  Widget _previewImage(String url, {BoxFit fit = BoxFit.cover}) {
    if (File(url).existsSync()) {
      return Image.file(File(url),
          fit: fit,
          errorBuilder: (_, __, ___) => const Center(
              child:
                  Text('图片加载失败', style: TextStyle(color: Colors.redAccent))));
    }
    final isData = url.startsWith('data:image') && url.contains('base64,');
    if (isData) {
      return Image.memory(
          base64Decode(url.substring(url.indexOf('base64,') + 7)),
          fit: fit,
          errorBuilder: (_, __, ___) => const Center(
              child:
                  Text('图片解析失败', style: TextStyle(color: Colors.redAccent))));
    }
    return Image.network(url,
        fit: fit,
        errorBuilder: (_, __, ___) => const Center(
            child: Text('图片加载失败', style: TextStyle(color: Colors.redAccent))));
  }

  Future<void> _attachGeneratedImageAsReference(String image) async {
    try {
      final bytes = image.startsWith('data:image') && image.contains('base64,')
          ? base64Decode(image.substring(image.indexOf('base64,') + 7))
          : await File(image).exists()
              ? await File(image).readAsBytes()
              : (await http.get(Uri.parse(image))).bodyBytes;
      final temp = await getTemporaryDirectory();
      final file = File(
          '${temp.path}/luna_ref_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      if (_attachedFiles.length >= _maxReferenceImages) {
        _snack('参考图已达上限，请先删除部分图片。');
        return;
      }
      setState(() {
        _attachedFiles.add(file);
        _attachedBase64Images.add(base64Encode(bytes));
        _forceImage = true;
      });
      _inputFocus.requestFocus();
      _snack('已加入参考图，可继续编辑');
    } catch (e) {
      _snack('加入参考图失败：$e');
    }
  }

  Future<void> _openImageViewer(Message msg) async {
    final prompt = msg.imagePrompt?.trim() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .86,
          child: Column(children: [
            Expanded(
                child: Container(
                    color: const Color(0xFFF8F5FF),
                    width: double.infinity,
                    child: InteractiveViewer(
                        child: Center(
                            child: _previewImage(msg.content,
                                fit: BoxFit.contain))))),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, MediaQuery.of(ctx).padding.bottom + 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _MiniTag(
                          label: msg.imageAspectRatio ?? _imageAspectRatio,
                          hot: true),
                      _MiniTag(label: msg.imageSize ?? _selectedSize),
                      _MiniTag(
                          label:
                              _qualityLabel(msg.imageQuality ?? _imageQuality)),
                      if ((msg.imageModel ?? '').isNotEmpty)
                        _MiniTag(label: msg.imageModel!),
                    ]),
                    if (prompt.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(prompt,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _text,
                              height: 1.35,
                              fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                          onPressed: () => _saveImage(msg.content),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('保存')),
                      if (prompt.isNotEmpty)
                        OutlinedButton.icon(
                            onPressed: () => _copyText(prompt),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('复制提示词')),
                      if (prompt.isNotEmpty)
                        OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _reusePrompt(prompt);
                            },
                            icon: const Icon(Icons.replay_rounded),
                            label: const Text('再生成')),
                      OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _attachGeneratedImageAsReference(msg.content);
                          },
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                          label: const Text('作为参考')),
                    ]),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openArtworkLibrary() async {
    await _loadArtworks();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, sheetSetState) {
        Future<void> refresh() async {
          final items = await _settings.getArtworkLibrary();
          if (!mounted) return;
          setState(() => _artworks = items);
          sheetSetState(() {});
        }

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .82,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(ctx).padding.bottom + 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.photo_library_rounded, color: _primary),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('作品库',
                              style: TextStyle(
                                  color: _text,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900))),
                      if (_artworks.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await _settings.clearArtworkLibrary();
                            await refresh();
                            _snack('作品库已清空');
                          },
                          child: const Text('清空'),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _artworks.isEmpty
                          ? const Center(
                              child: Text('暂无作品\n生成图片后会自动保存到这里',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: _muted,
                                      height: 1.5,
                                      fontWeight: FontWeight.w700)))
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: .72),
                              itemCount: _artworks.length,
                              itemBuilder: (_, i) {
                                final item = _artworks[i];
                                final msg = Message(
                                  id: item.id,
                                  role: 'assistant',
                                  content: item.image,
                                  type: MessageType.image,
                                  imagePrompt: item.prompt,
                                  originalPrompt: item.originalPrompt,
                                  imageModel: item.model,
                                  imageSize: item.size,
                                  imageQuality: item.quality,
                                  imageAspectRatio: item.aspectRatio,
                                  referenceImagePaths: item.referenceImagePaths,
                                  timestamp: item.createdAt,
                                );
                                return InkWell(
                                  onTap: () => _openImageViewer(msg),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFF7F4FF),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: _line)),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: SizedBox(
                                                  width: double.infinity,
                                                  child: _previewImage(
                                                      item.image))),
                                          Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      item.prompt.isEmpty
                                                          ? '未记录提示词'
                                                          : item.prompt,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          color: _text,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 12)),
                                                  const SizedBox(height: 4),
                                                  Row(children: [
                                                    Expanded(
                                                        child: Text(
                                                            '${item.aspectRatio} · ${item.size}',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: const TextStyle(
                                                                color: _muted,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700))),
                                                    IconButton(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      tooltip: '删除',
                                                      icon: const Icon(
                                                          Icons
                                                              .delete_outline_rounded,
                                                          color: _muted,
                                                          size: 20),
                                                      onPressed: () async {
                                                        await _settings
                                                            .deleteArtwork(
                                                                item.id);
                                                        await refresh();
                                                      },
                                                    ),
                                                  ]),
                                                ]),
                                          ),
                                        ]),
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

  Widget _attachedPreviewStrip() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: const Color(0xFFEFFFFD),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cyan.withValues(alpha: .8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.image_rounded, color: _cyan),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    '参考图 ${_attachedFiles.length} / $_maxReferenceImages，可继续追加或单张删除',
                    style: const TextStyle(
                        color: _text, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis)),
            TextButton(
                onPressed: _clearAttachedImages, child: const Text('清空')),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _attachedFiles.length +
                  (_attachedFiles.length < _maxReferenceImages ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == _attachedFiles.length) {
                  return InkWell(
                      onTap: _pickImages,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                          width: 74,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .72),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _line)),
                          child: const Icon(Icons.add_photo_alternate_rounded,
                              color: _primary)));
                }
                return Stack(children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(_attachedFiles[i],
                          width: 74,
                          height: 78,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 74,
                              height: 78,
                              color: Colors.white,
                              child: const Icon(Icons.broken_image_rounded,
                                  color: _muted)))),
                  Positioned(
                      top: 3,
                      right: 3,
                      child: InkWell(
                          onTap: () => _removeAttachedImage(i),
                          child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .55),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white, size: 16)))),
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
            _smallButton(
                _forceImage ? Icons.brush_rounded : Icons.auto_awesome_outlined,
                () => setState(() => _forceImage = !_forceImage),
                _forceImage ? _primary : _primary2),
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
                style:
                    const TextStyle(color: _text, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: _forceImage ? '描述要生成或编辑的画面…' : '输入聊天内容，或描述想生成的图片…',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .72),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _smallButton(
                Icons.arrow_upward_rounded, _loading ? null : _send, _primary),
          ]),
        ]),
      );

  Widget _smallButton(IconData icon, VoidCallback? onTap, Color color) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: onTap == null
                ? null
                : LinearGradient(colors: [color, color.withValues(alpha: .78)]),
            color: onTap == null ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: onTap == null
                ? null
                : [
                    BoxShadow(
                        color: color.withValues(alpha: .18),
                        blurRadius: 14,
                        offset: const Offset(0, 6))
                  ],
          ),
          child: Icon(icon, color: Colors.white),
        ),
      );

  Widget _panel(
          {required EdgeInsets margin,
          required EdgeInsets padding,
          required Widget child}) =>
      Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .84)),
          boxShadow: [
            BoxShadow(
                color: _primary.withValues(alpha: .10),
                blurRadius: 26,
                offset: const Offset(0, 12)),
            BoxShadow(
                color: _rose.withValues(alpha: .06),
                blurRadius: 18,
                offset: const Offset(-8, 2)),
          ],
        ),
        child: child,
      );

  Future<void> _fetchAndFillModel({
    required TextEditingController key,
    required TextEditingController base,
    required TextEditingController target,
    required String title,
    TextEditingController? imageKey,
    TextEditingController? imageBase,
    bool useImageProvider = false,
  }) async {
    final apiKey =
        useImageProvider && (imageKey?.text.trim().isNotEmpty ?? false)
            ? imageKey!.text.trim()
            : key.text.trim();
    final baseUrl =
        useImageProvider && (imageBase?.text.trim().isNotEmpty ?? false)
            ? imageBase!.text.trim()
            : base.text.trim();
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
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        clipBehavior: Clip.antiAlias,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .72,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(ctx).padding.bottom + 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _text,
                            fontSize: 21,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('共获取到 ${models.length} 个模型，点击一个模型回填到输入框。',
                        style: const TextStyle(
                            color: _muted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: models.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: _line),
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          leading: Icon(_modelIcon(models[i]), color: _primary),
                          title: Text(models[i],
                              style: const TextStyle(
                                  color: _text, fontWeight: FontWeight.w800)),
                          subtitle: Text(_modelKind(models[i]),
                              style: const TextStyle(
                                  color: _muted, fontWeight: FontWeight.w700)),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: _muted),
                          onTap: () => Navigator.pop(ctx, models[i]),
                        ),
                      ),
                    ),
                  ]),
            ),
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

  String _modelKind(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('image') ||
        lower.startsWith('dall-e') ||
        lower.contains('stable-diffusion')) return '图片生成/编辑模型';
    if (lower.contains('embedding')) return '向量模型';
    if (lower.contains('tts') ||
        lower.contains('audio') ||
        lower.contains('whisper')) return '音频模型';
    if (lower.contains('vision') ||
        lower.contains('vl') ||
        lower.contains('gpt-4o')) return '聊天/视觉模型';
    if (lower.startsWith('gpt') ||
        lower.contains('claude') ||
        lower.contains('gemini') ||
        lower.contains('deepseek') ||
        lower.contains('qwen') ||
        lower.contains('glm')) return '聊天模型';
    return '未知能力，请按服务商说明选择';
  }

  IconData _modelIcon(String model) {
    final kind = _modelKind(model);
    if (kind.contains('图片')) return Icons.image_search_rounded;
    if (kind.contains('音频')) return Icons.graphic_eq_rounded;
    if (kind.contains('向量')) return Icons.hub_rounded;
    if (kind.contains('视觉')) return Icons.visibility_rounded;
    if (kind.contains('聊天')) return Icons.chat_bubble_rounded;
    return Icons.view_in_ar_rounded;
  }

  Future<void> _openSettings() async {
    final key = TextEditingController(text: _apiKey);
    final imageKey = TextEditingController(text: _imageApiKey);
    final base = TextEditingController(text: _baseUrl);
    final imageBase = TextEditingController(text: _imageBaseUrl);
    final chat = TextEditingController(text: _chatModel);
    final image = TextEditingController(text: _imageModel);
    final edit = TextEditingController(text: _imageEditModel);
    Future<void> saveProfile() async {
      final name = TextEditingController();
      try {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('保存配置档案'),
            content: TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: '档案名称', border: OutlineInputBorder())),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存')),
            ],
          ),
        );
        final title = name.text.trim();
        if (ok != true || title.isEmpty) return;
        await _settings.upsertProviderProfile(ProviderProfile(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: title,
          apiKey: key.text.trim(),
          imageApiKey: imageKey.text.trim(),
          baseUrl: base.text.trim(),
          imageBaseUrl: imageBase.text.trim(),
          chatModel: chat.text.trim(),
          imageModel: image.text.trim(),
          imageEditModel: edit.text.trim(),
          updatedAt: DateTime.now(),
        ));
        _snack('配置档案已保存');
      } finally {
        name.dispose();
      }
    }

    Future<void> loadProfile() async {
      final profiles = await _settings.getProviderProfiles();
      if (!mounted) return;
      if (profiles.isEmpty) {
        _snack('还没有配置档案');
        return;
      }
      final selected = await showModalBottomSheet<ProviderProfile>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .62,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(ctx).padding.bottom + 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择配置档案',
                        style: TextStyle(
                            color: _text,
                            fontSize: 21,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: profiles.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: _line),
                        itemBuilder: (_, i) {
                          final profile = profiles[i];
                          return ListTile(
                            leading: const Icon(Icons.cloud_done_rounded,
                                color: _primary),
                            title: Text(profile.name,
                                style: const TextStyle(
                                    color: _text, fontWeight: FontWeight.w900)),
                            subtitle: Text(
                                '${profile.baseUrl} · ${profile.chatModel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(ctx, profile),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: _muted),
                              onPressed: () async {
                                await _settings
                                    .deleteProviderProfile(profile.id);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _snack('配置档案已删除');
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      );
      if (selected == null) return;
      key.text = selected.apiKey;
      imageKey.text = selected.imageApiKey;
      base.text = selected.baseUrl;
      imageBase.text = selected.imageBaseUrl;
      chat.text = selected.chatModel;
      image.text = selected.imageModel;
      edit.text = selected.imageEditModel;
      _snack('已加载配置档案：${selected.name}');
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          title: const Text('API 配置'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: loadProfile,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('加载档案'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: saveProfile,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('保存档案'))),
              ]),
              const SizedBox(height: 12),
              _field(key, '聊天 API Key'),
              _field(base, '聊天 Base URL'),
              _field(chat, '聊天模型'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _fetchAndFillModel(
                      key: key, base: base, target: chat, title: '选择聊天模型'),
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
                      onPressed: () => _fetchAndFillModel(
                          key: key,
                          base: base,
                          target: image,
                          title: '选择文生图模型',
                          imageKey: imageKey,
                          imageBase: imageBase,
                          useImageProvider: true),
                      icon: const Icon(Icons.image_search_rounded),
                      label: const Text('获取文生图模型'),
                    ),
                    TextButton.icon(
                      onPressed: () => _fetchAndFillModel(
                          key: key,
                          base: base,
                          target: edit,
                          title: '选择图生图模型',
                          imageKey: imageKey,
                          imageBase: imageBase,
                          useImageProvider: true),
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('获取图生图模型'),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
        child: TextField(
            controller: c,
            decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)))),
      );
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, this.hot = false});

  final String label;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: hot
            ? const LinearGradient(
                colors: [Color(0xFFFF7AB4), Color(0xFFB044FF)])
            : null,
        color: hot ? null : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: hot ? null : Border.all(color: const Color(0xFFE4DFFF)),
      ),
      child: Text(label,
          style: TextStyle(
              color: hot ? Colors.white : const Color(0xFF24213F),
              fontSize: 11.5,
              fontWeight: FontWeight.w900)),
    );
  }
}
