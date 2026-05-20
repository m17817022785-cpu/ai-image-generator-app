import 'dart:convert';

import 'package:flutter/foundation.dart';

enum DebugLogLevel { info, success, warning, error }

class DebugLogEntry {
  final String id;
  final DateTime time;
  final DebugLogLevel level;
  final String category;
  final String title;
  final String summary;
  final Map<String, dynamic> details;

  DebugLogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.category,
    required this.title,
    required this.summary,
    Map<String, dynamic>? details,
  }) : details = details ?? const {};

  String get levelName {
    switch (level) {
      case DebugLogLevel.info:
        return 'INFO';
      case DebugLogLevel.success:
        return 'SUCCESS';
      case DebugLogLevel.warning:
        return 'WARN';
      case DebugLogLevel.error:
        return 'ERROR';
    }
  }

  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('[$levelName] ${time.toIso8601String()} $title')
      ..writeln('Category: $category')
      ..writeln('Summary: $summary');
    if (details.isNotEmpty) {
      buffer.writeln('Details:');
      const encoder = JsonEncoder.withIndent('  ');
      buffer.writeln(encoder.convert(details));
    }
    return buffer.toString().trimRight();
  }
}

class DebugLogService extends ChangeNotifier {
  DebugLogService._();

  static final DebugLogService instance = DebugLogService._();

  final List<DebugLogEntry> _logs = [];

  List<DebugLogEntry> get logs => List.unmodifiable(_logs.reversed);

  void info(String category, String title, String summary, {Map<String, dynamic>? details}) {
    _add(DebugLogLevel.info, category, title, summary, details: details);
  }

  void success(String category, String title, String summary, {Map<String, dynamic>? details}) {
    _add(DebugLogLevel.success, category, title, summary, details: details);
  }

  void warning(String category, String title, String summary, {Map<String, dynamic>? details}) {
    _add(DebugLogLevel.warning, category, title, summary, details: details);
  }

  void error(String category, String title, String summary, {Map<String, dynamic>? details}) {
    _add(DebugLogLevel.error, category, title, summary, details: details);
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  String exportText({DebugLogLevel? level}) {
    final selected = logs.where((entry) => level == null || entry.level == level);
    return selected.map((entry) => entry.toPlainText()).join('\n\n---\n\n');
  }

  void _add(
    DebugLogLevel level,
    String category,
    String title,
    String summary, {
    Map<String, dynamic>? details,
  }) {
    _logs.add(DebugLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      time: DateTime.now(),
      level: level,
      category: category,
      title: title,
      summary: _sanitizeText(summary),
      details: _sanitizeMap(details ?? const {}),
    ));
    if (_logs.length > 300) {
      _logs.removeRange(0, _logs.length - 300);
    }
    notifyListeners();
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> input) {
    return input.map((key, value) => MapEntry(key, _sanitizeValue(key, value)));
  }

  dynamic _sanitizeValue(String key, dynamic value) {
    final lowerKey = key.toLowerCase();
    if (lowerKey.contains('authorization') ||
        lowerKey.contains('apikey') ||
        lowerKey.contains('api_key') ||
        lowerKey == 'token' ||
        lowerKey.contains('bearer')) {
      return _maskSecret(value?.toString() ?? '');
    }
    if (lowerKey.contains('base64') || lowerKey.contains('b64_json') || lowerKey.contains('imagebytes')) {
      final text = value?.toString() ?? '';
      return text.isEmpty ? '' : '<base64 omitted, length=${text.length}>';
    }
    if (value is Map) {
      return _sanitizeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map((item) => item is Map ? _sanitizeMap(Map<String, dynamic>.from(item)) : _sanitizeText(item?.toString() ?? '')).toList();
    }
    if (value is String) return _sanitizeText(value);
    return value;
  }

  String _sanitizeText(String text) {
    var sanitized = text;
    sanitized = sanitized.replaceAllMapped(RegExp(r'Bearer\s+([A-Za-z0-9_\-\.]{8,})'), (m) => 'Bearer ${_maskSecret(m.group(1)!)}');
    sanitized = sanitized.replaceAllMapped(RegExp(r'sk-[A-Za-z0-9_\-]{8,}'), (m) => _maskSecret(m.group(0)!));
    sanitized = sanitized.replaceAllMapped(RegExp(r'data:image\/[^;]+;base64,[A-Za-z0-9+\/=]+'), (m) => '<data:image base64 omitted, length=${m.group(0)!.length}>');
    return sanitized;
  }

  String _maskSecret(String secret) {
    if (secret.isEmpty) return '';
    if (secret.length <= 8) return '****';
    return '${secret.substring(0, 4)}****${secret.substring(secret.length - 4)}';
  }
}
