import 'package:shared_preferences/shared_preferences.dart';

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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, apiKey);
    await prefs.setString(_keyImageApiKey, (imageApiKey ?? '').trim());
    await prefs.setString(_keyBaseUrl, baseUrl);
    await prefs.setString(_keyImageBaseUrl, (imageBaseUrl ?? '').trim());
    await prefs.setString(_keyChatModel, chatModel);
    await prefs.setString(_keyImageModel, imageModel);
    await prefs.setString(_keyImageEditModel, (imageEditModel ?? 'gpt-image-1').trim());
    await prefs.setString(_keyImageAspectRatio, imageAspectRatio.trim().isEmpty ? '1:1' : imageAspectRatio.trim());
    await prefs.setString(_keyImageQuality, imageQuality.trim().isEmpty ? 'auto' : imageQuality.trim());
    await prefs.setBool(_keyEnhanceImagePrompt, enhanceImagePrompt);
  }

  Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyBaseUrl) ?? 'https://api.openai.com/v1';
    final imageBaseUrl = prefs.getString(_keyImageBaseUrl) ?? '';
    final imageApiKey = prefs.getString(_keyImageApiKey) ?? '';
    return {
      'apiKey': prefs.getString(_keyApiKey) ?? '',
      // 为空表示图片工具令牌沿用聊天令牌，兼容老版本设置。
      'imageApiKey': imageApiKey,
      'baseUrl': baseUrl,
      // 为空表示图片工具接口沿用聊天接口，兼容老版本设置。
      'imageBaseUrl': imageBaseUrl,
      'chatModel': prefs.getString(_keyChatModel) ?? 'gpt-4o-mini',
      'imageModel': prefs.getString(_keyImageModel) ?? 'dall-e-3',
      'imageEditModel': prefs.getString(_keyImageEditModel) ?? 'gpt-image-1',
      'imageAspectRatio': prefs.getString(_keyImageAspectRatio) ?? '1:1',
      'imageQuality': prefs.getString(_keyImageQuality) ?? 'auto',
      'enhanceImagePrompt': (prefs.getBool(_keyEnhanceImagePrompt) ?? true).toString(),
    };
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
  }
}
