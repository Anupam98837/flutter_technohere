import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';
import 'package:technohere/screens/pages/exam/exam.dart';

class MyExamPage extends StatefulWidget {
  final void Function(MyExamItem item)? onStartExam;
  final bool isDark;

  const MyExamPage({super.key, this.onStartExam, required this.isDark});

  @override
  State<MyExamPage> createState() => _MyExamPageState();
}

class _MyExamPageState extends State<MyExamPage> {
  static const Color _primary = Color(0xFF9E363A);
  static const Color _secondary = Color(0xFFC94B50);
  static const Color _deep = Color(0xFF2A0F10);
  static const Color _bg = Color(0xFFF7F5F8);
  static const Color _muted = Color(0xFF7C8090);
  static const Color _line = Color(0xFFF1E4E6);

  static const Color _darkBg = Color(0xFF121216);
  static const Color _darkCard = Color(0xFF1C1C21);
  static const Color _darkMuted = Color(0xFF9A9EAD);
  static const Color _darkLine = Color(0xFF2C2C33);

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _continueDialogVisible = false;
  String? _error;
  List<MyExamItem> _items = [];
  String _query = '';
  int _selectedTab = 0; // 0 = Exams, 1 = Finished

  @override
  void initState() {
    super.initState();
    _loadItems();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _query = _searchController.text.trim().toLowerCase();
    });
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('student_token') ?? prefs.getString('token') ?? '')
        .trim();
  }

  Future<Map<String, dynamic>> _getJsonWithToken(
    String endpoint,
    String token,
  ) async {
    final client = HttpClient();

    try {
      final request = await client.getUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );

      final responseText = await response.transform(utf8.decoder).join();

      dynamic decoded;
      try {
        decoded = responseText.isNotEmpty ? jsonDecode(responseText) : {};
      } catch (_) {
        decoded = {};
      }

      return {
        'statusCode': response.statusCode,
        'data': decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOneList(
    String endpoint,
    String token,
  ) async {
    final uri = Uri.parse(
      endpoint,
    ).replace(queryParameters: const {'page': '1', 'per_page': '1000'});

    final result = await _getJsonWithToken(uri.toString(), token);
    final statusCode = result['statusCode'] as int;
    final body = result['data'] as Map<String, dynamic>;

    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        (body['message'] ?? body['error'] ?? 'Failed to load items').toString(),
      );
    }

    final rawData = body['data'];
    if (rawData is List) {
      return rawData
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  Future<void> _loadItems({bool refreshing = false}) async {
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

      final results = await Future.wait<List<Map<String, dynamic>>>([
        _fetchOneList(
          '${AppConfig.baseUrl}/api/quizz/my',
          token,
        ).catchError((_) => <Map<String, dynamic>>[]),
        _fetchOneList(
          '${AppConfig.baseUrl}/api/bubble-games/my',
          token,
        ).catchError((_) => <Map<String, dynamic>>[]),
        _fetchOneList(
          '${AppConfig.baseUrl}/api/door-games/my',
          token,
        ).catchError((_) => <Map<String, dynamic>>[]),
        _fetchOneList(
          '${AppConfig.baseUrl}/api/path-games/my',
          token,
        ).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final merged = <MyExamItem>[
        ...results[0].map((e) => _normalizeItem(e, 'quiz')),
        ...results[1].map((e) => _normalizeItem(e, 'game')),
        ...results[2].map((e) => _normalizeItem(e, 'door')),
        ...results[3].map((e) => _normalizeItem(e, 'path')),
      ];

      merged.sort((a, b) {
        final da = _parseAnyDate(a.assignedAt) ?? DateTime(1970);
        final db = _parseAnyDate(b.assignedAt) ?? DateTime(1970);
        return db.compareTo(da);
      });

      if (!mounted) return;

      setState(() {
        _items = merged;
        _isLoading = false;
        _isRefreshing = false;
      });

      _maybePromptContinueItem();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Request timed out while loading exams.';
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

  MyExamItem _normalizeItem(Map<String, dynamic> raw, String type) {
    return MyExamItem(
      type: type,
      uuid: (raw['uuid'] ?? raw['id'] ?? '').toString(),
      title: (raw['title'] ?? raw['name'] ?? 'Item').toString(),
      instructions: _pickInstructions(raw),
      status: (raw['status'] ?? 'active').toString(),
      myStatus: (raw['my_status'] ?? raw['myStatus'] ?? 'pending').toString(),
      durationText: _toDurationText(raw),
      assignedAt:
          (raw['assigned_at'] ??
                  raw['assignment_time'] ??
                  raw['assigned_on'] ??
                  raw['assignedAt'] ??
                  raw['created_at'])
              ?.toString(),
      createdAt: raw['created_at']?.toString(),
      raw: Map<String, dynamic>.from(raw),
    );
  }

  String _pickInstructions(Map<String, dynamic> raw) {
    final value =
        raw['instructions_html'] ??
        raw['instructions'] ??
        raw['excerpt'] ??
        raw['description'] ??
        raw['note'] ??
        '';
    return value.toString();
  }

  String _toDurationText(Map<String, dynamic> raw) {
    final totalTime =
        raw['total_time'] ?? raw['total_time_minutes'] ?? raw['duration'];

    if (totalTime != null && totalTime.toString().trim().isNotEmpty) {
      final n = int.tryParse(totalTime.toString());
      if (n != null) return '$n min';
      return totalTime.toString();
    }

    final seconds = raw['time_limit_sec'] ?? raw['time_limit'];
    if (seconds != null && seconds.toString().trim().isNotEmpty) {
      final s = int.tryParse(seconds.toString());
      if (s != null) return '${(s / 60).ceil()} min';
      return seconds.toString();
    }

    return '—';
  }

  DateTime? _parseAnyDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final dt = DateTime.tryParse(raw);
    if (dt != null) return dt;

    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$',
    ).firstMatch(raw.trim());

    if (match == null) return null;

    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
  }

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _formatDateTime(String? raw) {
    final dt = _parseAnyDate(raw);
    if (dt == null) return '—';

    int hour = dt.hour;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;

    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}, $hour:$minute $suffix';
  }

  String _plainInstructions(String value) {
    var text = value;
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    return text.trim();
  }

  int _pickAllowedAttempts(MyExamItem item) {
    final raw = item.raw;
    final value =
        raw['max_attempts_allowed'] ??
        raw['max_attempts'] ??
        raw['max_attempt'] ??
        raw['total_attempts_allowed'] ??
        raw['attempts_allowed'] ??
        raw['allowed_attempts'] ??
        raw['total_attempts'] ??
        1;

    final parsed = int.tryParse(value.toString());
    return parsed == null || parsed <= 0 ? 1 : parsed;
  }

  int _pickUsedAttempts(MyExamItem item) {
    final raw = item.raw;

    Map<String, dynamic>? resultMap;
    if (raw['result'] is Map) {
      resultMap = Map<String, dynamic>.from(raw['result'] as Map);
    }

    final candidates = [
      raw['attempt_total_count'],
      raw['my_attempts'],
      raw['attempts_used'],
      raw['attempts_taken'],
      raw['attempt_count'],
      raw['latest_attempt_no'],
      raw['used_attempts'],
      resultMap?['attempt_no'],
    ];

    for (final v in candidates) {
      if (v != null && v.toString().trim().isNotEmpty) {
        final parsed = int.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
    }

    if (item.type == 'quiz') {
      if (item.myStatus.toLowerCase() == 'completed') return 1;
      if (raw['attempt'] is Map) return 1;
      if (raw['result'] is Map) return 1;
    }

    return 0;
  }

  int _computeRemainingAttempts(MyExamItem item, int allowed, int used) {
    final raw = item.raw;
    if (raw['remaining_attempts'] != null) {
      final parsed = int.tryParse(raw['remaining_attempts'].toString());
      if (parsed != null) return parsed < 0 ? 0 : parsed;
    }
    final remaining = allowed - used;
    return remaining < 0 ? 0 : remaining;
  }

  bool? _toBool(dynamic v) {
    if (v == true || v == 1) return true;
    if (v == false || v == 0) return false;

    final s = v?.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  _ExamActionMeta _buildActionMeta(MyExamItem item) {
    final status = item.status.toLowerCase();
    final myStatus = item.myStatus.toLowerCase();

    final allowed = _pickAllowedAttempts(item);
    final used = _pickUsedAttempts(item);
    final remaining = _computeRemainingAttempts(item, allowed, used);

    final apiMaxReached = _toBool(item.raw['max_attempt_reached']);
    final apiCanAttempt = _toBool(item.raw['can_attempt']);

    final maxAttemptReached =
        myStatus != 'in_progress' &&
        (apiMaxReached == true ||
            apiCanAttempt == false ||
            remaining <= 0 ||
            used >= allowed);

    String label = 'Start';
    if (myStatus == 'in_progress') {
      label = 'Continue';
    } else if (myStatus == 'completed') {
      label = 'Retake';
    }

    if (maxAttemptReached) {
      label = 'Finished';
    }

    final disabled =
        status != 'active' || maxAttemptReached || item.uuid.trim().isEmpty;

    String? reason;
    if (status != 'active') {
      reason = 'This exam is not active right now.';
    } else if (maxAttemptReached) {
      reason = 'Maximum attempts reached ($used/$allowed).';
    } else if (item.uuid.trim().isEmpty) {
      reason = 'Exam link is not available.';
    }

    return _ExamActionMeta(
      label: label,
      disabled: disabled,
      reason: reason,
      allowedAttempts: allowed,
      usedAttempts: used,
    );
  }

  bool _isFinishedItem(MyExamItem item) {
    final myStatus = item.myStatus.toLowerCase();
    final meta = _buildActionMeta(item);
    return myStatus == 'completed' || meta.label == 'Finished';
  }

  List<MyExamItem> get _filteredItems {
    if (_query.isEmpty) return _items;

    return _items.where((item) {
      return item.title.toLowerCase().contains(_query);
    }).toList();
  }

  List<MyExamItem> get _allExamItems {
    return _items.where((item) => !_isFinishedItem(item)).toList();
  }

  List<MyExamItem> get _allFinishedItems {
    return _items.where((item) => _isFinishedItem(item)).toList();
  }

  List<MyExamItem> get _filteredExamItems {
    return _filteredItems.where((item) => !_isFinishedItem(item)).toList();
  }

  List<MyExamItem> get _filteredFinishedItems {
    return _filteredItems.where((item) => _isFinishedItem(item)).toList();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openExamPage(MyExamItem item) async {
    if (!mounted) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ExamPage(quizKey: item.uuid.trim(), isDark: widget.isDark),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      await _loadItems(refreshing: true);
    } else {
      await _loadItems(refreshing: true);
    }
  }

  Future<void> _showInstructions(MyExamItem item) async {
    final text = _plainInstructions(item.instructions);
    final content = text.isEmpty ? 'No instructions available.' : text;
    final isDark = widget.isDark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bgColor = isDark ? _darkCard : Colors.white;
        final textColor = isDark ? Colors.white : _deep;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              expand: false,
              builder: (context, controller) {
                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 54,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.2)
                            : const Color(0xFFD5C4C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: _primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
                        children: [
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : const Color(0xFFFFFAFB),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.1)
                                    : _line,
                              ),
                            ),
                            child: Text(
                              content,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: textColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  bool _canOpenItem(MyExamItem item) {
    if (widget.onStartExam != null) return true;
    return item.type == 'quiz';
  }

  MyExamItem? _findContinueItem() {
    for (final item in _items) {
      final myStatus = item.myStatus.toLowerCase();
      final meta = _buildActionMeta(item);

      if (myStatus == 'in_progress' && !meta.disabled && _canOpenItem(item)) {
        return item;
      }
    }

    return null;
  }

  void _maybePromptContinueItem() {
    if (!mounted || _continueDialogVisible) return;

    final item = _findContinueItem();
    if (item == null) return;

    _continueDialogVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _continueDialogVisible = false;
        return;
      }

      await _showContinueDialog(item);
      _continueDialogVisible = false;
    });
  }

  Future<void> _showContinueDialog(MyExamItem item) async {
    final isDark = widget.isDark;
    final meta = _buildActionMeta(item);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final bgColor = isDark ? _darkCard : Colors.white;
        final textColor = isDark ? Colors.white : _deep;
        final subtitleColor = isDark ? _darkMuted : _muted;
        final borderColor = isDark ? Colors.white.withOpacity(0.06) : _line;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.34 : 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: _primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Continue Running Exam',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'This exam is already running. Continue from where you left off.',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : const Color(0xFFFFF8FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          color: _primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : const Color(0xFFFFF8FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.play_circle_outline_rounded,
                          color: _primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Status: In progress',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Later',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: meta.disabled
                            ? null
                            : () {
                                Navigator.of(dialogContext).pop();
                                _handleStart(item);
                              },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text(
                          'Continue',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _primary.withOpacity(0.4),
                          disabledForegroundColor: Colors.white.withOpacity(
                            0.65,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleStart(MyExamItem item) async {
    final meta = _buildActionMeta(item);

    if (meta.disabled) {
      _showSnack(meta.reason ?? 'This exam cannot be started.');
      return;
    }

    if (widget.onStartExam != null) {
      widget.onStartExam!(item);
      return;
    }

    if (item.type != 'quiz') {
      _showSnack(
        'This item is not linked to ExamPage yet. Quiz items will open the exam screen.',
      );
      return;
    }

    await _openExamPage(item);
  }

  Widget _buildSegmentTabs(bool isDark) {
    final bg = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF7ECEE);

    final activeBg = isDark ? Colors.white.withOpacity(0.12) : Colors.white;

    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;

    Widget tabButton({
      required int index,
      required String title,
      required int count,
    }) {
      final selected = _selectedTab == index;

      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (!mounted) return;
            setState(() {
              _selectedTab = index;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _primary.withOpacity(isDark ? 0.18 : 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? textPrimary : textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _primary.withOpacity(0.12)
                        : (isDark
                              ? Colors.white.withOpacity(0.08)
                              : const Color(0xFFF3E6E8)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: _primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : _line,
        ),
      ),
      child: Row(
        children: [
          tabButton(index: 0, title: 'Exams', count: _allExamItems.length),
          const SizedBox(width: 6),
          tabButton(
            index: 1,
            title: 'Finished',
            count: _allFinishedItems.length,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final items = _selectedTab == 0
        ? _filteredExamItems
        : _filteredFinishedItems;

    final bgColor = isDark ? _darkBg : _bg;
    final cardColor = isDark ? _darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;
    final softBorder = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF1E4E6);

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: _primary,
        onRefresh: () => _loadItems(refreshing: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                height: 245,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7B2A30), _primary, _secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20,
                      right: -10,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: -28,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      right: 26,
                      child: Icon(
                        Icons.description_rounded,
                        size: 82,
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          const Text(
                            'My Exams',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Search and manage your exams easily',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primary.withOpacity(0.08),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.search_rounded,
                                    color: _primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                        fontSize: 14,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Search exams...',
                                        hintStyle: TextStyle(
                                          color: textSecondary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        focusedErrorBorder: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                      },
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withOpacity(0.1)
                                              : const Color(0xFFF7ECEE),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: _primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildSegmentTabs(isDark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 26),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    _ExamLoadingState(isDark: isDark)
                  else if (_error != null && _items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: softBorder),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.10),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.error_outline_rounded,
                              color: _primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _loadItems(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: softBorder),
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
                              Icons.description_outlined,
                              color: _primary,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _selectedTab == 0
                                ? 'No exams found'
                                : 'No finished exams',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _query.isEmpty
                                ? (_selectedTab == 0
                                      ? 'No active or pending exams are available right now.'
                                      : 'No completed or finished exams are available right now.')
                                : 'Try a different search term.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(items.length, (index) {
                      final item = items[index];
                      final meta = _buildActionMeta(item);

                      return TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 360 + (index * 45)),
                        tween: Tween(begin: 0, end: 1),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value.clamp(0, 1),
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 14),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ExamCard(
                            item: item,
                            assignedText: _formatDateTime(item.assignedAt),
                            meta: meta,
                            isDark: isDark,
                            onInstructionTap: () => _showInstructions(item),
                            onStartTap: () => _handleStart(item),
                          ),
                        ),
                      );
                    }),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyExamItem {
  final String type;
  final String uuid;
  final String title;
  final String instructions;
  final String status;
  final String myStatus;
  final String durationText;
  final String? assignedAt;
  final String? createdAt;
  final Map<String, dynamic> raw;

  const MyExamItem({
    required this.type,
    required this.uuid,
    required this.title,
    required this.instructions,
    required this.status,
    required this.myStatus,
    required this.durationText,
    required this.assignedAt,
    required this.createdAt,
    required this.raw,
  });
}

class _ExamActionMeta {
  final String label;
  final bool disabled;
  final String? reason;
  final int allowedAttempts;
  final int usedAttempts;

  const _ExamActionMeta({
    required this.label,
    required this.disabled,
    required this.reason,
    required this.allowedAttempts,
    required this.usedAttempts,
  });
}

class _ExamCard extends StatelessWidget {
  final MyExamItem item;
  final String assignedText;
  final _ExamActionMeta meta;
  final bool isDark;
  final VoidCallback onInstructionTap;
  final VoidCallback onStartTap;

  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);

  static const Color _pastelBlue = Color(0xFFE3F2FD);
  static const Color _pastelGreen = Color(0xFFE8F5E9);
  static const Color _pastelOrange = Color(0xFFFFF3E0);
  static const Color _pastelPurple = Color(0xFFF3E5F5);
  static const Color _pastelPink = Color(0xFFFCE4EC);
  static const Color _pastelTeal = Color(0xFFE0F2F1);

  static const Color _darkPastelBlue = Color(0xFF1E2A3A);
  static const Color _darkPastelGreen = Color(0xFF1E3A2A);
  static const Color _darkPastelOrange = Color(0xFF3A2A1A);
  static const Color _darkPastelPurple = Color(0xFF2A1F3A);
  static const Color _darkPastelPink = Color(0xFF3A1A2A);
  static const Color _darkPastelTeal = Color(0xFF1A3A3A);

  const _ExamCard({
    required this.item,
    required this.assignedText,
    required this.meta,
    required this.isDark,
    required this.onInstructionTap,
    required this.onStartTap,
  });

  Color _getStatusColor() {
    switch (item.myStatus.toLowerCase()) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'in_progress':
        return const Color(0xFF1976D2);
      default:
        return const Color(0xFFF57C00);
    }
  }

  Color _getStatusBgColor() {
    if (isDark) {
      switch (item.myStatus.toLowerCase()) {
        case 'completed':
          return _darkPastelGreen;
        case 'in_progress':
          return _darkPastelBlue;
        default:
          return _darkPastelOrange;
      }
    } else {
      switch (item.myStatus.toLowerCase()) {
        case 'completed':
          return _pastelGreen;
        case 'in_progress':
          return _pastelBlue;
        default:
          return _pastelOrange;
      }
    }
  }

  String _statusLabel() {
    switch (item.myStatus.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In Progress';
      default:
        return 'Pending';
    }
  }

  Color _getSoftColorByIndex(int index) {
    if (isDark) {
      final colors = [
        _darkPastelBlue,
        _darkPastelGreen,
        _darkPastelOrange,
        _darkPastelPurple,
        _darkPastelPink,
        _darkPastelTeal,
      ];
      return colors[index % colors.length];
    } else {
      final colors = [
        _pastelBlue,
        _pastelGreen,
        _pastelOrange,
        _pastelPurple,
        _pastelPink,
        _pastelTeal,
      ];
      return colors[index % colors.length];
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF7C8090);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF1E4E6);

    final statusColor = _getStatusColor();
    final statusBgColor = _getStatusBgColor();
    final statusLabel = _statusLabel();

    final softColorIndex = item.title.hashCode.abs() % 6;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary, _primary.withOpacity(0.6)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_primary, _primary.withOpacity(0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.myStatus.toLowerCase() == 'completed'
                                  ? Icons.check_circle_outline
                                  : item.myStatus.toLowerCase() == 'in_progress'
                                  ? Icons.play_circle_outline
                                  : Icons.pending_outlined,
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getSoftColorByIndex(softColorIndex),
                        isDark ? cardColor : Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF4E9EB),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Assigned',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              assignedText,
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.repeat_rounded,
                              size: 14,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Attempts',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${meta.usedAttempts}/${meta.allowedAttempts}',
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (meta.reason != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A2A1A)
                          : const Color(0xFFFFF8E7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: Color(0xFFF57C00),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            meta.reason!,
                            style: const TextStyle(
                              color: Color(0xFFE67E22),
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: onInstructionTap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: BorderSide(color: _primary.withOpacity(0.3)),
                            backgroundColor: cardColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.menu_book_rounded, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Instructions',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: meta.disabled ? null : onStartTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            disabledBackgroundColor: _primary.withOpacity(0.4),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white.withOpacity(
                              0.6,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  meta.label == 'Continue'
                                      ? Icons.play_circle_outline
                                      : Icons.play_arrow_rounded,
                                  size: 19,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  meta.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamLoadingState extends StatelessWidget {
  final bool isDark;

  const _ExamLoadingState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final shimmerColor = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF3EAEC);

    return Column(
      children: List.generate(4, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 212,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF1E4E6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: shimmerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
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
                                width: 150,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: shimmerColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    height: 58,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFFCF6F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: List.generate(2, (i) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 0 ? 10 : 0),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: shimmerColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      );
                    }),
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
