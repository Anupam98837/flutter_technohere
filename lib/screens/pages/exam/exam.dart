import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';
import 'package:technohere/screens/structure.dart';

class ExamPage extends StatefulWidget {
  final String quizKey;
  final bool isDark;
  final VoidCallback? onExamFinished;
  final VoidCallback? onBackPressed;

  const ExamPage({
    super.key,
    required this.quizKey,
    required this.isDark,
    this.onExamFinished,
    this.onBackPressed,
  });

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WidgetsBindingObserver {
  static const Color _primary = Color(0xFF9E363A);
  static const Color _secondary = Color(0xFFC94B50);
  static const Color _deep = Color(0xFF2A0F10);
  static const Color _bg = Color(0xFFF7F5F8);
  static const Color _surface = Colors.white;
  static const Color _muted = Color(0xFF7C8090);
  static const Color _line = Color(0xFFF1E4E6);
  static const Color _success = Color(0xFF22A06B);
  static const Color _warn = Color(0xFFE8A73C);
  static const Color _info = Color(0xFF5D7BF2);
  static const Color _violet = Color(0xFF6E49B8);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _token = '';
  String? _attemptUuid;
  String? _serverEndAt;

  bool _booting = true;
  bool _startingExam = false;
  bool _examStarted = false;
  bool _isSubmitting = false;
  bool _autoSubmitFired = false;
  String? _error;

  List<ExamQuestion> _questions = [];
  int _currentIndex = 0;

  final Map<String, dynamic> _selections = {};
  final Map<String, bool> _reviews = {};
  final Map<String, bool> _visited = {};
  final Map<String, int> _timeSpentSec = {};
  final Map<String, TextEditingController> _fibControllers = {};
  final List<VoidCallback> _controllerListeners = [];

  int? _activeQuestionId;
  DateTime? _activeQuestionStartedAt;

  Timer? _timer;
  Timer? _cacheSaveTimer;
  bool _isDisposed = false;

  String get _attemptStorageKey => 'attempt_uuid:${widget.quizKey}';
  String get _cacheStorageKey => 'exam_cache:${widget.quizKey}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _prepare();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _leaveActiveQuestion();
    _timer?.cancel();
    _cacheSaveTimer?.cancel();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (final controller in _fibControllers.values) {
      try {
        controller.dispose();
      } catch (_) {}
    }
    _fibControllers.clear();
    _controllerListeners.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _leaveActiveQuestion();
      _cacheSave();
    }
  }

  Future<void> _prepare() async {
    if (_isDisposed) return;
    
    setState(() {
      _booting = true;
      _error = null;
    });

    try {
      _token = await _getToken();

      if (widget.quizKey.trim().isEmpty) {
        throw Exception('Quiz key missing.');
      }

      if (_token.isEmpty) {
        throw Exception('Login session not found. Please log in again.');
      }

      await _showIntroDialog();
    } catch (e) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });

      await _showMessageDialog(
        title: 'Cannot open exam',
        message: _error ?? 'Something went wrong.',
      );
      _goBack();
    } finally {
      if (!mounted || _isDisposed) return;
      setState(() {
        _booting = false;
      });
    }
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('student_token') ??
            prefs.getString('token') ??
            '')
        .trim();
  }

  Future<Map<String, dynamic>> _api(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
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

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');

      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });

      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
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

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] == false) {
        final message = (data['message'] ??
                data['error'] ??
                'HTTP ${response.statusCode}')
            .toString();

        throw ApiException(
          message: message,
          statusCode: response.statusCode,
          payload: data,
        );
      }

      return data;
    } on TimeoutException {
      throw ApiException(
        message: 'Request timed out. Please check your internet and try again.',
        statusCode: 408,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ExamIntroMeta?> _fetchQuizMeta() async {
    try {
      final response = await _api(
        '/api/exam/quizzes/${Uri.encodeComponent(widget.quizKey)}',
      );
      final meta = response['data'] ?? response['quiz'] ?? response;
      if (meta is Map<String, dynamic>) {
        return ExamIntroMeta.fromMap(meta);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showIntroDialog() async {
    final meta = await _fetchQuizMeta();

    if (!mounted || _isDisposed) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _line),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.info_rounded,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              meta?.title.isNotEmpty == true
                                  ? '${meta!.title} • Instructions'
                                  : 'Exam Instructions',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _deep,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _IntroSectionCard(
                        title: 'Description',
                        icon: Icons.sticky_note_2_rounded,
                        child: HtmlMathView(
                          html: meta?.description.isNotEmpty == true
                              ? meta!.description
                              : 'No description provided.',
                          baseUrl: AppConfig.baseUrl,
                          textStyle: const TextStyle(
                            color: _deep,
                            fontSize: 14,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _IntroSectionCard(
                        title: 'Instructions',
                        icon: Icons.menu_book_rounded,
                        child: HtmlMathView(
                          html: meta?.instructions.isNotEmpty == true
                              ? meta!.instructions
                              : 'No instructions provided.',
                          baseUrl: AppConfig.baseUrl,
                          textStyle: const TextStyle(
                            color: _deep,
                            fontSize: 14,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: const [
                          Icon(Icons.schedule_rounded,
                              size: 16, color: _muted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Timer will start only after you press Start Exam.',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _startingExam
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      _goBack();
                                    },
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Back'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _deep,
                                side: BorderSide(color: _line),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _startingExam
                                  ? null
                                  : () async {
                                      setLocalState(() {
                                        _startingExam = true;
                                      });
                                      Navigator.of(context).pop();
                                      await _bootExam();
                                    },
                              icon: _startingExam
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                _startingExam ? 'Starting…' : 'Start Exam',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _bootExam() async {
    if (!mounted || _isDisposed) return;

    setState(() {
      _startingExam = true;
      _error = null;
    });

    try {
      final hadCache = await _cacheLoad();

      if (_attemptUuid != null) {
        try {
          final response = await _api(
            '/api/exam/attempts/${Uri.encodeComponent(_attemptUuid!)}/questions',
          );
          final pack = response['data'] ?? response;

          if (pack is Map<String, dynamic>) {
            final attempt = pack['attempt'];
            if (attempt is Map<String, dynamic>) {
              _serverEndAt = _pickString(
                attempt['server_end_at'],
                attempt['serverEndAt'],
              );
            }

            if (!hadCache || _questions.isEmpty) {
              _questions = _extractQuestions(pack);
              _applyServerSelections(pack['selections']);
            }
          }

          final left = _computeTimeLeft();
          if (left != null && left <= 0) {
            await _clearAllExamClientState();
          } else {
            await _cacheSave();
          }
        } catch (e) {
          if (_isAttemptMissingError(e)) {
            await _clearAllExamClientState();
          }
        }
      }

      if (_attemptUuid == null) {
        final response = await _api(
          '/api/exam/quizzes/${Uri.encodeComponent(widget.quizKey)}/start',
          method: 'POST',
        );

        final attempt = response['attempt'] ??
            response['data']?['attempt'] ??
            response['data'] ??
            {};

        if (attempt is! Map<String, dynamic>) {
          throw Exception('Invalid attempt response.');
        }

        _attemptUuid = _pickString(
          attempt['attempt_uuid'],
          attempt['attemptUuid'],
          attempt['uuid'],
        );

        if ((_attemptUuid ?? '').isEmpty) {
          throw Exception('Attempt ID missing from start API response.');
        }

        _serverEndAt = _pickString(
          attempt['server_end_at'],
          attempt['serverEndAt'],
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_attemptStorageKey, _attemptUuid!);
        await _cacheSave();
      }

      if (!hadCache || _questions.isEmpty) {
        final response = await _api(
          '/api/exam/attempts/${Uri.encodeComponent(_attemptUuid!)}/questions',
        );
        final pack = response['data'] ?? response;

        if (pack is! Map<String, dynamic>) {
          throw Exception('Invalid question response.');
        }

        _questions = _extractQuestions(pack);
        _applyServerSelections(pack['selections']);

        final attempt = pack['attempt'];
        if (attempt is Map<String, dynamic>) {
          _serverEndAt = _pickString(
            attempt['server_end_at'],
            attempt['serverEndAt'],
          );
        }

        _currentIndex = 0;
        await _cacheSave();
      }

      if (_questions.isEmpty) {
        throw Exception('No questions found for this attempt.');
      }

      _examStarted = true;
      _currentIndex = _currentIndex.clamp(0, _questions.length - 1);
      _markVisited(_currentQuestion.questionId);
      _enterQuestion(_currentQuestion.questionId);

      _startTimerIfPossible();

      if (!mounted || _isDisposed) return;
      setState(() {});
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (!mounted || _isDisposed) return;
      setState(() {
        _error = message;
      });
      await _showMessageDialog(
        title: 'Cannot start exam',
        message: message,
      );
      _goBack();
    } finally {
      if (!mounted || _isDisposed) return;
      setState(() {
        _startingExam = false;
        _booting = false;
      });
    }
  }

  List<ExamQuestion> _extractQuestions(Map<String, dynamic> pack) {
    final rawQuestions = pack['questions'];
    if (rawQuestions is! List) return [];
    return rawQuestions
        .whereType<Map>()
        .map((e) => ExamQuestion.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  void _applyServerSelections(dynamic raw) {
    if (raw is! Map) return;

    for (final entry in raw.entries) {
      final qKey = entry.key.toString();
      final value = entry.value;

      if (value is List) {
        _selections[qKey] = List<dynamic>.from(value);
      } else {
        _selections[qKey] = value;
      }
    }

    for (final q in _questions) {
      if (q.type == 'fill_in_the_blank') {
        final key = _qKey(q.questionId);
        final current = _selections[key];
        if (current == null) {
          _selections[key] = <String>[];
        } else if (current is! List) {
          final v = current.toString().trim();
          _selections[key] = v.isEmpty ? <String>[] : <String>[v];
        }
      }
    }
  }

  Future<bool> _cacheLoad() async {
    final prefs = await SharedPreferences.getInstance();

    _attemptUuid = prefs.getString(_attemptStorageKey)?.trim();
    final raw = prefs.getString(_cacheStorageKey);

    if (raw == null || raw.trim().isEmpty) return false;

    try {
      final cache = jsonDecode(raw);
      if (cache is! Map<String, dynamic>) return false;

      final cachedAttempt = cache['attempt_uuid']?.toString().trim();
      if ((_attemptUuid == null || _attemptUuid!.isEmpty) &&
          cachedAttempt != null &&
          cachedAttempt.isNotEmpty) {
        _attemptUuid = cachedAttempt;
        await prefs.setString(_attemptStorageKey, cachedAttempt);
      }

      if (cachedAttempt != null &&
          cachedAttempt.isNotEmpty &&
          _attemptUuid != null &&
          _attemptUuid != cachedAttempt) {
        return false;
      }

      final rawQuestions = cache['questions'];
      if (rawQuestions is List) {
        _questions = rawQuestions
            .whereType<Map>()
            .map((e) => ExamQuestion.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }

      final selections = cache['selections'];
      if (selections is Map) {
        _selections
          ..clear()
          ..addAll(
            selections.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
      }

      final reviews = cache['reviews'];
      if (reviews is Map) {
        _reviews
          ..clear()
          ..addAll(
            reviews.map(
              (key, value) => MapEntry(key.toString(), value == true),
            ),
          );
      }

      final visited = cache['visited'];
      if (visited is Map) {
        _visited
          ..clear()
          ..addAll(
            visited.map(
              (key, value) => MapEntry(key.toString(), value == true),
            ),
          );
      }

      final timeSpent = cache['timeSpentSec'];
      if (timeSpent is Map) {
        _timeSpentSec
          ..clear()
          ..addAll(
            timeSpent.map(
              (key, value) => MapEntry(
                key.toString(),
                int.tryParse(value.toString()) ?? 0,
              ),
            ),
          );
      }

      _currentIndex =
          int.tryParse((cache['currentIndex'] ?? 0).toString()) ?? 0;
      _serverEndAt = cache['serverEndAt']?.toString();

      for (final q in _questions) {
        if (q.type == 'fill_in_the_blank') {
          final key = _qKey(q.questionId);
          final current = _selections[key];
          if (current == null) {
            _selections[key] = <String>[];
          } else if (current is! List) {
            final v = current.toString().trim();
            _selections[key] = v.isEmpty ? <String>[] : <String>[v];
          }
        }
      }

      return _questions.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _cacheSaveDebounced() {
    _cacheSaveTimer?.cancel();
    _cacheSaveTimer = Timer(const Duration(milliseconds: 250), _cacheSave);
  }

  Future<void> _cacheSave() async {
    if (_isDisposed) return;
    
    final prefs = await SharedPreferences.getInstance();

    final payload = {
      'attempt_uuid': _attemptUuid,
      'serverEndAt': _serverEndAt,
      'currentIndex': _currentIndex,
      'questions': _questions.map((e) => e.toMap()).toList(),
      'selections': _selections,
      'reviews': _reviews,
      'visited': _visited,
      'timeSpentSec': _timeSpentSec,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_cacheStorageKey, jsonEncode(payload));
  }

  Future<void> _clearAllExamClientState() async {
    _timer?.cancel();
    _cacheSaveTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptStorageKey);
    await prefs.remove(_cacheStorageKey);

    _attemptUuid = null;
    _serverEndAt = null;
    _questions = [];
    _currentIndex = 0;
    _selections.clear();
    _reviews.clear();
    _visited.clear();
    _timeSpentSec.clear();
    _activeQuestionId = null;
    _activeQuestionStartedAt = null;
    _autoSubmitFired = false;
    _disposeAllControllers();
  }

  DateTime? _parseServerDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final s = value.trim();

    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d+))?$',
    ).firstMatch(s);

    if (match == null) return null;

    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
      int.parse((match.group(7) ?? '0').padRight(3, '0').substring(0, 3)),
    );
  }

  int? _computeTimeLeft() {
    final end = _parseServerDate(_serverEndAt);
    if (end == null) return null;
    return (end.difference(DateTime.now()).inSeconds).clamp(0, 999999);
  }

  void _startTimerIfPossible() {
    _timer?.cancel();

    if (_parseServerDate(_serverEndAt) == null) {
      return;
    }

    void tick() {
      if (_isDisposed) return;
      
      final left = _computeTimeLeft();
      if (left != null && left <= 0 && !_autoSubmitFired) {
        _autoSubmitFired = true;
        _timer?.cancel();
        _submitExam(auto: true);
      }
      if (mounted && !_isDisposed) setState(() {});
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  bool _isAttemptMissingError(Object error) {
    if (error is ApiException) {
      final msg = error.message.toLowerCase();
      final payloadMsg =
          (error.payload?['message'] ?? '').toString().toLowerCase();

      return (error.statusCode == 404 &&
              (msg.contains('attempt') || payloadMsg.contains('attempt'))) ||
          msg.contains('attempt not found') ||
          payloadMsg.contains('attempt not found');
    }

    final msg = error.toString().toLowerCase();
    return msg.contains('attempt not found');
  }

  void _enterQuestion(int questionId) {
    if (_activeQuestionId != null && _activeQuestionId != questionId) {
      _leaveActiveQuestion();
    }
    _activeQuestionId = questionId;
    _activeQuestionStartedAt = DateTime.now();
  }

  void _leaveActiveQuestion() {
    if (_activeQuestionId == null || _activeQuestionStartedAt == null) return;

    final diffSec = DateTime.now()
        .difference(_activeQuestionStartedAt!)
        .inSeconds
        .clamp(1, 999999);

    final key = _qKey(_activeQuestionId!);
    _timeSpentSec[key] = (_timeSpentSec[key] ?? 0) + diffSec;

    _activeQuestionId = null;
    _activeQuestionStartedAt = null;
    _cacheSaveDebounced();
  }

  String _pickString(dynamic a, [dynamic b, dynamic c, dynamic d]) {
    final values = [a, b, c, d];
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _qKey(int id) => id.toString();

  ExamQuestion get _currentQuestion => _questions[_currentIndex];

  bool _isAnswered(int questionId) {
    final value = _selections[_qKey(questionId)];
    if (value == null) return false;
    if (value is List) {
      return value.any((e) => e.toString().trim().isNotEmpty);
    }
    return value.toString().trim().isNotEmpty;
  }

  int _answeredCount() {
    return _questions.where((q) => _isAnswered(q.questionId)).length;
  }

  double _progressPercent() {
    if (_questions.isEmpty) return 0;
    return _answeredCount() / _questions.length;
  }

  void _markVisited(int questionId) {
    _visited[_qKey(questionId)] = true;
    _cacheSaveDebounced();
  }

  Future<void> _goToQuestion(int index) async {
    if (!_examStarted || _isDisposed) return;
    if (index < 0 || index >= _questions.length) return;
    if (_currentIndex == index) return;

    _leaveActiveQuestion();

    if (mounted && !_isDisposed) {
      setState(() {
        _currentIndex = index;
        _markVisited(_currentQuestion.questionId);
      });
    }

    _enterQuestion(_currentQuestion.questionId);
  }

  void _onPrevious() {
    if (_currentIndex > 0) {
      _goToQuestion(_currentIndex - 1);
    }
  }

  void _onNext() {
    if (_currentIndex < _questions.length - 1) {
      _goToQuestion(_currentIndex + 1);
    } else {
      _submitExam(auto: false);
    }
  }

  void _toggleReview() {
    final key = _qKey(_currentQuestion.questionId);
    if (mounted && !_isDisposed) {
      setState(() {
        _reviews[key] = !(_reviews[key] ?? false);
      });
    }
    _cacheSaveDebounced();
  }

  void _setSingleAnswer(int questionId, int answerId) {
    if (mounted && !_isDisposed) {
      setState(() {
        _selections[_qKey(questionId)] = answerId;
      });
    }
    _cacheSaveDebounced();
  }

  void _toggleMultiAnswer(int questionId, int answerId) {
    final key = _qKey(questionId);
    final current = (_selections[key] is List)
        ? List<dynamic>.from(_selections[key] as List)
        : <dynamic>[];

    if (current.map((e) => e.toString()).contains(answerId.toString())) {
      current.removeWhere((e) => e.toString() == answerId.toString());
    } else {
      current.add(answerId);
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _selections[key] = current;
      });
    }
    _cacheSaveDebounced();
  }

  void _updateFibAnswer(int questionId, int index, String value) {
    if (_isDisposed) return;
    
    final key = _qKey(questionId);
    final gaps = _countGaps(_currentQuestion);
    
    List<String> current;
    final existing = _selections[key];
    if (existing is List) {
      current = List<String>.from(existing.map((e) => e.toString()));
    } else if (existing != null) {
      current = [existing.toString()];
    } else {
      current = [];
    }
    
    while (current.length < gaps) {
      current.add('');
    }
    
    if (index < current.length) {
      current[index] = value;
    }
    
    if (mounted && !_isDisposed) {
      setState(() {
        _selections[key] = current;
      });
    }
    _cacheSaveDebounced();
  }

  int _countGaps(ExamQuestion q) {
    final regex = RegExp(r'\{dash\}', caseSensitive: false);
    final titleCount = regex.allMatches(q.titleHtml).length;
    final descCount = regex.allMatches(q.descriptionHtml).length;
    if (titleCount + descCount > 0) return titleCount + descCount;
    return q.answers.isNotEmpty ? q.answers.length : 1;
  }

  List<dynamic> _submitAnswersPayload() {
    _leaveActiveQuestion();

    return _questions.map((q) {
      return {
        'question_id': q.questionId,
        'selected': _selections[_qKey(q.questionId)],
        'time_spent_sec': _timeSpentSec[_qKey(q.questionId)] ?? 0,
      };
    }).toList();
  }

  Future<void> _submitExam({required bool auto}) async {
    if (_isSubmitting || _isDisposed) return;

    if ((_attemptUuid ?? '').trim().isEmpty) {
      await _showMessageDialog(
        title: 'Cannot submit',
        message: 'Attempt ID is missing. Please refresh and try again.',
      );
      return;
    }

    if (!auto) {
      final confirmed = await _showConfirmDialog(
        title: 'Submit exam?',
        message: 'Once submitted, answers cannot be changed.',
        confirmText: 'Submit',
      );
      if (!confirmed) return;
    }

    if (!mounted || _isDisposed) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final payload = {'answers': _submitAnswersPayload()};

      try {
        await _api(
          '/api/exam/attempts/${Uri.encodeComponent(_attemptUuid!)}/bulk-answer',
          method: 'POST',
          body: payload,
          timeoutSeconds: 25,
        );
      } catch (e) {
        if (_isAttemptMissingError(e)) rethrow;
      }

      await _api(
        '/api/exam/attempts/${Uri.encodeComponent(_attemptUuid!)}/submit',
        method: 'POST',
        timeoutSeconds: 25,
      );

      await _clearAllExamClientState();

      if (!mounted || _isDisposed) return;
      await _showMessageDialog(
        title: auto ? 'Exam Auto-Submitted' : 'Exam Submitted',
        message: auto
            ? 'Your exam time ended and your responses have been automatically recorded.'
            : 'Your responses have been recorded successfully.',
      );

      _finishAndExit();
    } catch (e) {
      if (_isAttemptMissingError(e)) {
        await _clearAllExamClientState();
        if (!mounted || _isDisposed) return;
        await _showMessageDialog(
          title: auto ? 'Exam Time Ended' : 'Exam Already Closed',
          message: auto
              ? 'Your exam time has ended. Your responses may already be recorded.'
              : 'This attempt is no longer active. Your responses may have already been recorded.',
        );
        _finishAndExit();
        return;
      }

      final message = e.toString().replaceFirst('Exception: ', '');
      if (!mounted || _isDisposed) return;
      await _showMessageDialog(
        title: 'Submit Failed',
        message: message,
      );
    } finally {
      if (mounted && !_isDisposed) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _showMessageDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted || _isDisposed) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    String confirmText = 'Confirm',
  }) async {
    if (!mounted || _isDisposed) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _finishAndExit() {
  if (_isDisposed || !mounted) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _isDisposed) return;

    if (widget.onExamFinished != null) {
      widget.onExamFinished!();
    } else {
      Navigator.of(context).maybePop(true);
    }
  });
}

  void _goBack() {
    if (_isDisposed) return;
    
    if (widget.onBackPressed != null) {
      widget.onBackPressed!.call();
      return;
    }

    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  String _timeText() {
    final left = _computeTimeLeft();
    if (left == null) return '--:--';

    final minutes = (left ~/ 60).toString().padLeft(2, '0');
    final seconds = (left % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _questionTypeLabel(ExamQuestion q) {
    if (q.type == 'fill_in_the_blank') return 'Fill in the blanks';
    if (q.type == 'true_false') return 'True / False';
    if (q.hasMultipleCorrectAnswer) return 'Multiple choice';
    return 'Single choice';
  }

  Widget _buildQuestionBody() {
    if (_error != null && _questions.isEmpty) {
      return _buildCenteredError();
    }

    if (_booting || _startingExam || (_examStarted && _questions.isEmpty)) {
      return _buildQuestionSkeleton();
    }

    if (!_examStarted) {
      return _buildWaitingState();
    }

    final q = _currentQuestion;
    final review = _reviews[_qKey(q.questionId)] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: _primary.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _chip(
                              'Q${_currentIndex + 1} of ${_questions.length}',
                              bg: _primary.withOpacity(0.10),
                              color: _primary,
                              icon: Icons.help_outline_rounded,
                            ),
                            _chip(
                              '${q.questionMark} mark${q.questionMark == 1 ? '' : 's'}',
                              bg: const Color(0xFFFDF3E7),
                              color: const Color(0xFFB56E17),
                              icon: Icons.stars_rounded,
                            ),
                            _chip(
                              _questionTypeLabel(q),
                              bg: const Color(0xFFF3EFFB),
                              color: const Color(0xFF6E49B8),
                              icon: Icons.category_rounded,
                            ),
                          ],
                        ),
                      ),
                      if (review)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFFFFD99A),
                            ),
                          ),
                          child: const Text(
                            'Review',
                            style: TextStyle(
                              color: Color(0xFFB56E17),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HtmlMathView(
                    html:
                        '<div><strong>Q${_currentIndex + 1}.</strong> ${q.titleHtml}</div>',
                    baseUrl: AppConfig.baseUrl,
                    textStyle: const TextStyle(
                      color: _deep,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                    ),
                  ),
                  if (q.descriptionHtml.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    HtmlMathView(
                      html: q.descriptionHtml,
                      baseUrl: AppConfig.baseUrl,
                      textStyle: const TextStyle(
                        color: _muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildOptions(q),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(ExamQuestion q) {
    if (q.type == 'fill_in_the_blank') {
      final gaps = _countGaps(q);
      final key = _qKey(q.questionId);
      
      List<String> currentValues;
      final existing = _selections[key];
      if (existing is List) {
        currentValues = List<String>.from(existing.map((e) => e.toString()));
      } else if (existing != null) {
        currentValues = [existing.toString()];
      } else {
        currentValues = [];
      }
      
      while (currentValues.length < gaps) {
        currentValues.add('');
      }
      
      final controllers = <TextEditingController>[];
      for (int i = 0; i < gaps; i++) {
        final controllerKey = '${q.questionId}_$i';
        TextEditingController controller;
        
        if (_fibControllers.containsKey(controllerKey)) {
          controller = _fibControllers[controllerKey]!;
          if (controller.text != currentValues[i]) {
            controller.text = currentValues[i];
          }
        } else {
          controller = TextEditingController(text: currentValues[i]);
          final listener = () {
            if (!_isDisposed) {
              _updateFibAnswer(q.questionId, i, controller.text);
            }
          };
          controller.addListener(listener);
          _controllerListeners.add(listener);
          _fibControllers[controllerKey] = controller;
        }
        controllers.add(controller);
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAFB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your answers',
              style: TextStyle(
                color: _deep,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(gaps, (index) {
                return SizedBox(
                  width: 220,
                  child: TextFormField(
                    controller: controllers[index],
                    decoration: InputDecoration(
                      hintText: 'Answer ${index + 1}',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: _primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            const Text(
              'Enter each blank separately. Answers are case-insensitive.',
              style: TextStyle(
                color: _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: q.answers.map((answer) {
        final key = _qKey(q.questionId);
        final checked = q.hasMultipleCorrectAnswer
            ? ((_selections[key] is List)
                ? (_selections[key] as List)
                    .map((e) => e.toString())
                    .contains(answer.answerId.toString())
                : false)
            : (_selections[key]?.toString() == answer.answerId.toString());

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              if (q.hasMultipleCorrectAnswer) {
                _toggleMultiAnswer(q.questionId, answer.answerId);
              } else {
                _setSingleAnswer(q.questionId, answer.answerId);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: checked ? _primary.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: checked ? _primary : _line,
                  width: checked ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: checked
                        ? _primary.withOpacity(0.10)
                        : Colors.black.withOpacity(0.02),
                    blurRadius: checked ? 16 : 8,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: q.hasMultipleCorrectAnswer
                          ? Checkbox(
                              value: checked,
                              activeColor: _primary,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              onChanged: (_) {
                                _toggleMultiAnswer(
                                  q.questionId,
                                  answer.answerId,
                                );
                              },
                            )
                          : Radio<int>(
                              value: answer.answerId,
                              groupValue: int.tryParse(
                                _selections[_qKey(q.questionId)]?.toString() ??
                                    '',
                              ),
                              activeColor: _primary,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) {
                                _setSingleAnswer(q.questionId, answer.answerId);
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: HtmlMathView(
                        html: answer.answerTitle,
                        baseUrl: AppConfig.baseUrl,
                        textStyle: const TextStyle(
                          color: _deep,
                          fontSize: 14.2,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNavigatorDrawer() {
    final answered = _answeredCount();
    final total = _questions.isEmpty ? 1 : _questions.length;
    final pct = (_progressPercent() * 100).round();

    return Drawer(
      width: 325,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Container(
          color: _surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: _primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Question Navigator',
                        style: TextStyle(
                          color: _deep,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFAFB),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Progress',
                        style: TextStyle(
                          color: _deep,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: _progressPercent(),
                                minHeight: 10,
                                backgroundColor: const Color(0xFFF3E6E8),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(_primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              color: _primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$answered of $total answered',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _legendDot(
                            color: _primary,
                            text: 'Current',
                          ),
                          _legendDot(
                            color: _success,
                            text: 'Answered',
                          ),
                          _legendDot(
                            color: _warn,
                            text: 'Marked',
                          ),
                          _legendDot(
                            color: const Color(0xFFECEDEF),
                            text: 'Visited',
                            textColor: _deep,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: GridView.builder(
                    itemCount: _questions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final q = _questions[index];
                      final nav = _navStyle(index, q);

                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () async {
                          Navigator.of(context).maybePop();
                          await _goToQuestion(index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: nav.background,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: nav.border,
                              width: nav.isCurrent ? 1.5 : 1,
                            ),
                            boxShadow: nav.isCurrent
                                ? [
                                    BoxShadow(
                                      color: nav.background.withOpacity(0.30),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    )
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: nav.foreground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _questions.isEmpty || _isSubmitting
                        ? null
                        : () => _submitExam(auto: false),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSubmitting ? 'Submitting…' : 'Submit Exam',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _NavStyle _navStyle(int index, ExamQuestion q) {
    final current = index == _currentIndex;
    final reviewed = _reviews[_qKey(q.questionId)] == true;
    final answered = _isAnswered(q.questionId);
    final visited = _visited[_qKey(q.questionId)] == true;

    if (current) {
      return const _NavStyle(
        background: _primary,
        border: _primary,
        foreground: Colors.white,
        isCurrent: true,
      );
    }

    if (reviewed) {
      return const _NavStyle(
        background: _warn,
        border: _warn,
        foreground: _deep,
      );
    }

    if (answered) {
      return const _NavStyle(
        background: _success,
        border: _success,
        foreground: _deep,
      );
    }

    if (visited) {
      return const _NavStyle(
        background: Color(0xFFECEDEF),
        border: Color(0xFFD7DCE1),
        foreground: _deep,
      );
    }

    return const _NavStyle(
      background: Colors.white,
      border: Color(0xFFE7E0E2),
      foreground: _deep,
    );
  }

  Widget _buildBottomBar() {
    if (!_examStarted || _questions.isEmpty) return const SizedBox.shrink();

    final isLast = _currentIndex == _questions.length - 1;
    final reviewed = _reviews[_qKey(_currentQuestion.questionId)] == true;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: _surface,
          border: Border(top: BorderSide(color: _line)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _currentIndex == 0 ? null : _onPrevious,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _deep,
                  side: BorderSide(color: _line),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleReview,
                icon: const Icon(Icons.flag_rounded),
                label: Text(reviewed ? 'Unmark' : 'Mark Review'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: reviewed ? const Color(0xFFB56E17) : _deep,
                  side: BorderSide(
                    color: reviewed ? const Color(0xFFFFD99A) : _line,
                  ),
                  backgroundColor:
                      reviewed ? const Color(0xFFFFF7EA) : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _onNext,
                icon: Icon(
                  isLast ? Icons.send_rounded : Icons.arrow_forward_rounded,
                ),
                label: Text(isLast ? 'Submit' : 'Next'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenteredError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _deep,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _prepare,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: _primary),
              SizedBox(height: 16),
              Text(
                'Preparing your exam…',
                style: TextStyle(
                  color: _deep,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _skeleton(height: 18, widthFactor: .56),
              const SizedBox(height: 12),
              _skeleton(height: 14, widthFactor: .86),
              const SizedBox(height: 10),
              _skeleton(height: 14, widthFactor: .64),
              const SizedBox(height: 22),
              _skeleton(height: 92, widthFactor: 1),
              const SizedBox(height: 12),
              _skeleton(height: 92, widthFactor: 1),
              const SizedBox(height: 12),
              _skeleton(height: 92, widthFactor: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeleton({required double height, required double widthFactor}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF2E9EB),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _legendDot({
    required Color color,
    required String text,
    Color textColor = _muted,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _chip(
    String label, {
    required Color bg,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBadge({
    required String title,
    required String value,
    required Color background,
    required Color foreground,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 7),
          Text(
            '$title ',
            style: TextStyle(
              color: foreground.withOpacity(0.90),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: foreground,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final answered = _answeredCount();
    final total = _questions.length;
    final current = total == 0 ? 0 : (_currentIndex + 1);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildNavigatorDrawer(),
      backgroundColor: _bg,
      bottomNavigationBar: _buildBottomBar(),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
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
                    bottomLeft: Radius.circular(34),
                    bottomRight: Radius.circular(34),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                _scaffoldKey.currentState?.openDrawer();
                              },
                              icon: const Icon(
                                Icons.menu_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _timeText(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _headerBadge(
                                title: 'Answered',
                                value: '$answered',
                                background: Colors.white.withOpacity(0.14),
                                foreground: const Color(0xFFFFFFFF),
                                icon: Icons.check_circle_rounded,
                              ),
                              const SizedBox(width: 8),
                              _headerBadge(
                                title: 'Total',
                                value: '$total',
                                background: const Color(0x33B79CFF),
                                foreground: const Color(0xFFF3E9FF),
                                icon: Icons.layers_rounded,
                              ),
                              const SizedBox(width: 8),
                              _headerBadge(
                                title: 'Current',
                                value: '$current',
                                background: const Color(0x332ED0FF),
                                foreground: const Color(0xFFE8FBFF),
                                icon: Icons.adjust_rounded,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildQuestionBody()),
            ],
          ),
          if (_isSubmitting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.28),
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _primary),
                      SizedBox(height: 16),
                      Text(
                        'Submitting your exam…',
                        style: TextStyle(
                          color: _deep,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Please wait while your responses are saved.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HtmlMathView extends StatelessWidget {
  final String html;
  final String baseUrl;
  final TextStyle? textStyle;

  const HtmlMathView({
    super.key,
    required this.html,
    required this.baseUrl,
    this.textStyle,
  });

  String _resolveUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }

    final cleanBase = baseUrl.replaceAll(RegExp(r'/$'), '');
    if (trimmed.startsWith('/')) {
      return '$cleanBase$trimmed';
    }
    return '$cleanBase/$trimmed';
  }

  String _normalizeAssetUrls(String raw) {
    return raw.replaceAllMapped(
      RegExp(r'''src\s*=\s*(['"])(.*?)\1''', caseSensitive: false),
      (match) {
        final quote = match.group(1) ?? '"';
        final src = match.group(2) ?? '';
        return 'src=$quote${_resolveUrl(src)}$quote';
      },
    );
  }

  String _replaceDashes(String raw) {
    return raw.replaceAllMapped(
      RegExp(r'\{dash\}', caseSensitive: false),
      (_) => '<span style="display:inline-block; min-width:80px; border-bottom:2px solid #cbd5e1; margin:0 4px;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>',
    );
  }

  String _decorateMathTags(String raw) {
    String data = raw;

    // Handle display math with double dollar signs
    data = data.replaceAllMapped(
      RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true),
      (m) {
        final latex = m.group(1)?.trim() ?? '';
        if (latex.isEmpty) return '';
        final encoded = Uri.encodeComponent(latex);
        return '<math-block data-latex="$encoded"></math-block>';
      },
    );

    // Handle display math with \[ \]
    data = data.replaceAllMapped(
      RegExp(r'\\\[([\s\S]*?)\\\]', multiLine: true),
      (m) {
        final latex = m.group(1)?.trim() ?? '';
        if (latex.isEmpty) return '';
        final encoded = Uri.encodeComponent(latex);
        return '<math-block data-latex="$encoded"></math-block>';
      },
    );

    // Handle inline math with \( \)
    data = data.replaceAllMapped(
      RegExp(r'\\\(([\s\S]*?)\\\)', multiLine: true),
      (m) {
        final latex = m.group(1)?.trim() ?? '';
        if (latex.isEmpty) return '';
        final encoded = Uri.encodeComponent(latex);
        return '<math-inline data-latex="$encoded"></math-inline>';
      },
    );

    // Handle inline math with single dollars - improved pattern
    data = data.replaceAllMapped(
      RegExp(r'(?<!\$)\$([^\$]+?)\$(?!\$)', multiLine: true),
      (m) {
        final latex = m.group(1)?.trim() ?? '';
        if (latex.isEmpty) return '';
        final encoded = Uri.encodeComponent(latex);
        return '<math-inline data-latex="$encoded"></math-inline>';
      },
    );

    return data;
  }

  String _prepare(String raw) {
    var processed = raw.trim();
    processed = _normalizeAssetUrls(processed);
    processed = _replaceDashes(processed);
    processed = _decorateMathTags(processed);
    processed = '<div style="margin:0; padding:0; line-height:1.6;">$processed</div>';
    return processed;
  }

  @override
  Widget build(BuildContext context) {
    final processed = _prepare(html);

    return HtmlWidget(
      processed,
      textStyle: textStyle ??
          const TextStyle(
            color: Color(0xFF2A0F10),
            fontSize: 14,
            height: 1.6,
          ),
      customWidgetBuilder: (element) {
        if (element.localName == 'math-inline') {
          final latex = Uri.decodeComponent(element.attributes['data-latex'] ?? '');
          if (latex.trim().isEmpty) return const SizedBox.shrink();

          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  latex,
                  mathStyle: MathStyle.text,
                  textStyle: textStyle,
                  onErrorFallback: (error) {
                    debugPrint('Math inline error: $error for latex: $latex');
                    return Text(
                      latex,
                      style: textStyle,
                    );
                  },
                ),
              );
            },
          );
        }

        if (element.localName == 'math-block') {
          final latex = Uri.decodeComponent(element.attributes['data-latex'] ?? '');
          if (latex.trim().isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Math.tex(
                    latex,
                    mathStyle: MathStyle.display,
                    textStyle: textStyle,
                    onErrorFallback: (error) {
                      debugPrint('Math block error: $error for latex: $latex');
                      return Text(
                        latex,
                        style: textStyle,
                      );
                    },
                  ),
                );
              },
            ),
          );
        }

        if (element.localName == 'img') {
          final src = element.attributes['src'] ?? '';
          final resolved = _resolveUrl(src);

          if (resolved.trim().isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.of(context).size.width - 32;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: maxWidth,
                    color: const Color(0xFFF8F3F4),
                    child: Image.network(
                      resolved,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: maxWidth,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _ExamPageState._primary,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: maxWidth,
                          padding: const EdgeInsets.all(14),
                          alignment: Alignment.center,
                          child: const Text(
                            'Image could not be loaded',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _ExamPageState._muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
        }

        return null;
      },
    );
  }
}

class ExamQuestion {
  final int questionId;
  final String type;
  final String titleHtml;
  final String descriptionHtml;
  final int questionMark;
  final bool hasMultipleCorrectAnswer;
  final List<ExamAnswer> answers;

  const ExamQuestion({
    required this.questionId,
    required this.type,
    required this.titleHtml,
    required this.descriptionHtml,
    required this.questionMark,
    required this.hasMultipleCorrectAnswer,
    required this.answers,
  });

  factory ExamQuestion.fromMap(Map<String, dynamic> map) {
    final rawAnswers = map['answers'];
    return ExamQuestion(
      questionId:
          int.tryParse((map['question_id'] ?? map['id'] ?? 0).toString()) ?? 0,
      type: (map['question_type'] ?? map['type'] ?? 'single_choice')
          .toString()
          .trim()
          .toLowerCase(),
      titleHtml: (map['question_title'] ?? map['title'] ?? '').toString(),
      descriptionHtml:
          (map['question_description'] ?? map['description'] ?? '').toString(),
      questionMark:
          int.tryParse((map['question_mark'] ?? map['mark'] ?? 1).toString()) ??
              1,
      hasMultipleCorrectAnswer:
          map['has_multiple_correct_answer'] == true ||
              map['has_multiple_correct_answer'] == 1 ||
              map['multiple'] == true,
      answers: rawAnswers is List
          ? rawAnswers
              .whereType<Map>()
              .map((e) => ExamAnswer.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question_id': questionId,
      'question_type': type,
      'question_title': titleHtml,
      'question_description': descriptionHtml,
      'question_mark': questionMark,
      'has_multiple_correct_answer': hasMultipleCorrectAnswer,
      'answers': answers.map((e) => e.toMap()).toList(),
    };
  }
}

class ExamAnswer {
  final int answerId;
  final String answerTitle;

  const ExamAnswer({
    required this.answerId,
    required this.answerTitle,
  });

  factory ExamAnswer.fromMap(Map<String, dynamic> map) {
    return ExamAnswer(
      answerId:
          int.tryParse((map['answer_id'] ?? map['id'] ?? 0).toString()) ?? 0,
      answerTitle: (map['answer_title'] ?? map['title'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'answer_id': answerId,
      'answer_title': answerTitle,
    };
  }
}

class ExamIntroMeta {
  final String title;
  final String description;
  final String instructions;

  const ExamIntroMeta({
    required this.title,
    required this.description,
    required this.instructions,
  });

  factory ExamIntroMeta.fromMap(Map<String, dynamic> map) {
    String pick(dynamic a, [dynamic b, dynamic c, dynamic d]) {
      final values = [a, b, c, d];
      for (final value in values) {
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    return ExamIntroMeta(
      title: pick(map['quiz_name'], map['title'], map['name'], 'Exam'),
      description: pick(
        map['quiz_description'],
        map['description_html'],
        map['description'],
        map['desc'],
      ),
      instructions: pick(
        map['instructions'],
        map['instructions_html'],
        map['instruction'],
        map['rules'],
      ),
    );
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? payload;

  ApiException({
    required this.message,
    this.statusCode,
    this.payload,
  });

  @override
  String toString() => message;
}

class _NavStyle {
  final Color background;
  final Color border;
  final Color foreground;
  final bool isCurrent;

  const _NavStyle({
    required this.background,
    required this.border,
    required this.foreground,
    this.isCurrent = false,
  });
}

class _IntroSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _IntroSectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1E4E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _ExamPageState._primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: _ExamPageState._deep,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}