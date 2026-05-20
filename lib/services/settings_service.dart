import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyApiKey = 'api_key';
  static const String _keyImageApiKey = 'image_api_key';
  static const String _keyBaseUrl = 'base_url';
  static const String _keyImageBaseUrl = 'image_base_url';
  static const String _keyChatModel = 'chat_model';
  static const String _keyImageModel = 'image_model';

  Future<void> saveSettings({
    required String apiKey,
    String? imageApiKey,
    required String baseUrl,
    String? imageBaseUrl,
    required String chatModel,
    required String imageModel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey);
    await prefs.setString(_keyImageApiKey, (imageApiKey ?? '').trim());
    await prefs.setString(_keyBaseUrl, baseUrl);
    await prefs.setString(_keyImageBaseUrl, (imageBaseUrl ?? '').trim());
    await prefs.setString(_keyChatModel, chatModel);
    await prefs.setString(_keyImageModel, imageModel);
  }

  Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyBaseUrl) ?? 'https://api.openai.com/v1';
    final imageBaseUrl = prefs.getString(_keyImageBaseUrl) ?? '';
    final imageApiKey = prefs.getString(_keyImageApiKey) ?? '';
    return {
      'apiKey': prefs.getString(_keyApiKey) ?? '',
      // 为空表示生图令牌沿用聊天令牌，兼容老版本设置。
      'imageApiKey': imageApiKey,
      'baseUrl': baseUrl,
      // 为空表示生图接口沿用聊天接口，兼容老版本设置。
      'imageBaseUrl': imageBaseUrl,
      'chatModel': prefs.getString(_keyChatModel) ?? 'gpt-4o-mini',
      'imageModel': prefs.getString(_keyImageModel) ?? 'dall-e-3',
    };
  }
}
