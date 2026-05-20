enum MessageType { text, image }

class Message {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  String content; // 流式更新需要可变
  final MessageType type;
  final String? localFilePath; // 关联的上传文件本地路径
  final String? base64Image; // 上传图片的 base64 编码，用于多模态
  bool isGenerating; // 是否正在处于打字机流式生成状态
  final DateTime timestamp;

  Message({
    required this.id,
    required this.role,
    required this.content,
    this.type = MessageType.text,
    this.localFilePath,
    this.base64Image,
    this.isGenerating = false,
    DateTime? timestamp,
  }) : this.timestamp = timestamp ?? DateTime.now();

  // 转换成 OpenAI API 标准的消息格式
  Map<String, dynamic> toOpenAiMap() {
    if (base64Image != null && base64Image!.isNotEmpty) {
      // OpenAI 多模态消息格式
      return {
        'role': role,
        'content': [
          {
            'type': 'text',
            'text': content.isNotEmpty ? content : '分析这张图片'
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image'
            }
          }
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
