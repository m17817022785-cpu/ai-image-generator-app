enum MessageType { text, image }

class Message {
  final String id;
  final String role;
  String content;
  final MessageType type;
  final String? localFilePath;
  final String? base64Image;
  final List<String> localFilePaths;
  final List<String> base64Images;
  bool isGenerating;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.role,
    required this.content,
    this.type = MessageType.text,
    this.localFilePath,
    this.base64Image,
    List<String>? localFilePaths,
    List<String>? base64Images,
    this.isGenerating = false,
    DateTime? timestamp,
  })  : localFilePaths = localFilePaths ?? (localFilePath == null ? const <String>[] : <String>[localFilePath]),
        base64Images = base64Images ?? (base64Image == null ? const <String>[] : <String>[base64Image]),
        timestamp = timestamp ?? DateTime.now();

  List<String> get effectiveLocalFilePaths {
    if (localFilePaths.isNotEmpty) return localFilePaths.where((e) => e.trim().isNotEmpty).toList();
    final single = localFilePath;
    return single == null || single.trim().isEmpty ? const <String>[] : <String>[single];
  }

  List<String> get effectiveBase64Images {
    if (base64Images.isNotEmpty) return base64Images.where((e) => e.trim().isNotEmpty).toList();
    final single = base64Image;
    return single == null || single.trim().isEmpty ? const <String>[] : <String>[single];
  }

  Map<String, dynamic> toOpenAiMap() {
    final images = effectiveBase64Images;
    if (images.isNotEmpty) {
      return {
        'role': role,
        'content': [
          {'type': 'text', 'text': content.isNotEmpty ? content : (images.length > 1 ? '分析这些图片' : '分析这张图片')},
          ...images.map((image) => {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$image'}}),
        ]
      };
    }
    return {'role': role, 'content': content};
  }
}
