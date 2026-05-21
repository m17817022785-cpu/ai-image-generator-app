from pathlib import Path
import re

home = Path('lib/screens/home_screen.dart')
api = Path('lib/services/api_service.dart')

s = home.read_text(encoding='utf-8')
s = s.replace("      imageFile: decision.action == ToolAction.imageToImage ? imageFile : null,\n      base64Image: null, base64Images: base64Images,", "      imageFiles: decision.action == ToolAction.imageToImage ? imageFiles : const <File>[],\n      base64Images: decision.action == ToolAction.imageToImage ? base64Images : const <String>[] ,")
s = s.replace("const <String>[] ,", "const <String>[],")
s = s.replace("await _finishImageMessage(placeholder: placeholder, prompt: prompt, imageFile: imageFile, base64Image: null, base64Images: base64Images, quality: quality);", "await _finishImageMessage(placeholder: placeholder, prompt: prompt, imageFiles: imageFiles, base64Images: base64Images, quality: quality);")
s = re.sub(r"\n\s*if \(_attachedFiles\.isNotEmpty\) Container\(margin: const EdgeInsets\.only\(bottom: 8\).*?_primary\)\)\)\),", "\n          if (_attachedFiles.isNotEmpty) _attachedPreviewStrip(),", s, count=1, flags=re.S)
s = s.replace("if (msg.localFilePath != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('参考图：${msg.localFilePath!.split('/').last}', style: TextStyle(color: user ? Colors.white70 : _muted, fontSize: 12)))", "if (msg.effectiveLocalFilePaths.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('参考图：${msg.effectiveLocalFilePaths.length} 张', style: TextStyle(color: user ? Colors.white70 : _muted, fontSize: 12)))")
home.write_text(s, encoding='utf-8')

t = api.read_text(encoding='utf-8')
if 'List<String> _effectiveImages(' not in t:
    marker = "  Map<String, dynamic> _imageContentMessage(String role, String text, String? base64Image) {"
    helper = """  List<String> _effectiveImages(String? base64Image, List<String>? base64Images) {
    final images = <String>[];
    if (base64Images != null) images.addAll(base64Images.map((e) => e.trim()).where((e) => e.isNotEmpty));
    if (images.isEmpty && base64Image != null && base64Image.trim().isNotEmpty) images.add(base64Image.trim());
    return images;
  }

"""
    t = t.replace(marker, helper + marker, 1)

t = t.replace("Map<String, dynamic> _imageContentMessage(String role, String text, String? base64Image) {", "Map<String, dynamic> _imageContentMessage(String role, String text, String? base64Image, {List<String>? base64Images}) {")
t = re.sub(r"if \(base64Image != null && base64Image\.trim\(\)\.isNotEmpty\) \{\s*return \{\s*'role': role,\s*'content': \[\s*\{'type': 'text', 'text': text\},\s*\{'type': 'image_url', 'image_url': \{'url': 'data:image/jpeg;base64,\$base64Image'\}\},\s*\]\s*\};\s*\}", "final images = _effectiveImages(base64Image, base64Images);\n    if (images.isNotEmpty) {\n      return {'role': role, 'content': [{'type': 'text', 'text': text}, ...images.map((image) => {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$image'}})]};\n    }", t, count=1, flags=re.S)

t = t.replace("Future<ToolDecision> decideTool({required String userText, required String? base64Image, required String apiKey, required String baseUrl, required String model})", "Future<ToolDecision> decideTool({required String userText, required String? base64Image, List<String>? base64Images, required String apiKey, required String baseUrl, required String model})")
t = t.replace("Future<String> refineImagePrompt({required String userText, required String? base64Image, required String apiKey, required String baseUrl, required String model, required String aspectRatio, required String size, required String quality, required bool isEdit})", "Future<String> refineImagePrompt({required String userText, required String? base64Image, List<String>? base64Images, required String apiKey, required String baseUrl, required String model, required String aspectRatio, required String size, required String quality, required bool isEdit})")
t = t.replace("_imageContentMessage('user', decisionText, base64Image)", "_imageContentMessage('user', decisionText, null, base64Images: _effectiveImages(base64Image, base64Images))")
t = t.replace("_imageContentMessage('user', userInstruction, base64Image)", "_imageContentMessage('user', userInstruction, null, base64Images: _effectiveImages(base64Image, base64Images))")
t = t.replace("final hasImage = base64Image != null && base64Image.trim().isNotEmpty;", "final hasImage = _effectiveImages(base64Image, base64Images).isNotEmpty;")

if 'Future<String> editImages(' not in t:
    method = """
  Future<String> editImages(String prompt, List<File> imageFiles, String apiKey, String baseUrl, String model, {String size = '1024x1024', String quality = 'auto'}) async {
    if (imageFiles.isEmpty) return generateImage(prompt, apiKey, baseUrl, model, size: size, quality: quality);
    if (imageFiles.length == 1) return editImage(prompt, imageFiles.first, apiKey, baseUrl, model, size: size, quality: quality);
    if (_useChatImageEndpoint(baseUrl)) {
      final images = <String>[];
      for (final file in imageFiles) {
        images.add(base64Encode(await file.readAsBytes()));
      }
      return _callChatStyleImageTool(prompt: prompt, base64Image: null, base64Images: images, apiKey: apiKey, baseUrl: baseUrl, model: model, size: size, quality: quality, category: 'image_to_image', title: '图生图 / 图片编辑');
    }
    final url = _endpoint(baseUrl, '/images/edits');
    final editModel = normalizeImageEditModel(model);
    final qualityValue = _normalizeImageQuality(quality, editModel);
    final request = http.MultipartRequest('POST', url)
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ' + apiKey.trim()
      ..fields['model'] = editModel
      ..fields['prompt'] = prompt
      ..fields['n'] = '1'
      ..fields['size'] = size;
    if (qualityValue != null) request.fields['quality'] = qualityValue;
    for (final file in imageFiles) {
      request.files.add(await http.MultipartFile.fromPath('image', file.path));
    }
    final response = await http.Response.fromStream(await request.send());
    final bodyText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_friendlyImageError(bodyText, model, editModel, '图生图 / 图片编辑'));
    return _extractImageResult(bodyText, endpoint: url.toString(), model: editModel, category: 'image_to_image');
  }
"""
    t = t.replace("\n  Future<String> _callChatStyleImageTool", method + "\n  Future<String> _callChatStyleImageTool", 1)

t = t.replace("Future<String> _callChatStyleImageTool({required String prompt, required String? base64Image, required String apiKey, required String baseUrl, required String model, required String size, String quality = 'auto', required String category, required String title})", "Future<String> _callChatStyleImageTool({required String prompt, required String? base64Image, List<String>? base64Images, required String apiKey, required String baseUrl, required String model, required String size, String quality = 'auto', required String category, required String title})")
t = t.replace("final hasImage = base64Image != null && base64Image.trim().isNotEmpty;\n    final instruction = hasImage", "final images = _effectiveImages(base64Image, base64Images);\n    final hasImage = images.isNotEmpty;\n    final instruction = hasImage")
t = t.replace("_imageContentMessage('user', instruction, base64Image)", "_imageContentMessage('user', instruction, null, base64Images: images)")
api.write_text(t, encoding='utf-8')
print('patched api_service.dart and home_screen.dart compile errors')
