from pathlib import Path
import re

home = Path('lib/screens/home_screen.dart')
s = home.read_text(encoding='utf-8')

if 'bool _studioHeaderCollapsed' not in s:
    s = s.replace('bool _enhanceImagePrompt = true;\n  int _imageCount = 1;', 'bool _enhanceImagePrompt = true;\n  bool _studioHeaderCollapsed = false;\n  int _imageCount = 1;', 1)

if 'Future<void> _confirmNewSession()' not in s:
    marker = '  void _snack(String message) {\n'
    insert = """  void _startNewSession() {
    setState(() {
      _messages.clear();
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = false;
      _forceImage = false;
      _studioHeaderCollapsed = false;
    });
    _snack('已开启新会话');
  }

  Future<void> _confirmNewSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开新会话'),
        content: const Text('清空当前聊天记录、输入内容和参考图？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始')),
        ],
      ),
    );
    if (ok == true) _startNewSession();
  }

  void _setStudioHeaderCollapsed(bool value) {
    if (_studioHeaderCollapsed != value) setState(() => _studioHeaderCollapsed = value);
  }

"""
    if marker not in s:
        raise SystemExit('snack marker not found')
    s = s.replace(marker, insert + marker, 1)

if 'Icons.add_comment_rounded' not in s:
    old = """        actions: [
          _roundIcon(Icons.terminal_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugConsoleScreen()))),"""
    new = """        actions: [
          _roundIcon(Icons.add_comment_rounded, _confirmNewSession),
          _roundIcon(Icons.terminal_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugConsoleScreen()))),"""
    if old not in s:
        raise SystemExit('appbar marker not found')
    s = s.replace(old, new, 1)

if '展开创作面板' not in s:
    old_title = "Text(_forceImage ? '图像创作模式' : '智能创作模式', style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w900))"
    new_title = "Text(_forceImage ? '图像创作模式' : '智能创作模式', style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 2), InkWell(onTap: () => _setStudioHeaderCollapsed(!_studioHeaderCollapsed), child: Text(_studioHeaderCollapsed ? '展开创作面板' : '收起创作面板', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w800)))"
    if old_title not in s:
        raise SystemExit('studio title marker not found')
    s = s.replace(old_title, new_title, 1)

old_send = """  Future<void> _send() async {
    final text = _input.text.trim();"""
new_send = """  Future<void> _send() async {
    _setStudioHeaderCollapsed(true);
    final text = _input.text.trim();"""
if old_send in s and new_send not in s:
    s = s.replace(old_send, new_send, 1)

if 'if (!_studioHeaderCollapsed) ...[' not in s:
    start = '          const SizedBox(height: 12),\n          Row(children: [Expanded(child: _modeButton('
    if start not in s:
        raise SystemExit('collapse start marker not found')
    s = s.replace(start, '          if (!_studioHeaderCollapsed) ...[\n            const SizedBox(height: 12),\n            Row(children: [Expanded(child: _modeButton(', 1)
    end = """          InkWell(onTap: _openImageParams, borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(.58), borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)), child: Row(children: [const Icon(Icons.tune_rounded, color: _primary), const SizedBox(width: 8), Expanded(child: Text('图片参数 · $_imageAspectRatio · ${_qualityLabel(_imageQuality)} · $_imageCount 张 · ${_enhanceImagePrompt ? '润色开' : '润色关'}', style: const TextStyle(color: _text, fontWeight: FontWeight.w900))), const Icon(Icons.keyboard_arrow_up_rounded, color: _muted)]))),
"""
    if end not in s:
        raise SystemExit('collapse end marker not found')
    s = s.replace(end, end + '          ],\n', 1)

for marker in ['_confirmNewSession', '_startNewSession', '_setStudioHeaderCollapsed', '展开创作面板', '收起创作面板', 'add_comment_rounded', 'if (!_studioHeaderCollapsed) ...[']:
    if marker not in s:
        raise SystemExit('missing marker: ' + marker)
home.write_text(s, encoding='utf-8')

pub = Path('pubspec.yaml')
p = pub.read_text(encoding='utf-8')
p = re.sub(r'^version:\s*\S+\s*$', 'version: 1.2.7+1003', p, count=1, flags=re.M)
pub.write_text(p, encoding='utf-8')
