from pathlib import Path

path = Path('lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')


def replace(old: str, new: str):
    global text
    if old in text:
        text = text.replace(old, new)
    else:
        print('patch warning: pattern not found:', old[:100].replace('\n', ' '))


def insert_before(anchor: str, block: str):
    global text
    if block.strip() in text:
        return
    if anchor not in text:
        print('patch warning: anchor not found:', anchor)
        return
    text = text.replace(anchor, block + '\n\n' + anchor)

# Imports and service field.
if "import 'package:flutter/services.dart';" not in text:
    replace("import 'package:flutter/material.dart';\nimport 'package:flutter_markdown/flutter_markdown.dart';",
            "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\nimport 'package:flutter_markdown/flutter_markdown.dart';")
if "import '../services/debug_log_service.dart';" not in text:
    replace("import '../services/api_service.dart';\nimport '../services/image_save_service.dart';\nimport '../services/settings_service.dart';",
            "import '../services/api_service.dart';\nimport '../services/debug_log_service.dart';\nimport '../services/image_save_service.dart';\nimport '../services/settings_service.dart';")
if 'final _debugLog = DebugLogService.instance;' not in text:
    replace("  final _api = ApiService();\n  final _settings = SettingsService();",
            "  final _api = ApiService();\n  final _settings = SettingsService();\n  final _debugLog = DebugLogService.instance;")

# Friendly errors + missing reference detector.
old_friendly = """  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('RangeError')) {
      return '发送失败：服务器返回内容为空或格式异常，请稍后重试。';
    }
    if (raw.contains('SocketException') || raw.contains('connection reset') || raw.contains('read_response_body_failed')) {
      return '发送失败：网络连接中断或服务器提前断开，请稍后重试。';
    }
    if (raw.contains('TimeoutException')) {
      return '发送失败：请求超时，请稍后重试。';
    }
    return '发送失败：$raw';
  }"""
new_friendly = """  String _friendlyError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (raw.contains('RangeError')) return '发送失败：服务器返回内容为空或格式异常，请稍后重试。详情已记录到控制台。';
    if (lower.contains('content_policy_violation')) return '发送失败：请求被内容策略拦截。请删除具体角色名/受版权角色名，改用原创角色描述；如果使用参考图，请确认图片已上传。详情已记录到控制台。';
    if (lower.contains('do_request_failed') || lower.contains('upstream error') || lower.contains('工具决策失败500') || lower.contains(' 500:')) return '发送失败：上游服务暂时异常，请稍后重试。请求 ID 和原始错误已记录到控制台。';
    if (raw.contains('SocketException') || lower.contains('connection reset') || lower.contains('read_response_body_failed')) return '发送失败：网络连接中断或服务器提前断开，请稍后重试。详情已记录到控制台。';
    if (raw.contains('TimeoutException')) return '发送失败：请求超时，请稍后重试，或降低图片数量/质量。详情已记录到控制台。';
    return '发送失败：$raw';
  }

  bool _looksLikeMissingReferenceRequest(String text) {
    final value = text.trim().toLowerCase();
    if (value.isEmpty) return false;
    const markers = ['参考图', '参考图片', '根据这张图', '根据这张图片', '根据此图', '按照这张图', '按这张图', '这张图的风格', '它的风格', '同款风格', '换风格', '重绘这张', '修这张', 'edit this image', 'reference image', 'this image', 'same style'];
    return markers.any(value.contains);
  }"""
replace(old_friendly, new_friendly)

# Send precheck.
old_precheck = """    if (_apiKey.trim().isEmpty) {
      _snack('请先配置聊天 API Key。点击右上角设置。');
      return;
    }

    final content = text.isEmpty ? (files.length > 1 ? '请根据这些图片继续处理' : '请根据这张图片继续处理') : text;"""
new_precheck = """    if (_apiKey.trim().isEmpty) {
      _snack('请先配置聊天 API Key。点击右上角设置。');
      _debugLog.warning('send', '发送前校验失败', '缺少聊天 API Key', details: {'hasText': text.isNotEmpty, 'imageCount': files.length, 'forceImage': _forceImage});
      return;
    }
    if (files.isEmpty && _looksLikeMissingReferenceRequest(text)) {
      const message = '当前描述像是在参考/编辑一张图片，但还没有上传参考图。请先上传图片，或改成纯文字生图描述。';
      _snack(message);
      _debugLog.warning('send', '发送前校验失败', '参考图请求缺少上传图片', details: {'userText': text, 'imageCount': files.length, 'forceImage': _forceImage});
      return;
    }

    final content = text.isEmpty ? (files.length > 1 ? '请根据这些图片继续处理' : '请根据这张图片继续处理') : text;"""
replace(old_precheck, new_precheck)

if "_debugLog.info('send', '开始发送请求'" not in text:
    replace("""    setState(() {
      _messages.add(user);
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = true;
    });""", """    _debugLog.info('send', '开始发送请求', _forceImage ? '强制图片模式' : '自动决策模式', details: {'userText': content, 'imageCount': files.length, 'base64ImageCount': b64s.length, 'forceImage': _forceImage, 'aspectRatio': _imageAspectRatio, 'size': _selectedSize, 'quality': _imageQuality, 'imageCountSetting': _imageCount});

    setState(() {
      _messages.add(user);
      _input.clear();
      _attachedFiles.clear();
      _attachedBase64Images.clear();
      _loading = true;
    });""")

replace("""    } catch (e) {
      final friendly = _friendlyError(e);
      _markLastGeneratingAsFailed(friendly);
      _snack(friendly);
    } finally {""", """      _debugLog.success('send', '请求处理完成', _forceImage ? '图片模式完成' : '自动模式完成', details: {'userText': content, 'imageCount': files.length});
    } catch (e) {
      final friendly = _friendlyError(e);
      _debugLog.error('send', '请求发送失败', friendly, details: {'rawError': e.toString(), 'userText': content, 'imageCount': files.length, 'base64ImageCount': b64s.length, 'forceImage': _forceImage, 'aspectRatio': _imageAspectRatio, 'size': _selectedSize, 'quality': _imageQuality, 'imageCountSetting': _imageCount});
      _markLastGeneratingAsFailed(friendly);
      _snack(friendly);
    } finally {""")

# AppBar console entry.
if "tooltip: '控制台'" not in text:
    replace("""        actions: [
          IconButton(
            tooltip: '历史记录',
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded, color: _text),
          ),""", """        actions: [
          IconButton(
            tooltip: '控制台',
            onPressed: _openDebugConsole,
            icon: const Icon(Icons.terminal_rounded, color: _text),
          ),
          IconButton(
            tooltip: '历史记录',
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded, color: _text),
          ),""")

# Console UI.
console_block = r'''  Future<void> _openDebugConsole() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => AnimatedBuilder(
        animation: _debugLog,
        builder: (ctx, _) {
          final logs = _debugLog.logs;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.of(ctx).padding.bottom + 18),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * .78,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.terminal_rounded, color: _primary),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('控制台', style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w900))),
                    TextButton.icon(onPressed: logs.isEmpty ? null : () async { await Clipboard.setData(ClipboardData(text: _debugLog.exportText())); if (mounted) _snack('控制台日志已复制'); }, icon: const Icon(Icons.copy_rounded), label: const Text('复制')),
                    TextButton.icon(onPressed: logs.isEmpty ? null : () { _debugLog.clear(); if (mounted) _snack('控制台已清空'); }, icon: const Icon(Icons.delete_outline_rounded), label: const Text('清空')),
                  ]),
                  const SizedBox(height: 8),
                  const Text('请求、工具决策、图片生成、解析错误和 request id 会记录在这里，便于复制反馈。', style: TextStyle(color: _muted, height: 1.4, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Expanded(child: logs.isEmpty ? const Center(child: Text('暂无日志\n发送请求或遇到错误后会显示在这里', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.5, fontWeight: FontWeight.w700))) : ListView.separated(itemCount: logs.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => _debugLogTile(logs[i]))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _debugLogTile(DebugLogEntry entry) {
    final color = switch (entry.level) { DebugLogLevel.success => const Color(0xFF16A34A), DebugLogLevel.warning => const Color(0xFFF59E0B), DebugLogLevel.error => const Color(0xFFEF4444), _ => _primary };
    final time = '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
    return Material(
      color: const Color(0xFFF7F4FF),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onLongPress: () async { await Clipboard.setData(ClipboardData(text: entry.toPlainText())); if (mounted) _snack('单条日志已复制'); },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(entry.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w900))), Text('$time · ${entry.levelName}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 6),
            Text(entry.summary, style: const TextStyle(color: _text, height: 1.35, fontWeight: FontWeight.w700)),
            if (entry.details.isNotEmpty) ...[const SizedBox(height: 8), Text(entry.details.entries.map((e) => '${e.key}: ${e.value}').join('\n'), maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, height: 1.35, fontSize: 12, fontWeight: FontWeight.w600))],
          ]),
        ),
      ),
    );
  }'''
if 'Future<void> _openDebugConsole() async' not in text:
    insert_before('  Future<void> _openHistory() async {', console_block)

# Image parameter colors.
replace("""              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成'))),""", """              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), style: FilledButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, disabledBackgroundColor: _line, disabledForegroundColor: _muted), child: const Text('完成'))),""")
replace("""  Widget _choice(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ChoiceChip(label: Text(label), selected: active, onSelected: (_) => onTap(), selectedColor: _primary, labelStyle: TextStyle(color: active ? Colors.white : _text, fontWeight: FontWeight.w800)),
      );""", """  Widget _choice(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ChoiceChip(label: Text(label), selected: active, onSelected: (_) => onTap(), selectedColor: _primary, backgroundColor: Colors.white, disabledColor: const Color(0xFFF1EEFF), checkmarkColor: Colors.white, side: BorderSide(color: active ? _primary : _line), labelStyle: TextStyle(color: active ? Colors.white : _text, fontWeight: FontWeight.w800)),
      );""")

path.write_text(text, encoding='utf-8')
print('HomeScreen hotfix applied')
