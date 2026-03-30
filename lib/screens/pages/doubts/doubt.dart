import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';

class DoubtPage extends StatefulWidget {
  final bool isDark;

  const DoubtPage({
    super.key,
    required this.isDark,
  });

  @override
  State<DoubtPage> createState() => _DoubtPageState();
}

class _DoubtPageState extends State<DoubtPage> {
  static const Color _primary = Color(0xFF9E363A);
  static const Color _secondary = Color(0xFFC94B50);
  static const Color _deep = Color(0xFF2A0F10);
  static const Color _bg = Color(0xFFF7F5F8);
  static const Color _surface = Colors.white;
  static const Color _muted = Color(0xFF7C8090);
  static const Color _line = Color(0xFFF1E4E6);

  static const Color _darkBg = Color(0xFF121216);
  static const Color _darkCard = Color(0xFF1C1C21);
  static const Color _darkMuted = Color(0xFF9A9EAD);
  static const Color _darkLine = Color(0xFF2C2C33);

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;

  final Map<String, DoubtSubjectData> _subjects = {};
  final Map<String, Map<String, Map<String, int>>> _currentSelections = {};
  final Map<String, String> _currentNotes = {};

  @override
  void initState() {
    super.initState();
    _loadBootData();
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('student_token') ?? prefs.getString('token') ?? '')
        .trim();
  }

  Future<Map<String, dynamic>> _api(
    String path, {
    String method = 'GET',
    Object? body,
    int timeoutSeconds = 20,
  }) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse(
        path.startsWith('http') ? path : '${AppConfig.baseUrl}$path',
      );

      final request = await (() async {
        switch (method.toUpperCase()) {
          case 'POST':
            return client.postUrl(uri);
          case 'PUT':
            return client.putUrl(uri);
          case 'PATCH':
            return client.patchUrl(uri);
          case 'DELETE':
            return client.deleteUrl(uri);
          default:
            return client.getUrl(uri);
        }
      })();

      final token = await _getToken();

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');

      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response =
          await request.close().timeout(Duration(seconds: timeoutSeconds));
      final text = await response.transform(utf8.decoder).join();

      dynamic decoded;
      try {
        decoded = text.isNotEmpty ? jsonDecode(text) : {};
      } catch (_) {
        decoded = {};
      }

      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            (data['message'] ?? data['error'] ?? 'Request failed').toString();
        throw Exception(message);
      }

      return data;
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadBootData({bool refreshing = false}) async {
    if (!mounted) return;

    setState(() {
      if (refreshing) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token.isEmpty) {
        throw Exception('Login session not found. Please log in again.');
      }

      await _loadSubjects();
      await _loadExistingSubmissions();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadSubjects() async {
    final response = await _api('/api/student/doubt-subjects');
    final data = response['data'];

    _subjects.clear();

    if (data is Map) {
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          _subjects[key] =
              DoubtSubjectData.fromMap(key, Map<String, dynamic>.from(value));
        }
      }
    }

    for (final subjectKey in _subjects.keys) {
      _currentSelections[subjectKey] ??= _buildEmptySubjectState(subjectKey);
      _currentNotes[subjectKey] ??= '';
    }
  }

  Future<void> _loadExistingSubmissions() async {
    if (_subjects.isEmpty) return;

    final response = await _api('/api/student/doubt-submissions');
    final rows = response['data'];

    if (rows is! List) return;

    final todayIst = _todayIst();
    final Map<String, Map<String, dynamic>> bestBySubject = {};

    for (final item in rows) {
      if (item is! Map) continue;

      final row = Map<String, dynamic>.from(item);
      final subject = row['subject']?.toString() ?? '';
      if (!_subjects.containsKey(subject)) continue;

      final rowDate = row['submitted_date']?.toString() ??
          _extractDateOnly(row['submitted_at']?.toString());

      final score = rowDate == todayIst ? 2 : 1;
      final currentTime = DateTime.tryParse(
            row['submitted_at']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      if (!bestBySubject.containsKey(subject)) {
        bestBySubject[subject] = {
          ...row,
          '__score': score,
          '__time': currentTime.millisecondsSinceEpoch,
        };
        continue;
      }

      final existing = bestBySubject[subject]!;
      final existingScore = existing['__score'] as int? ?? 0;
      final existingTime = existing['__time'] as int? ?? 0;

      if (score > existingScore ||
          (score == existingScore &&
              currentTime.millisecondsSinceEpoch > existingTime)) {
        bestBySubject[subject] = {
          ...row,
          '__score': score,
          '__time': currentTime.millisecondsSinceEpoch,
        };
      }
    }

    for (final entry in bestBySubject.entries) {
      final subject = entry.key;
      final row = entry.value;

      final topics = _parseTopics(row['topics']);
      _currentSelections[subject] = _mergeSavedTopics(subject, topics);
      _currentNotes[subject] = (row['notes'] ?? '').toString();
    }
  }

  String _todayIst() {
    final nowIst =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = nowIst.year.toString().padLeft(4, '0');
    final m = nowIst.month.toString().padLeft(2, '0');
    final d = nowIst.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _extractDateOnly(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    return raw.trim().length >= 10 ? raw.trim().substring(0, 10) : raw.trim();
  }

  Map<String, dynamic> _parseTopics(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return <String, dynamic>{};
  }

  Map<String, Map<String, int>> _buildEmptySubjectState(String subjectKey) {
    final result = <String, Map<String, int>>{};
    final subject = _subjects[subjectKey];
    if (subject == null) return result;

    for (final chapter in subject.chapters.entries) {
      result[chapter.key] = {};
      for (final subtopicKey in chapter.value.subtopics.keys) {
        result[chapter.key]![subtopicKey] = 0;
      }
    }

    return result;
  }

  Map<String, Map<String, int>> _mergeSavedTopics(
    String subjectKey,
    Map<String, dynamic> savedTopics,
  ) {
    final fresh = _buildEmptySubjectState(subjectKey);

    for (final chapterEntry in fresh.entries) {
      final chapterKey = chapterEntry.key;
      final savedChapter = savedTopics[chapterKey];

      if (savedChapter is Map) {
        for (final subtopicKey in chapterEntry.value.keys) {
          chapterEntry.value[subtopicKey] =
              _toInt(savedChapter[subtopicKey]) == 1 ? 1 : 0;
        }
      }
    }

    return fresh;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  int _countSelectedForChapter(String subjectKey, String chapterKey) {
    final chapter = _currentSelections[subjectKey]?[chapterKey];
    if (chapter == null) return 0;
    return chapter.values.where((e) => e == 1).length;
  }

  int _countSelectedForSubject(String subjectKey) {
    final subject = _currentSelections[subjectKey];
    if (subject == null) return 0;

    int total = 0;
    for (final chapterKey in subject.keys) {
      total += _countSelectedForChapter(subjectKey, chapterKey);
    }
    return total;
  }

  int _totalSelectedAllSubjects() {
    int total = 0;
    for (final subjectKey in _subjects.keys) {
      total += _countSelectedForSubject(subjectKey);
    }
    return total;
  }

  IconData _subjectIcon(String key) {
    switch (key.toLowerCase()) {
      case 'physics':
        return Icons.science_rounded;
      case 'chemistry':
        return Icons.biotech_rounded;
      default:
        return Icons.functions_rounded;
    }
  }

  Checkbox _buildAppCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required bool isDark,
  }) {
    return Checkbox(
      value: value,
      onChanged: onChanged,
      activeColor: _primary,
      checkColor: Colors.white,
      side: BorderSide(
        color: value
            ? _primary
            : (isDark ? Colors.white70 : const Color(0xFF8D9098)),
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? const Color(0xFFB3261E) : null,
        ),
      );
  }

  Future<bool> _saveSubjectSubmission(String subjectKey) async {
    try {
      final response = await _api(
        '/api/student/doubt-submissions',
        method: 'POST',
        body: {
          'subject': subjectKey,
          'topics': _currentSelections[subjectKey] ?? {},
          'notes': (_currentNotes[subjectKey] ?? '').trim().isEmpty
              ? null
              : _currentNotes[subjectKey]!.trim(),
        },
      );

      final submission = response['submission'] ??
          (response['data'] is Map
              ? (response['data'] as Map<String, dynamic>)['submission']
              : null);

      if (submission is Map) {
        final topics = _parseTopics(submission['topics']);
        _currentSelections[subjectKey] = _mergeSavedTopics(subjectKey, topics);
        _currentNotes[subjectKey] = (submission['notes'] ?? '').toString();
      }

      _showSnack(
        (response['message'] ?? 'Submission saved successfully.').toString(),
      );
      return true;
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
      return false;
    }
  }

  Future<void> _openSubjectSheet(String subjectKey) async {
    final subject = _subjects[subjectKey];
    if (subject == null) return;

    String? expandedChapter =
        subject.chapters.keys.isNotEmpty ? subject.chapters.keys.first : null;

    final notesController = TextEditingController(
      text: _currentNotes[subjectKey] ?? '',
    );

    final isDark = widget.isDark;

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (bottomSheetContext, modalSetState) {
            final bgColor = isDark ? _darkCard : Colors.white;
            final textPrimary = isDark ? Colors.white : _deep;
            final textSecondary = isDark ? _darkMuted : _muted;
            final borderColor = isDark ? _darkLine : _line;
            final softBg = isDark
                ? Colors.white.withOpacity(0.04)
                : const Color(0xFFFFFAFB);

            return DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.65,
              maxChildSize: 0.96,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 56,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.18)
                              : const Color(0xFFD8C7CA),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _primary.withOpacity(0.10),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _subjectIcon(subject.key),
                                color: _primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subject.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_countSelectedForSubject(subjectKey)} selected across ${subject.chapters.length} chapters',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(bottomSheetContext).pop(false),
                              icon: Icon(
                                Icons.close_rounded,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: softBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: _primary.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.view_agenda_rounded,
                                      color: _primary,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Chapter Accordion',
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Expand a chapter and choose its subtopics.',
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontSize: 12.2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...subject.chapters.entries.map((chapterEntry) {
                              final chapterKey = chapterEntry.key;
                              final chapter = chapterEntry.value;
                              final isExpanded = expandedChapter == chapterKey;
                              final selectedInChapter =
                                  _countSelectedForChapter(
                                subjectKey,
                                chapterKey,
                              );
                              final subtopics = chapter.subtopics;
                              final allChecked = subtopics.isNotEmpty &&
                                  subtopics.keys.every(
                                    (key) =>
                                        (_currentSelections[subjectKey]?[chapterKey]?[key] ??
                                            0) ==
                                        1,
                                  );

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.03)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Column(
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () {
                                          modalSetState(() {
                                            expandedChapter = isExpanded
                                                ? null
                                                : chapterKey;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 38,
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  color: _primary.withOpacity(
                                                    0.10,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
                                                  Icons.layers_rounded,
                                                  color: _primary,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      chapter.label,
                                                      style: TextStyle(
                                                        color: textPrimary,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '$selectedInChapter of ${subtopics.length} selected',
                                                      style: TextStyle(
                                                        color: textSecondary,
                                                        fontSize: 12.2,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _primary.withOpacity(
                                                    0.10,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  '$selectedInChapter',
                                                  style: const TextStyle(
                                                    color: _primary,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                isExpanded
                                                    ? Icons.keyboard_arrow_up_rounded
                                                    : Icons
                                                        .keyboard_arrow_down_rounded,
                                                color: textSecondary,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isExpanded) ...[
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            14,
                                            0,
                                            14,
                                            14,
                                          ),
                                          child: Column(
                                            children: [
                                              const SizedBox(height: 2),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: softBg,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: borderColor,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    _buildAppCheckbox(
                                                      value: allChecked,
                                                      isDark: isDark,
                                                      onChanged: (value) {
                                                        final nextValue =
                                                            value == true;
                                                        for (final key
                                                            in subtopics.keys) {
                                                          _currentSelections[
                                                                      subjectKey]![chapterKey]![key] =
                                                              nextValue ? 1 : 0;
                                                        }
                                                        modalSetState(() {});
                                                      },
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        'Select all subtopics',
                                                        style: TextStyle(
                                                          color: textPrimary,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              ...subtopics.entries
                                                  .map((subtopic) {
                                                final checked = (_currentSelections[
                                                                    subjectKey]?[chapterKey]?[subtopic.key] ??
                                                                0) ==
                                                            1;

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      14,
                                                    ),
                                                    onTap: () {
                                                      _currentSelections[
                                                                  subjectKey]![chapterKey]![subtopic.key] =
                                                          checked ? 0 : 1;
                                                      modalSetState(() {});
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: checked
                                                            ? _primary
                                                                .withOpacity(
                                                                  0.08,
                                                                )
                                                            : (isDark
                                                                ? Colors.white
                                                                    .withOpacity(
                                                                    0.03,
                                                                  )
                                                                : Colors.white),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        border: Border.all(
                                                          color: checked
                                                              ? _primary
                                                              : borderColor,
                                                          width:
                                                              checked ? 1.3 : 1,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          _buildAppCheckbox(
                                                            value: checked,
                                                            isDark: isDark,
                                                            onChanged: (value) {
                                                              _currentSelections[
                                                                          subjectKey]![chapterKey]![subtopic.key] =
                                                                  value == true
                                                                      ? 1
                                                                      : 0;
                                                              modalSetState(
                                                                () {},
                                                              );
                                                            },
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                top: 6,
                                                              ),
                                                              child: Text(
                                                                subtopic.value,
                                                                style: TextStyle(
                                                                  color:
                                                                      textPrimary,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  height: 1.45,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.03)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Notes',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: notesController,
                                    minLines: 4,
                                    maxLines: 6,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Write any doubt note here...',
                                      hintStyle:
                                          TextStyle(color: textSecondary),
                                      filled: true,
                                      fillColor: isDark
                                          ? Colors.white.withOpacity(0.04)
                                          : Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(18),
                                        borderSide: BorderSide(
                                          color: borderColor,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(18),
                                        borderSide: BorderSide(
                                          color: borderColor,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(18),
                                        borderSide: const BorderSide(
                                          color: _primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      _currentNotes[subjectKey] = value;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          decoration: BoxDecoration(
                            color: bgColor,
                            border: Border(
                              top: BorderSide(color: borderColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_countSelectedForSubject(subjectKey)} subtopics selected',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 44,
                                child: OutlinedButton(
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.of(bottomSheetContext)
                                          .pop(false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: textPrimary,
                                    side: BorderSide(color: borderColor),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text('Close'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () async {
                                          modalSetState(() {
                                            saving = true;
                                          });

                                          _currentNotes[subjectKey] =
                                              notesController.text.trim();

                                          final success =
                                              await _saveSubjectSubmission(
                                            subjectKey,
                                          );

                                          if (!bottomSheetContext.mounted) {
                                            return;
                                          }

                                          if (success) {
                                            Navigator.of(bottomSheetContext)
                                                .pop(true);
                                          } else {
                                            modalSetState(() {
                                              saving = false;
                                            });
                                          }
                                        },
                                  icon: saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save_rounded),
                                  label: Text(
                                    saving ? 'Saving…' : 'Save Submission',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    notesController.dispose();

    if (saved == true && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _loadBootData(refreshing: true);
      return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    final bgColor = isDark ? _darkBg : _bg;
    final cardColor = isDark ? _darkCard : _surface;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: _primary,
        onRefresh: () => _loadBootData(refreshing: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF7B2A30),
                      _primary,
                      _secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(38),
                    bottomRight: Radius.circular(38),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -18,
                      right: -10,
                      child: Container(
                        width: 126,
                        height: 126,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: -26,
                      child: Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 34,
                      right: 20,
                      child: Icon(
                        Icons.live_help_rounded,
                        size: 78,
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                        child: Column(
                          children: [
                            const SizedBox(height: 2),
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                              child: const Icon(
                                Icons.live_help_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Doubts',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Choose a subject, expand chapter accordions, select subtopics, and save your doubt submission.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 13.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _TopInfoChip(
                                  icon: Icons.menu_book_rounded,
                                  label: 'Subjects',
                                  value: '${_subjects.length}',
                                ),
                                _TopInfoChip(
                                  icon: Icons.check_circle_rounded,
                                  label: 'Selected',
                                  value: '${_totalSelectedAllSubjects()}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    if (_isLoading)
                      _DoubtLoadingState(isDark: isDark)
                    else if (_error != null && _subjects.isEmpty)
                      _ErrorCard(
                        isDark: isDark,
                        message: _error!,
                        onRetry: _loadBootData,
                      )
                    else if (_subjects.isEmpty)
                      _EmptyCard(
                        isDark: isDark,
                        title: 'No subjects available',
                        subtitle:
                            'No doubt subjects were returned by the API.',
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                color: _primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Tap a subject row to open the accordion view.',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 13,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._subjects.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MinimalSubjectRow(
                            isDark: isDark,
                            title: entry.value.label,
                            subtitle: '${entry.value.chapters.length} chapters',
                            selectedCount:
                                _countSelectedForSubject(entry.key),
                            icon: _subjectIcon(entry.key),
                            hasNote:
                                (_currentNotes[entry.key] ?? '').trim().isNotEmpty,
                            onTap: () => _openSubjectSheet(entry.key),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoubtSubjectData {
  final String key;
  final String label;
  final Map<String, DoubtChapterData> chapters;

  const DoubtSubjectData({
    required this.key,
    required this.label,
    required this.chapters,
  });

  factory DoubtSubjectData.fromMap(
    String key,
    Map<String, dynamic> map,
  ) {
    final rawChapters = map['chapters'];
    final chapters = <String, DoubtChapterData>{};

    if (rawChapters is Map) {
      for (final entry in rawChapters.entries) {
        final chapterKey = entry.key.toString();
        final chapterValue = entry.value;
        if (chapterValue is Map) {
          chapters[chapterKey] = DoubtChapterData.fromMap(
            chapterKey,
            Map<String, dynamic>.from(chapterValue),
          );
        }
      }
    }

    return DoubtSubjectData(
      key: key,
      label: (map['label'] ?? key).toString(),
      chapters: chapters,
    );
  }
}

class DoubtChapterData {
  final String key;
  final String label;
  final Map<String, String> subtopics;

  const DoubtChapterData({
    required this.key,
    required this.label,
    required this.subtopics,
  });

  factory DoubtChapterData.fromMap(
    String key,
    Map<String, dynamic> map,
  ) {
    final rawSubtopics = map['subtopics'];
    final subtopics = <String, String>{};

    if (rawSubtopics is Map) {
      for (final entry in rawSubtopics.entries) {
        subtopics[entry.key.toString()] = entry.value.toString();
      }
    }

    return DoubtChapterData(
      key: key,
      label: (map['label'] ?? key).toString(),
      subtopics: subtopics,
    );
  }
}

class _TopInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TopInfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            '$label ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimalSubjectRow extends StatelessWidget {
  final bool isDark;
  final String title;
  final String subtitle;
  final int selectedCount;
  final IconData icon;
  final bool hasNote;
  final VoidCallback onTap;

  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);

  const _MinimalSubjectRow({
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.selectedCount,
    required this.icon,
    required this.hasNote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary =
        isDark ? const Color(0xFF9A9EAD) : const Color(0xFF7C8090);
    final borderColor =
        isDark ? const Color(0xFF2C2C33) : const Color(0xFFF1E4E6);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: _primary.withOpacity(isDark ? 0.14 : 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: _primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (hasNote) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.sticky_note_2_rounded,
                          color: _primary,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$selectedCount',
                style: const TextStyle(
                  color: _primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _DoubtLoadingState extends StatelessWidget {
  final bool isDark;

  const _DoubtLoadingState({
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final shimmerColor =
        isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF3EAEC);

    return Column(
      children: List.generate(4, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF1E4E6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 110,
                            height: 10,
                            decoration: BoxDecoration(
                              color: shimmerColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final bool isDark;
  final String message;
  final Future<void> Function() onRetry;

  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);

  const _ErrorCard({
    required this.isDark,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final borderColor =
        isDark ? const Color(0xFF2C2C33) : const Color(0xFFF1E4E6);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: _primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final String subtitle;

  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);

  const _EmptyCard({
    required this.isDark,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary =
        isDark ? const Color(0xFF9A9EAD) : const Color(0xFF7C8090);
    final borderColor =
        isDark ? const Color(0xFF2C2C33) : const Color(0xFFF1E4E6);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.live_help_outlined,
              color: _primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}