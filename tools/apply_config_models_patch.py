from pathlib import Path

HOME = Path('lib/screens/home_screen.dart')
text = HOME.read_text(encoding='utf-8')
original = text

text = text.replace(
    'await ImageSaveService.saveNetworkImage(url);',
    'await ImageSaveService.saveImage(url);',
)

old = "      if (!isData) FilledButton.icon(onPressed: () => _saveImage(url), icon: const Icon(Icons.download_rounded), label: const Text('d 密图片'), style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))) else const Text('base64 图片嵦直推显礷', style: TextStyle(color: _muted, fontSize: 12)),"
new = "      FilledButton.icon(onPressed: () => _saveImage(url), icon: const Icon(Icons.download_rounded), label: const Text('保存图片'), style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),\n      if (isData) const Padding(padding: EdgeInset.only(top: 6), child: Text('base64 图片已直接显示，可保存到相册', style: TextStyle(color: _muted, fontSize: 12))),"
text = text.replace(old, new)

HOME.write_text(text, encoding='utf-8')

print('HomeScreen base64 save patch:', 'changed' if text != original else 'already up to date or pattern not found')
