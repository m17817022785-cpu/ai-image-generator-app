enum MessageType { text, image }

class Message {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  String content; // 流式更新需要可变
  final MessageType type;

  /// 兼容旧版：单张上传文件本地路径。
  final String? localFilePath;

  /// 兼容旧版：单张上传图片 base64 编码。
  final String? base64Image;

  /// 新版：多张参考图本地路径。
  final List<String> localFilePaths;

  /// 新版：多张参考图 base64 编码，用于多模态请求。
  final List<String> base64Images;

  /// 图片消息元数据：用于作品库、复用提示词、继续编辑。
  final String? imagePrompt;
  final String? originalPrompt;
  final String? imageModel;
  final String? imageSize;
  final String? imageQuality;
  final String? imageAspectRatio;
  final List<String> referenceImagePaths;

  bool isGenerating; // 是否正在处于打字机流式生成状态
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
    this.imagePrompt,
    this.originalPrompt,
    this.imageModel,
    this.imageSize,
    this.imageQuality,
    this.imageAspectRatio,
    List<String>? referenceImagePaths,
    this.isGenerating = false,
    DateTime? timestamp,
  })  : localFilePaths = localFilePaths ??
            (localFilePath == null
                ? const <String>[]
                : <String>[localFilePath]),
        base64Images = base64Images ??
            (base64Image == null ? const <String>[] : <String>[base64Image]),
        referenceImagePaths = referenceImagePaths ?? const <String>[],
        timestamp = timestamp ?? DateTime.now();

  List<String> get effectiveLocalFilePaths {
    if (localFilePaths.isNotEmpty)
      return localFilePaths.where((e) => e.trim().isNotEmpty).toList();
    final single = localFilePath;
    return single == null || single.trim().isEmpty
        ? const <String>[]
        : <String>[single];
  }

  List<String> get effectiveBase64Images {
    if (base64Images.isNotEmpty)
      return base64Images.where((e) => e.trim().isNotEmpty).toList();
    final single = base64Image;
    return single == null || single.trim().isEmpty
        ? const <String>[]
        : <String>[single];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'type': type.name,
        'localFilePath': localFilePath,
        // 历史记录不持久化 base64 图片，避免 SharedPreferences 因大图过大而写入失败。
        // 恢复历史时仍保留文字、图片 URL/data 消息和本地参考图路径。
        'base64Image': null,
        'localFilePaths': localFilePaths,
        'base64Images': const <String>[],
        'imagePrompt': imagePrompt,
        'originalPrompt': originalPrompt,
        'imageModel': imageModel,
        'imageSize': imageSize,
        'imageQuality': imageQuality,
        'imageAspectRatio': imageAspectRatio,
        'referenceImagePaths': referenceImagePaths,
        'isGenerating': false,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) {
      if (value is List)
        return value
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      return const <String>[];
    }

    final rawType = json['type']?.toString() ?? 'text';
    final parsedType = MessageType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => MessageType.text,
    );
    return Message(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      type: parsedType,
      localFilePath: json['localFilePath']?.toString(),
      base64Image: json['base64Image']?.toString(),
      localFilePaths: stringList(json['localFilePaths']),
      base64Images: stringList(json['base64Images']),
      imagePrompt: json['imagePrompt']?.toString(),
      originalPrompt: json['originalPrompt']?.toString(),
      imageModel: json['imageModel']?.toString(),
      imageSize: json['imageSize']?.toString(),
      imageQuality: json['imageQuality']?.toString(),
      imageAspectRatio: json['imageAspectRatio']?.toString(),
      referenceImagePaths: stringList(json['referenceImagePaths']),
      isGenerating: json['isGenerating'] == true,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  // 转换成 OpenAI API 标准的消息格式
  Map<String, dynamic> toOpenAiMap() {
    final images = effectiveBase64Images;
    if (images.isNotEmpty) {
      // OpenAI 多模态消息格式，支持多张图片。
      return {
        'role': role,
        'content': [
          {
            'type': 'text',
            'text': content.isNotEmpty
                ? content
                : (images.length > 1 ? '分析这些图片' : '分析这张图片')
          },
          ...images.map((image) => {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$image'}
              }),
        ]
      };
    }
    // 普通文本消息格式
    return {
      'role': role,
      'content': content,
    };
  }
}
