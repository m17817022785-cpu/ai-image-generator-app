import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/debug_log_service.dart';

class DebugConsoleScreen extends StatefulWidget {
  const DebugConsoleScreen({super.key});

  @override
  State<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends State<DebugConsoleScreen> {
  static const _bg = Color(0xFF050816);
  static const _surface = Color(0xFF182033);
  static const _surface2 = Color(0xFF222B3F);
  static const _text = Color(0xFFF8FAFC);
  static const _muted = Color(0xFFCBD5E1);
  static const _primary = Color(0xFF7C3AED);
  static const _secondary = Color(0xFF06B6D4);

  DebugLogLevel? _filterLevel;
  String? _filterCategory;

  @override
  Widget build(BuildContext context) {
    final logService = DebugLogService.instance;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('调试控制台', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        backgroundColor: _bg,
        iconTheme: const IconThemeData(color: _text),
        actions: [
          IconButton(
            tooltip: '复制当前日志',
            onPressed: () => _copyLogs(logService),
            icon: const Icon(Icons.copy_all_rounded, color: _secondary),
          ),
          IconButton(
            tooltip: '清空日志',
            onPressed: () => _confirmClear(logService),
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: logService,
        builder: (context, _) {
          final allLogs = logService.logs;
          final categories = allLogs.map((e) => e.category).toSet().toList()..sort();
          final logs = allLogs.where((entry) {
            final levelOk = _filterLevel == null || entry.level == _filterLevel;
            final categoryOk = _filterCategory == null || entry.category == _filterCategory;
            return levelOk && categoryOk;
          }).toList();

          return Column(
            children: [
              _filters(categories),
              Expanded(
                child: logs.isEmpty
                    ? const Center(child: Text('暂无日志', style: TextStyle(color: _muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                        itemCount: logs.length,
                        itemBuilder: (_, index) => _logTile(logs[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filters(List<String> categories) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: _surface.withValues(alpha: 0.96), border: const Border(bottom: BorderSide(color: Colors.white10))),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('全部', _filterLevel == null, () => setState(() => _filterLevel = null)),
                _filterChip('错误', _filterLevel == DebugLogLevel.error, () => setState(() => _filterLevel = DebugLogLevel.error), color: Colors.redAccent),
                _filterChip('警告', _filterLevel == DebugLogLevel.warning, () => setState(() => _filterLevel = DebugLogLevel.warning), color: Colors.orangeAccent),
                _filterChip('成功', _filterLevel == DebugLogLevel.success, () => setState(() => _filterLevel = DebugLogLevel.success), color: Colors.greenAccent),
                _filterChip('信息', _filterLevel == DebugLogLevel.info, () => setState(() => _filterLevel = DebugLogLevel.info), color: _secondary),
              ],
            ),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('全部模块', _filterCategory == null, () => setState(() => _filterCategory = null), color: _primary),
                  ...categories.map((category) => _filterChip(category, _filterCategory == category, () => setState(() => _filterCategory = category), color: _secondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, {Color color = _secondary}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        label: Text(label),
        labelStyle: TextStyle(color: selected ? Colors.white : _muted, fontWeight: FontWeight.w700),
        selectedColor: color.withValues(alpha: 0.45),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        side: BorderSide(color: selected ? color : Colors.white10),
      ),
    );
  }

  Widget _logTile(DebugLogEntry entry) {
    final color = _levelColor(entry.level);
    return Card(
      color: _surface2.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: color.withValues(alpha: 0.25))),
      child: ExpansionTile(
        iconColor: _text,
        collapsedIconColor: _muted,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.4))),
              child: Text(entry.levelName, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w800))),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${_formatTime(entry.time)} · ${entry.category} · ${entry.summary}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
        ),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _copyText(entry.toPlainText()),
              icon: const Icon(Icons.copy_rounded, color: _secondary, size: 16),
              label: const Text('复制此条', style: TextStyle(color: _secondary, fontWeight: FontWeight.w700)),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
            child: SelectableText(entry.toPlainText(), style: const TextStyle(color: _text, height: 1.45, fontSize: 12.5, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Color _levelColor(DebugLogLevel level) {
    switch (level) {
      case DebugLogLevel.info:
        return _secondary;
      case DebugLogLevel.success:
        return const Color(0xFF10B981);
      case DebugLogLevel.warning:
        return Colors.orangeAccent;
      case DebugLogLevel.error:
        return Colors.redAccent;
    }
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Future<void> _copyLogs(DebugLogService service) async {
    final text = service.exportText(level: _filterLevel);
    await _copyText(text.isEmpty ? '暂无日志' : text);
  }

  Future<void> _confirmClear(DebugLogService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('清空控制台日志？', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        content: const Text('日志只保存在本次运行内，清空后无法恢复。', style: TextStyle(color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: _muted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (ok == true) service.clear();
  }
}
