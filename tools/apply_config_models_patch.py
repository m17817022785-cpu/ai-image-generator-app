from pathlib import Path
import re

HOME = Path('lib/screens/home_screen.dart')
text = HOME.read_text(encoding='utf-8')
original = text

# Ensure the unified save method is used for both network URLs and data:image base64 URLs.
text = text.replace(
    'await ImageSaveService.saveNetworkImage(url);',
    'await ImageSaveService.saveImage(url);',
)

# Replace the old conditional UI that hides the save button for base64 images.
pattern = re.compile(
    r"if \(!isData\) FilledButton\.icon\(onPressed: \(\) => _saveImage\(url\), icon: const Icon\(Icons\.download_rounded\), label: const Text\('保存图片'\), style: FilledButton\.styleFrom\(backgroundColor: _cyan, foregroundColor: Colors\.white, shape: RoundedRectangleBorder\(borderRadius: BorderRadius\.circular\(16\)\)\)\) else const Text\('base64 图片已直接显示', style: TextStyle\(color: _muted, fontSize: 12\)\)"
)
replacement = (
    "FilledButton.icon(onPressed: () => _saveImage(url), icon: const Icon(Icons.download_rounded), "
    "label: const Text('保存图片'), style: FilledButton.styleFrom(backgroundColor: _cyan, "
    "foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))), "
    "if (isData) const Padding(padding: EdgeInsets.only(top: 6), child: Text('base64 图片已直接显示，可保存到相册', "
    "style: TextStyle(color: _muted, fontSize: 12)))"
)
text, count = pattern.subn(replacement, text)

HOME.write_text(text, encoding='utf-8')
print('HomeScreen base64 save UI patch replacements:', count)
print('HomeScreen base64 save UI patch:', 'changed' if text != original else 'already up to date or pattern not found')
