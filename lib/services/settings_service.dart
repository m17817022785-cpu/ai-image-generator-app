import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

class ChatHistoryEntry {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<Message> messages;

  const ChatHistoryEntry({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatHistoryEntry.fromJson(Map<String, dynamic> json) => ChatHistoryEntry(
        id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title']?.toString() ?? '未命名会话',
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        messages: (json['messages'] is List)
            ? (json['messages'] as List)
                .whereType<Map>()
                .map((e) => Message.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const <Message>[],
      );
}

class SettingsService {
  static const String _keyApiKey = 'api_key';
  static const String _keyImageApiKey = 'image_api_key';
  static const String _keyBaseUrl = 'base_url';
  static const String _keyImageBaseUrl = 'image_base_url';
  static const String _keyChatModel = 'chat_model';
  static const String _keyImageModel = 'image_model';
  static const String _keyImageEditModel = 'image_edit_model';
  static const String _keyImageAspectRatio = 'image_aspect_ratio';
  static const String _keyImageQuality = 'image_quality';
  static const String _keyEnhanceImagePrompt = 'enhance_image_prompt';
  static const String _keyImageCount = 'image_count';
  static const String _keyStudioHeaderCollapsed = 'studio_header_collapsed';
  static const String _keyChatHistory = 'chat_history_v1';
  static const int _maxHistoryItems = 30;

  Future<void> saveSettings({
    required String apiKey,
    String? imageApiKey,
    required String baseUrl,
    String? imageBaseUrl,
    required String chatModel,
    required String imageModel,
    String? imageEditModel,
    String imageAspectRatio = '1:1',
    String imageQuality = 'auto',
    bool enhanceImagePrompt = true,
    int imageCount = 1,
    bool? studioHeaderCollapsed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey);
    await prefs.setString(_keyImageApiKey, (imageApiKey ?? '').trim());
    await prefs.setString(_keyBaseUrl, baseUrl);
    await prefs.setString(_keyImageBaseUrl, (imageBaseUrl ?? '').trim());
    await prefs.setString(_keyChatModel, chatModel);
    await prefs.setString(_keyImageModel, imageModel);
    await prefs.setString(_keyImageEditModel, (imageEditModel ?? '').trim());
    await prefs.setString(_keyImageAspectRatio, imageAspectRatio.trim().isEmpty ? '1:1' : imageAspectRatio.trim());
    await prefs.setString(_keyImageQuality, imageQuality.trim().isEmpty ? 'auto' : imageQuality.trim());
    await prefs.setBool(_keyEnhanceImagePrompt, enhanceImagePrompt);
    await prefs.setInt(_keyImageCount, imageCount.clamp(1, 4).toInt());
    if (studioHeaderCollapsed != null) await prefs.setBool(_keyStudioHeaderCollapsed, studioHeaderCollapsed);
  }

  Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyBaseUrl) ?? '';
    final imageBaseUrl = prefs.getString(_keyImageBaseUrl) ?? '';
    final imageApiKey = prefs.getString(_keyImageApiKey) ?? '';
    return {
      'apiKey': prefs.getString(_keyApiKey) ?? '',
      // 为空表示图片工具令牌沿用聊天令牌，兼容老版本设置。
      'imageApiKey': imageApiKey,
      'baseUrl': baseUrl,
      // 为空表示图片工具接口沿用聊天接口，兼容老版本设置。
      'imageBaseUrl': imageBaseUrl,
      'chatModel': prefs.getString(_keyChatModel) ?? '',
      'imageModel': prefs.getString(_keyImageModel) ?? '',
      'imageEditModel': prefs.getString(_keyImageEditModel) ?? '',
      'imageAspectRatio': prefs.getString(_keyImageAspectRatio) ?? '1:1',
      'imageQuality': prefs.getString(_keyImageQuality) ?? 'auto',
      'enhanceImagePrompt': (prefs.getBool(_keyEnhanceImagePrompt) ?? true).toString(),
      'imageCount': (prefs.getInt(_keyImageCount) ?? 1).clamp(1, 4).toString(),
      'studioHeaderCollapsed': (prefs.getBool(_keyStudioHeaderCollapsed) ?? true).toString(),
    };
  }

  Future<List<ChatHistoryEntry>> getChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyChatHistory);
    if (raw == null || raw.trim().isEmpty) return const <ChatHistoryEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ChatHistoryEntry>[];
      final items = decoded
          .whereType<Map>()
          .map((e) => ChatHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.messages.isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items.take(_maxHistoryItems).toList();
    } catch (_) {
      return const <ChatHistoryEntry>[];
    }
  }

  Future<void> upsertChatHistory(ChatHistoryEntry entry) async {
    if (entry.messages.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await getChatHistory();
    final next = <ChatHistoryEntry>[
      entry,
      ...items.where((e) => e.id != entry.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await prefs.setString(_keyChatHistory, jsonEncode(next.take(_maxHistoryItems).map((e) => e.toJson()).toList()));
  }

  Future<void> deleteChatHistory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (await getChatHistory()).where((e) => e.id != id).toList();
    await prefs.setString(_keyChatHistory, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  Future<void> clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyChatHistory);
  }

  Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyApiKey);
    await prefs.remove(_keyImageApiKey);
    await prefs.remove(_keyBaseUrl);
    await prefs.remove(_keyImageBaseUrl);
    await prefs.remove(_keyChatModel);
    await prefs.remove(_keyImageModel);
    await prefs.remove(_keyImageEditModel);
    await prefs.remove(_keyImageAspectRatio);
    await prefs.remove(_keyImageQuality);
    await prefs.remove(_keyEnhanceImagePrompt);
    await prefs.remove(_keyImageCount);
    await prefs.remove(_keyStudioHeaderCollapsed);
  }
}
