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

  factory ChatHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ChatHistoryEntry(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title']?.toString() ?? '未命名会话',
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        messages: (json['messages'] is List)
            ? (json['messages'] as List)
                .whereType<Map>()
                .map((e) => Message.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const <Message>[],
      );
}

class ArtworkEntry {
  final String id;
  final String image;
  final String prompt;
  final String originalPrompt;
  final String model;
  final String size;
  final String quality;
  final String aspectRatio;
  final List<String> referenceImagePaths;
  final DateTime createdAt;
  final bool favorite;

  const ArtworkEntry({
    required this.id,
    required this.image,
    required this.prompt,
    required this.originalPrompt,
    required this.model,
    required this.size,
    required this.quality,
    required this.aspectRatio,
    required this.referenceImagePaths,
    required this.createdAt,
    this.favorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'image': image,
        'prompt': prompt,
        'originalPrompt': originalPrompt,
        'model': model,
        'size': size,
        'quality': quality,
        'aspectRatio': aspectRatio,
        'referenceImagePaths': referenceImagePaths,
        'createdAt': createdAt.toIso8601String(),
        'favorite': favorite,
      };

  ArtworkEntry copyWith({bool? favorite}) => ArtworkEntry(
        id: id,
        image: image,
        prompt: prompt,
        originalPrompt: originalPrompt,
        model: model,
        size: size,
        quality: quality,
        aspectRatio: aspectRatio,
        referenceImagePaths: referenceImagePaths,
        createdAt: createdAt,
        favorite: favorite ?? this.favorite,
      );

  factory ArtworkEntry.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) {
      if (value is List)
        return value
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      return const <String>[];
    }

    return ArtworkEntry(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      image: json['image']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      originalPrompt: json['originalPrompt']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      aspectRatio: json['aspectRatio']?.toString() ?? '',
      referenceImagePaths: stringList(json['referenceImagePaths']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      favorite: json['favorite'] == true,
    );
  }
}

class ProviderProfile {
  final String id;
  final String name;
  final String apiKey;
  final String imageApiKey;
  final String baseUrl;
  final String imageBaseUrl;
  final String chatModel;
  final String imageModel;
  final String imageEditModel;
  final DateTime updatedAt;

  const ProviderProfile({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.imageApiKey,
    required this.baseUrl,
    required this.imageBaseUrl,
    required this.chatModel,
    required this.imageModel,
    required this.imageEditModel,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'apiKey': apiKey,
        'imageApiKey': imageApiKey,
        'baseUrl': baseUrl,
        'imageBaseUrl': imageBaseUrl,
        'chatModel': chatModel,
        'imageModel': imageModel,
        'imageEditModel': imageEditModel,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProviderProfile.fromJson(Map<String, dynamic> json) =>
      ProviderProfile(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name']?.toString() ?? '未命名配置',
        apiKey: json['apiKey']?.toString() ?? '',
        imageApiKey: json['imageApiKey']?.toString() ?? '',
        baseUrl: json['baseUrl']?.toString() ?? '',
        imageBaseUrl: json['imageBaseUrl']?.toString() ?? '',
        chatModel: json['chatModel']?.toString() ?? '',
        imageModel: json['imageModel']?.toString() ?? '',
        imageEditModel: json['imageEditModel']?.toString() ?? '',
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class SettingsService {
  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultChatModel = 'gpt-4o-mini';
  static const String defaultImageModel = 'dall-e-3';
  static const String defaultImageEditModel = 'gpt-image-1';

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
  static const String _keyArtworkLibrary = 'artwork_library_v1';
  static const String _keyProviderProfiles = 'provider_profiles_v1';
  static const int _maxHistoryItems = 30;
  static const int _maxArtworkItems = 120;

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
    await prefs.setString(_keyImageAspectRatio,
        imageAspectRatio.trim().isEmpty ? '1:1' : imageAspectRatio.trim());
    await prefs.setString(_keyImageQuality,
        imageQuality.trim().isEmpty ? 'auto' : imageQuality.trim());
    await prefs.setBool(_keyEnhanceImagePrompt, enhanceImagePrompt);
    await prefs.setInt(_keyImageCount, imageCount.clamp(1, 4).toInt());
    if (studioHeaderCollapsed != null)
      await prefs.setBool(_keyStudioHeaderCollapsed, studioHeaderCollapsed);
  }

  Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyBaseUrl) ?? defaultBaseUrl;
    final imageBaseUrl = prefs.getString(_keyImageBaseUrl) ?? '';
    final imageApiKey = prefs.getString(_keyImageApiKey) ?? '';
    return {
      'apiKey': prefs.getString(_keyApiKey) ?? '',
      // 为空表示图片工具令牌沿用聊天令牌，兼容老版本设置。
      'imageApiKey': imageApiKey,
      'baseUrl': baseUrl,
      // 为空表示图片工具接口沿用聊天接口，兼容老版本设置。
      'imageBaseUrl': imageBaseUrl,
      'chatModel': prefs.getString(_keyChatModel) ?? defaultChatModel,
      'imageModel': prefs.getString(_keyImageModel) ?? defaultImageModel,
      'imageEditModel':
          prefs.getString(_keyImageEditModel) ?? defaultImageEditModel,
      'imageAspectRatio': prefs.getString(_keyImageAspectRatio) ?? '1:1',
      'imageQuality': prefs.getString(_keyImageQuality) ?? 'auto',
      'enhanceImagePrompt':
          (prefs.getBool(_keyEnhanceImagePrompt) ?? true).toString(),
      'imageCount': (prefs.getInt(_keyImageCount) ?? 1).clamp(1, 4).toString(),
      'studioHeaderCollapsed':
          (prefs.getBool(_keyStudioHeaderCollapsed) ?? true).toString(),
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
    await prefs.setString(
        _keyChatHistory,
        jsonEncode(
            next.take(_maxHistoryItems).map((e) => e.toJson()).toList()));
  }

  Future<void> deleteChatHistory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (await getChatHistory()).where((e) => e.id != id).toList();
    await prefs.setString(
        _keyChatHistory, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  Future<void> clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyChatHistory);
  }

  Future<List<ArtworkEntry>> getArtworkLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyArtworkLibrary);
    if (raw == null || raw.trim().isEmpty) return const <ArtworkEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ArtworkEntry>[];
      final items = decoded
          .whereType<Map>()
          .map((e) => ArtworkEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.image.trim().isNotEmpty)
          .toList()
        ..sort((a, b) {
          if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
      return items.take(_maxArtworkItems).toList();
    } catch (_) {
      return const <ArtworkEntry>[];
    }
  }

  Future<void> upsertArtwork(ArtworkEntry entry) async {
    if (entry.image.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await getArtworkLibrary();
    final next = <ArtworkEntry>[
      entry,
      ...items.where((e) => e.id != entry.id),
    ]..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    await prefs.setString(
        _keyArtworkLibrary,
        jsonEncode(
            next.take(_maxArtworkItems).map((e) => e.toJson()).toList()));
  }

  Future<void> deleteArtwork(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (await getArtworkLibrary()).where((e) => e.id != id).toList();
    await prefs.setString(
        _keyArtworkLibrary, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  Future<void> clearArtworkLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyArtworkLibrary);
  }

  Future<List<ProviderProfile>> getProviderProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProviderProfiles);
    if (raw == null || raw.trim().isEmpty) return const <ProviderProfile>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ProviderProfile>[];
      final items = decoded
          .whereType<Map>()
          .map((e) => ProviderProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (_) {
      return const <ProviderProfile>[];
    }
  }

  Future<void> upsertProviderProfile(ProviderProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getProviderProfiles();
    final next = <ProviderProfile>[
      profile,
      ...items.where((e) => e.id != profile.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await prefs.setString(
        _keyProviderProfiles, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  Future<void> deleteProviderProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next =
        (await getProviderProfiles()).where((e) => e.id != id).toList();
    await prefs.setString(
        _keyProviderProfiles, jsonEncode(next.map((e) => e.toJson()).toList()));
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
