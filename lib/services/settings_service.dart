import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyApiKey = 'api_key';
  static const String _keyBaseUrl = 'base_url';
  static const String _keyChatModel = 'chat_model';
  static const String _keyImageModel = 'image_model';

  Future<void> saveSettings({
    required String apiKey,
    required String baseUrl,
    required String chatModel,
    required String imageModel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey);
    await prefs.setString(_keyBaseUrl, baseUrl);
    await prefs.setString(_keyChatModel, chatModel);
    await prefs.setString(_keyImageModel, imageModel);
  }

  Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'apiKey': prefs.getString(_keyApiKey) ?? '',
      'baseUrl': prefs.getString(_keyBaseUrl) ?? 'https://api.openai.com/v1',
      'chatModel': prefs.getString(_keyChatModel) ?? 'gpt-4o-mini',
      'imageModel': prefs.getString(_keyImageModel) ?? 'dall-e-3',
    };
  }
}
