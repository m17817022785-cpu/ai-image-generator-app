from pathlib import Path
import re

p=Path('lib/screens/home_screen.dart')
s=p.read_text(encoding='utf-8')

def rep(a,b):
    global s
    if a in s:
        s=s.replace(a,b,1)
    elif b not in s:
        raise SystemExit('missing snippet: '+a[:120])

rep('  bool _enhanceImagePrompt = true;\n  File? _attachedFile;\n  String? _attachedBase64;', '  bool _enhanceImagePrompt = true;\n  int _imageCount = 1;\n  final List<File> _attachedFiles = [];\n  final List<String> _attachedBase64Images = [];')
rep("  static const _qualityOptions = ['auto', 'standard', 'hd', 'low', 'medium', 'high'];", "  static const _qualityOptions = ['auto', 'standard', 'hd', 'low', 'medium', 'high'];\n  static const _imageCountOptions = [1, 2, 3, 4];\n  static const _maxReferenceImages = 8;")
rep("        _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';", "        _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';\n        _imageCount = int.tryParse(s['imageCount'] ?? '1')?.clamp(1, 4).toInt() ?? 1;")
rep('        enhanceImagePrompt: _enhanceImagePrompt,', '        enhanceImagePrompt: _enhanceImagePrompt,\n        imageCount: _imageCount,')

old_pick='''  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;
    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _attachedFile = file;
      _attachedBase64 = base64Encode(bytes);
    });
  }'''
new_pick='''  Future<void> _pickImage() async {
    final remaining = _maxReferenceImages - _attachedFiles.length;
    if (remaining <= 0) {
      _snack('最多支持 $_maxReferenceImages 张参考图，请先删除部分图片。');
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;
    final files = <File>[];
    final images = <String>[];
    for (final item in picked.take(remaining)) {
      final file = File(item.path);
      files.add(file);
      images.add(base64Encode(await file.readAsBytes()));
    }
    if (!mounted) return;
    setState(() {
      _attachedFiles.addAll(files);
      _attachedBase64Images.addAll(images);
    });
    if (picked.length > remaining) _snack('最多支持 $_maxReferenceImages 张参考图，已添加前 $remaining 张。');
  }

  void _removeAttachedImage(int index) {
    if (index < 0 || index >= _attachedFiles.length) return;
    setState(() {
      _attachedFiles.removeAt(index);
      if (index < _attachedBase64Images.length) _attachedBase64Images.removeAt(index);
    });
  }

  void _clearAttachedImages() {
    setState(() {
      _attachedFiles.clear();
      _attachedBase64Images.clear();
    });
  }'''
rep(old_pick,new_pick)

s=s.replace('final file = _attachedFile;\n    final b64 = _attachedBase64;', 'final files = List<File>.from(_attachedFiles);\n    final b64s = List<String>.from(_attachedBase64Images);')
s=s.replace('if (text.isEmpty && file == null) return;', 'if (text.isEmpty && files.isEmpty) return;')
s=s.replace("final content = text.isEmpty ? '请根据这张图片继续处理' : text;", "final content = text.isEmpty ? (files.length > 1 ? '请根据这些图片继续处理' : '请根据这张图片继续处理') : text;")
s=s.replace('localFilePath: file?.path, base64Image: b64', 'localFilePaths: files.map((e) => e.path).toList(), base64Images: b64s')
s=s.replace('_attachedFile = null;\n      _attachedBase64 = null;', '_attachedFiles.clear();\n      _attachedBase64Images.clear();')
s=s.replace("'hasImage': file != null", "'referenceImageCount': files.length, 'generateImageCount': _imageCount")
s=s.replace('imageFile: file, base64Image: b64', 'imageFiles: files, base64Images: b64s')

s=s.replace('required File? imageFile, required String? base64Image', 'required List<File> imageFiles, required List<String> base64Images')
s=s.replace('base64Image: base64Image', 'base64Image: null, base64Images: base64Images')
s=s.replace('imageFile: decision.action == ToolAction.imageToImage ? imageFile : null,\n      base64Image: base64Image,', 'imageFiles: decision.action == ToolAction.imageToImage ? imageFiles : const <File>[],\n      base64Images: decision.action == ToolAction.imageToImage ? base64Images : const <String>[],')
s=s.replace('imageFile == null ? \'正在构建画面…\' : \'正在分析参考图并生成新画面…\'', 'imageFiles.isEmpty ? \'正在构建画面…\' : \'正在读取参考图并生成新画面…\'')
s=s.replace('imageFile: imageFile, base64Image: base64Image', 'imageFiles: imageFiles, base64Images: base64Images')
s=s.replace('isEdit: imageFile != null', 'isEdit: imageFiles.isNotEmpty')

old_gen='''    if (mounted) setState(() => placeholder.content = imageFile == null ? '正在生成 $_imageAspectRatio 画面…' : '正在编辑 $_imageAspectRatio 参考图…');
    final image = imageFile == null
        ? await _api.generateImage(finalPrompt, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageModel, size: _selectedSize, quality: quality)
        : await _api.editImage(finalPrompt, imageFile, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageEditModel, size: _selectedSize, quality: quality);
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == placeholder.id);
      if (index >= 0) _messages[index] = Message(id: placeholder.id, role: 'assistant', content: image, type: MessageType.image);
    });'''
new_gen='''    final total = _imageCount.clamp(1, 4).toInt();
    final generated = <String>[];
    try {
      for (var i = 0; i < total; i++) {
        if (mounted) setState(() => placeholder.content = imageFiles.isEmpty ? '正在生成第 ${i + 1} / $total 张 $_imageAspectRatio 画面…' : '正在参考 ${imageFiles.length} 张图生成第 ${i + 1} / $total 张 $_imageAspectRatio 画面…');
        final image = imageFiles.isEmpty
            ? await _api.generateImage(finalPrompt, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageModel, size: _selectedSize, quality: quality)
            : await _api.editImages(finalPrompt, imageFiles, _effectiveImageApiKey, _effectiveImageBaseUrl, _effectiveImageEditModel, size: _selectedSize, quality: quality);
        generated.add(image);
        if (!mounted) return;
        setState(() {
          if (i == 0) {
            final index = _messages.indexWhere((m) => m.id == placeholder.id);
            if (index >= 0) _messages[index] = Message(id: placeholder.id, role: 'assistant', content: image, type: MessageType.image);
          } else {
            _messages.add(Message(id: '${DateTime.now().microsecondsSinceEpoch + i}', role: 'assistant', content: image, type: MessageType.image));
          }
        });
        _scrollBottom();
      }
      if (generated.length > 1) _snack('已生成 ${generated.length} 张图片');
    } catch (e) {
      if (generated.isNotEmpty) {
        _snack('已生成 ${generated.length} / $total 张，后续生成失败：$e');
        return;
      }
      rethrow;
    }'''
rep(old_gen,new_gen)

s=s.replace('· ${_qualityLabel(_imageQuality)}画质', '· ${_qualityLabel(_imageQuality)}画质 · $_imageCount 张')
s=s.replace("· ${_enhanceImagePrompt ? '润色开' : '润色关'}", "· $_imageCount 张 · ${_enhanceImagePrompt ? '润色开' : '润色关'}")
s=s.replace('_attachedFile != null', '_attachedFiles.isNotEmpty')

insert='''  Widget _attachedPreviewStrip() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFEFFFFD), borderRadius: BorderRadius.circular(18), border: Border.all(color: _cyan.withOpacity(.8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.image_rounded, color: _cyan), const SizedBox(width: 8), Expanded(child: Text('参考图 ${_attachedFiles.length} / $_maxReferenceImages，可继续追加或单张删除', style: const TextStyle(color: _text, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)), TextButton(onPressed: _clearAttachedImages, child: const Text('清空'))]),
          const SizedBox(height: 6),
          SizedBox(height: 78, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _attachedFiles.length + (_attachedFiles.length < _maxReferenceImages ? 1 : 0), separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) {
            if (i == _attachedFiles.length) return InkWell(onTap: _pickImage, borderRadius: BorderRadius.circular(16), child: Container(width: 74, decoration: BoxDecoration(color: Colors.white.withOpacity(.72), borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)), child: const Icon(Icons.add_photo_alternate_rounded, color: _primary)));
            return Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_attachedFiles[i], width: 74, height: 78, fit: BoxFit.cover)), Positioned(top: 3, right: 3, child: InkWell(onTap: () => _removeAttachedImage(i), child: Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.black.withOpacity(.55), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 16))))]);
          })),
        ]),
      );

'''
if '_attachedPreviewStrip()' not in s:
    s=s.replace('  Widget _imageMessage(String url) {\n', insert+'  Widget _imageMessage(String url) {\n',1)
s=re.sub(r'          if \(_attachedFiles\.isNotEmpty\)\s+Container\(.*?\),\n\s+Row\(children:', '          if (_attachedFiles.isNotEmpty) _attachedPreviewStrip(),\n          Row(children:', s, count=1, flags=re.S)

needle='''                Wrap(spacing: 8, runSpacing: 8, children: _qualityOptions.map((v) => _choice(_qualityLabel(v), _imageQuality == v, () => apply(() async { _imageQuality = v; await _saveAllSettings(); }))).toList()),
                const SizedBox(height: 14),
                SwitchListTile.adaptive('''
if '生成数量' not in s:
    s=s.replace(needle, needle.replace('const SizedBox(height: 14),\n                SwitchListTile.adaptive(', "const SizedBox(height: 18),\n                const Text('生成数量', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),\n                const SizedBox(height: 10),\n                Wrap(spacing: 8, runSpacing: 8, children: _imageCountOptions.map((v) => _choice('$v 张', _imageCount == v, () => apply(() async { _imageCount = v; await _saveAllSettings(); }))).toList()),\n                const SizedBox(height: 6),\n                const Text('选择多张时会自动连续生成，并保留已成功的图片。', style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),\n                const SizedBox(height: 14),\n                SwitchListTile.adaptive("))

p.write_text(s,encoding='utf-8')
print('patched home_screen.dart multi image count')
