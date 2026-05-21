from pathlib import Path

p = Path('lib/screens/home_screen.dart')
s = p.read_text(encoding='utf-8')

if 'bool _studioHeaderCollapsed = true;' not in s:
    s = s.replace(
        '  bool _enhanceImagePrompt = true;\n',
        '  bool _enhanceImagePrompt = true;\n  bool _studioHeaderCollapsed = true;\n',
    )

if '_studioHeaderCollapsed ? _compactStudioHeader() : _studioHeader()' not in s:
    s = s.replace(
        'SafeArea(top: false, child: Column(children: [_studioHeader(),',
        'SafeArea(top: false, child: Column(children: [_studioHeaderCollapsed ? _compactStudioHeader() : _studioHeader(),',
    )

old_load = "        _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';\n      });"
new_load = "        _enhanceImagePrompt = (s['enhanceImagePrompt'] ?? 'true') == 'true';\n        _studioHeaderCollapsed = true;\n      });"
if old_load in s and new_load not in s:
    s = s.replace(old_load, new_load)

old_save = '        enhanceImagePrompt: _enhanceImagePrompt,\n      );'
new_save = '        enhanceImagePrompt: _enhanceImagePrompt,\n        studioHeaderCollapsed: _studioHeaderCollapsed,\n      );'
if old_save in s and new_save not in s:
    s = s.replace(old_save, new_save)

# Add collapse button into the full studio header row.
old_chip = '            _statusChip(),\n          ]),' 
new_chip = '''            _statusChip(),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '收起面板',
              onPressed: () async {
                setState(() => _studioHeaderCollapsed = true);
                await _saveAllSettings();
              },
              icon: const Icon(Icons.keyboard_arrow_up_rounded, color: _muted),
              style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(.58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ]),'''
if "tooltip: '收起面板'" not in s and old_chip in s:
    s = s.replace(old_chip, new_chip)

marker = '  Widget _statusChip() => InkWell('
compact = r'''
  Widget _compactStudioHeader() => _glassPanel(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        radius: 22,
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [_primary, _primary2])),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_forceImage ? '生图模式' : '智能模式', style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('画幅 $_imageAspectRatio · $_selectedSize · ${_qualityLabel(_imageQuality)}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
            tooltip: '图片参数',
            onPressed: _openImageParams,
            icon: const Icon(Icons.tune_rounded, color: _primary),
            style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(.60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '展开面板',
            onPressed: () async {
              setState(() => _studioHeaderCollapsed = false);
              await _saveAllSettings();
            },
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
            style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(.60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
        ]),
      );

'''
if '_compactStudioHeader() =>' not in s and marker in s:
    s = s.replace(marker, compact + marker)

p.write_text(s, encoding='utf-8')
print('studio header patch applied')
