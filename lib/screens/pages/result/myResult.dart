import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';
import 'package:url_launcher/url_launcher.dart';

class MyResultPage extends StatefulWidget {
  final bool isDark;

  const MyResultPage({super.key, required this.isDark});

  @override
  State<MyResultPage> createState() => _MyResultPageState();
}

class _MyResultPageState extends State<MyResultPage>
    with WidgetsBindingObserver {
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

  static const String _fixedType = 'quizz';
  static const String _notSeenStatus = 'not_seen';
  static const String _seenStatus = 'seen';
  static const String _localSeenStorageKey = 'my_result_local_seen_items';

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _searchDebounce;

  bool _isLoading = true;
  String? _error;

  List<MyResultItem> _items = [];
  String _seenFilter = _notSeenStatus;

  int _page = 1;
  int _perPage = 20;
  int _total = 0;
  int _totalPages = 1;
  bool _hasMore = false;
  bool _hasKnownTotalPages = false;

  Map<String, dynamic>? _emailStatusCache;
  Map<String, MyResultItem> _localSeenItems = {};
  bool _localSeenLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    _loadItems();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _loadItems(refreshing: true);
    }
  }

  String get _query => _searchController.text.trim();

  void _onSearchChanged() {
    if (!mounted) return;

    setState(() {});

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _page = 1;
      _loadItems();
    });
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('student_token') ?? prefs.getString('token') ?? '')
        .trim();
  }

  Future<void> _ensureLocalSeenLoaded() async {
    if (_localSeenLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localSeenStorageKey);

    if (raw == null || raw.trim().isEmpty) {
      _localSeenLoaded = true;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _localSeenItems = decoded.map((key, value) {
          final itemMap = value is Map<String, dynamic>
              ? value
              : <String, dynamic>{};
          return MapEntry(key, MyResultItem.fromMap(itemMap));
        });
      }
    } catch (_) {
      _localSeenItems = {};
    }

    _localSeenLoaded = true;
  }

  Future<void> _persistLocalSeenItems() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _localSeenItems.map(
      (key, value) => MapEntry(key, value.toMap()),
    );
    await prefs.setString(_localSeenStorageKey, jsonEncode(payload));
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    final raw = value?.toString().trim().toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  DateTime _submittedAtOrEpoch(MyResultItem item) {
    return _parseAnyDate(item.submittedAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<MyResultItem> _applySeenOverrides(List<MyResultItem> serverItems) {
    final seenIds = _localSeenItems.keys.toSet();

    if (_seenFilter == _notSeenStatus) {
      return serverItems
          .where((item) => !seenIds.contains(item.resultUuid.trim()))
          .toList();
    }

    final merged = <String, MyResultItem>{};

    for (final item in _localSeenItems.values) {
      final key = item.resultUuid.trim();
      if (key.isNotEmpty) {
        merged[key] = item;
      }
    }

    for (final item in serverItems) {
      final key = item.resultUuid.trim();
      if (key.isNotEmpty) {
        merged[key] = item;
      }
    }

    final items = merged.values.toList()
      ..sort(
        (a, b) => _submittedAtOrEpoch(b).compareTo(_submittedAtOrEpoch(a)),
      );
    return items;
  }

  Future<void> _markResultSeen(MyResultItem item) async {
    await _ensureLocalSeenLoaded();

    final key = item.resultUuid.trim();
    if (key.isEmpty) return;

    _localSeenItems[key] = item;
    await _persistLocalSeenItems();

    if (!mounted) return;

    setState(() {
      if (_seenFilter == _notSeenStatus) {
        _items.removeWhere((entry) => entry.resultUuid.trim() == key);
      } else {
        final exists = _items.any((entry) => entry.resultUuid.trim() == key);
        if (!exists) {
          _items = [item, ..._items]
            ..sort(
              (a, b) =>
                  _submittedAtOrEpoch(b).compareTo(_submittedAtOrEpoch(a)),
            );
        }
      }
    });
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

  Future<Map<String, dynamic>> _postJsonWithToken(
    String endpoint,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();

    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body ?? <String, dynamic>{}));

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

  Future<void> _loadItems({bool refreshing = false}) async {
    if (!mounted) return;

    setState(() {
      if (!refreshing) {
        _isLoading = true;
      }
      _error = null;
    });

    try {
      final token = await _getToken();
      await _ensureLocalSeenLoaded();

      if (token.isEmpty) {
        throw Exception('Login session not found. Please log in again.');
      }

      final uri = Uri.parse('${AppConfig.baseUrl}/api/student-results/my')
          .replace(
            queryParameters: {
              'page': '$_page',
              'per_page': '$_perPage',
              'type': _fixedType,
              'seen_status': _seenFilter,
              if (_query.isNotEmpty) 'q': _query,
            },
          );

      final result = await _getJsonWithToken(uri.toString(), token);
      final statusCode = result['statusCode'] as int;
      final body = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          (body['message'] ?? body['error'] ?? 'Failed to load results')
              .toString(),
        );
      }

      final rawData = body['data'];
      final pagination = body['pagination'] is Map
          ? Map<String, dynamic>.from(body['pagination'] as Map)
          : <String, dynamic>{};

      final items = rawData is List
          ? rawData
                .whereType<Map>()
                .map((e) => MyResultItem.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : <MyResultItem>[];
      final displayItems = _applySeenOverrides(items);

      final currentPage =
          _asInt(
            pagination['page'] ??
                pagination['current_page'] ??
                pagination['currentPage'],
          ) ??
          _page;

      final total = _asInt(
        pagination['total'] ??
            pagination['total_count'] ??
            pagination['totalCount'],
      );

      final serverPerPage =
          _asInt(
            pagination['per_page'] ??
                pagination['perPage'] ??
                pagination['limit'],
          ) ??
          _perPage;

      final explicitTotalPages = _asInt(
        pagination['total_pages'] ??
            pagination['last_page'] ??
            pagination['lastPage'],
      );

      final rawHasMore =
          _asBool(pagination['has_more'] ?? pagination['hasMore']) || false;

      final hasKnownTotalPages = explicitTotalPages != null || total != null;

      int resolvedTotalPages;
      if (explicitTotalPages != null && explicitTotalPages > 0) {
        resolvedTotalPages = explicitTotalPages;
      } else if (total != null && serverPerPage > 0) {
        resolvedTotalPages = (total / serverPerPage).ceil();
      } else {
        resolvedTotalPages = math.max(1, currentPage);
      }

      final canGoNext = hasKnownTotalPages
          ? currentPage < math.max(1, resolvedTotalPages)
          : rawHasMore;

      if (!mounted) return;

      setState(() {
        _items = displayItems;
        _page = math.max(1, currentPage);
        _total = _seenFilter == _seenStatus
            ? math.max(total ?? displayItems.length, displayItems.length)
            : (total ?? displayItems.length);
        _totalPages = math.max(1, resolvedTotalPages);
        _hasMore = canGoNext;
        _hasKnownTotalPages = hasKnownTotalPages;
        _isLoading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Request timed out while loading results.';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _fetchEmailStatus({bool force = false}) async {
    if (_emailStatusCache != null && !force) {
      return _emailStatusCache!;
    }

    final token = await _getToken();
    if (token.isEmpty) {
      throw Exception('Login session not found. Please log in again.');
    }

    final result = await _getJsonWithToken(
      '${AppConfig.baseUrl}/api/my-email-status',
      token,
    );

    final statusCode = result['statusCode'] as int;
    final body = result['data'] as Map<String, dynamic>;

    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        (body['message'] ?? body['error'] ?? 'Unable to check email status')
            .toString(),
      );
    }

    _emailStatusCache = body;
    return body;
  }

  Future<void> _sendEmailOtp(String email) async {
    final token = await _getToken();
    if (token.isEmpty) {
      throw Exception('Login session not found. Please log in again.');
    }

    final result = await _postJsonWithToken(
      '${AppConfig.baseUrl}/api/student-results/send-email-otp',
      token,
      body: {'email': email},
    );

    final statusCode = result['statusCode'] as int;
    final body = result['data'] as Map<String, dynamic>;

    if (statusCode < 200 || statusCode >= 300 || body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error'] ?? 'Failed to send OTP').toString(),
      );
    }
  }

  Future<void> _verifyEmailOtp(String email, String otp) async {
    final token = await _getToken();
    if (token.isEmpty) {
      throw Exception('Login session not found. Please log in again.');
    }

    final result = await _postJsonWithToken(
      '${AppConfig.baseUrl}/api/student-results/verify-email-otp',
      token,
      body: {'email': email, 'otp': otp},
    );

    final statusCode = result['statusCode'] as int;
    final body = result['data'] as Map<String, dynamic>;

    if (statusCode < 200 || statusCode >= 300 || body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error'] ?? 'Incorrect OTP').toString(),
      );
    }

    _emailStatusCache = null;
  }

  Future<void> _sendResultLink(MyResultItem item, String email) async {
    final token = await _getToken();
    if (token.isEmpty) {
      throw Exception('Login session not found. Please log in again.');
    }

    final result = await _postJsonWithToken(
      '${AppConfig.baseUrl}/api/student-results/send-result-email',
      token,
      body: {
        'result_uuid': item.resultUuid,
        'module': item.module,
        'view_url': _buildViewUrl(item),
        'email': email,
      },
    );

    final statusCode = result['statusCode'] as int;
    final body = result['data'] as Map<String, dynamic>;

    if (statusCode < 200 || statusCode >= 300 || body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error'] ?? 'Failed to send result link')
            .toString(),
      );
    }
  }

  Future<bool> _ensureEmailVerified(MyResultItem item) async {
    try {
      final status = await _fetchEmailStatus();
      final hasEmail =
          (status['is_email'] ?? '').toString().toLowerCase() == 'yes';
      final isVerified =
          (status['is_email_verified'] ?? '').toString().toLowerCase() == 'yes';

      if (hasEmail && isVerified) {
        return true;
      }

      if (!mounted) return false;

      final verified =
          await showDialog<bool>(
            context: context,
            barrierDismissible: true,
            builder: (context) {
              return _ResultEmailGateDialog(
                isDark: widget.isDark,
                title: item.title,
                existingEmail: hasEmail
                    ? (status['email'] ?? '').toString().trim()
                    : '',
                onSendOtp: _sendEmailOtp,
                onVerifyOtp: _verifyEmailOtp,
                onSendResultLink: (email) => _sendResultLink(item, email),
              );
            },
          ) ??
          false;

      if (verified) {
        await _fetchEmailStatus(force: true);
      }

      return verified;
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<void> _openResult(MyResultItem item) async {
    final url = _buildViewUrl(item).trim();

    if (url.isEmpty) {
      _showSnack('Result view link is not available.');
      return;
    }

    final allowed = await _ensureEmailVerified(item);
    if (!allowed) return;

    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      uri = null;
    }

    if (uri == null ||
        !(uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https'))) {
      _showSnack('Invalid result URL.');
      return;
    }

    bool opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      opened = false;
    }

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }

    if (!opened) {
      _showSnack('Could not open result.');
      return;
    }

    await _markResultSeen(item);
  }

  void _goToPage(int targetPage) {
    if (targetPage < 1 || targetPage == _page) return;

    if (_hasKnownTotalPages && targetPage > _totalPages) return;
    if (!_hasKnownTotalPages && targetPage > _page && !_hasMore) return;

    setState(() {
      _page = targetPage;
    });

    _loadItems();
    _scrollToTop();
  }

  DateTime? _parseAnyDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final direct = DateTime.tryParse(raw.trim());
    if (direct != null) return direct;

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

  String _moduleLabel(String type) {
    switch (type) {
      case 'quizz':
        return 'Quizz';
      case 'door_game':
        return 'Door';
      case 'bubble_game':
        return 'Bubble';
      case 'path_game':
        return 'Path';
      default:
        return 'Module';
    }
  }

  IconData _moduleIcon(String type) {
    switch (type) {
      case 'quizz':
        return Icons.quiz_rounded;
      case 'door_game':
        return Icons.door_front_door_rounded;
      case 'bubble_game':
        return Icons.bubble_chart_rounded;
      case 'path_game':
        return Icons.route_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Color _moduleColor(String type) {
    switch (type) {
      case 'quizz':
        return const Color(0xFF7C3AED);
      case 'door_game':
        return const Color(0xFF0F766E);
      case 'bubble_game':
        return const Color(0xFF2563EB);
      case 'path_game':
        return const Color(0xFFEA580C);
      default:
        return _primary;
    }
  }

  String _buildViewUrl(MyResultItem item) {
    if (item.resultUuid.trim().isEmpty) return '';

    switch (item.module) {
      case 'door_game':
        return '${AppConfig.baseUrl}/decision-making-test/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'quizz':
        return '${AppConfig.baseUrl}/exam/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'bubble_game':
        return '${AppConfig.baseUrl}/test/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'path_game':
        return '${AppConfig.baseUrl}/path-game/results/${Uri.encodeComponent(item.resultUuid)}/view';
      default:
        return '';
    }
  }

  List<dynamic> _buildPagerItems() {
    if (_items.isEmpty) return [];

    if (_hasKnownTotalPages) {
      if (_totalPages <= 1) return [];
    } else {
      if (_page <= 1 && !_hasMore) return [];
    }

    if (!_hasKnownTotalPages) {
      return ['prev', 'next'];
    }

    final items = <dynamic>['prev'];

    final start = math.max(1, _page - 3);
    final end = math.min(_totalPages, _page + 3);

    if (start > 1) {
      items.add(1);
      if (start > 2) {
        items.add('left-ellipsis');
      }
    }

    for (int i = start; i <= end; i++) {
      items.add(i);
    }

    if (end < _totalPages) {
      if (end < _totalPages - 1) {
        items.add('right-ellipsis');
      }
      if (!items.contains(_totalPages)) {
        items.add(_totalPages);
      }
    }

    items.add('next');
    return items;
  }

  void _changeSeenFilter(String nextValue) {
    if (nextValue == _seenFilter) return;
    setState(() {
      _seenFilter = nextValue;
      _page = 1;
    });
    _loadItems();
    _scrollToTop();
  }

  Widget _buildHeader(bool isDark) {
    final cardColor = isDark ? _darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;
    final borderColor = isDark ? _darkLine : _line;

    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        height: 290,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7B2A30), _primary, _secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(42),
            bottomRight: Radius.circular(42),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -24,
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
              left: -28,
              child: Container(
                width: 138,
                height: 138,
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
                Icons.bar_chart_rounded,
                size: 84,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'My Results',
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
                    'Search and view your published results',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),
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
                            color: _primary.withOpacity(0.10),
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
                                hintText: 'Search game / folder...',
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
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchDebounce?.cancel();
                                _searchController.clear();
                                setState(() {
                                  _page = 1;
                                });
                                _loadItems();
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.10)
                                      : const Color(0xFFF7ECEE),
                                  borderRadius: BorderRadius.circular(999),
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
                    child: _buildSeenTabs(isDark, inHeader: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeenTabs(bool isDark, {bool inHeader = false}) {
    final cardColor = isDark ? _darkCard : Colors.white;
    final borderColor = isDark ? _darkLine : _line;
    final activeColor = _primary;
    final inactiveText = isDark ? Colors.white : _deep;

    Widget tabButton({
      required String value,
      required String label,
      required IconData icon,
    }) {
      final selected = _seenFilter == value;

      return Expanded(
        child: InkWell(
          onTap: _isLoading ? null : () => _changeSeenFilter(value),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? activeColor : borderColor),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _primary.withOpacity(inHeader ? 0.12 : 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? Colors.white : inactiveText,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : inactiveText,
                      fontSize: 13.5,
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
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: inHeader
            ? [
                BoxShadow(
                  color: _primary.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          tabButton(
            value: _notSeenStatus,
            label: 'Not Seen',
            icon: Icons.visibility_off_rounded,
          ),
          const SizedBox(width: 8),
          tabButton(
            value: _seenStatus,
            label: 'Seen',
            icon: Icons.visibility_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    if (_items.isEmpty) return const SizedBox.shrink();

    final textSecondary = isDark ? _darkMuted : _muted;
    final cardColor = isDark ? _darkCard : Colors.white;
    final borderColor = isDark ? _darkLine : _line;
    final pagerItems = _buildPagerItems();

    final metaText = _hasKnownTotalPages
        ? 'Showing page $_page of $_totalPages — $_total result(s)'
        : (_hasMore
              ? 'Showing page $_page (more available)'
              : 'Showing page $_page');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metaText,
            style: TextStyle(
              color: textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (pagerItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pagerItems.map((item) {
                  if (item == 'left-ellipsis' || item == 'right-ellipsis') {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        '...',
                        style: TextStyle(
                          color: textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }

                  if (item == 'prev') {
                    final disabled = _page <= 1;
                    return _PagerButton(
                      label: 'Previous',
                      active: false,
                      disabled: disabled,
                      onTap: disabled ? null : () => _goToPage(_page - 1),
                    );
                  }

                  if (item == 'next') {
                    final disabled = _hasKnownTotalPages
                        ? _page >= _totalPages
                        : !_hasMore;
                    return _PagerButton(
                      label: 'Next',
                      active: false,
                      disabled: disabled,
                      onTap: disabled ? null : () => _goToPage(_page + 1),
                    );
                  }

                  final pageNumber = item as int;
                  return _PagerButton(
                    label: '$pageNumber',
                    active: pageNumber == _page,
                    disabled: false,
                    onTap: () => _goToPage(pageNumber),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final items = _items;

    final bgColor = isDark ? _darkBg : _bg;
    final cardColor = isDark ? _darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? _darkMuted : _muted;
    final softBorder = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF1E4E6);

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: _primary,
        onRefresh: () => _loadItems(refreshing: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildHeader(isDark),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    _ResultLoadingState(isDark: isDark)
                  else if (_error != null && items.isEmpty)
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
                              Icons.bar_chart_outlined,
                              color: _primary,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _seenFilter == _notSeenStatus
                                ? 'No unseen results'
                                : 'No seen results',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _query.isEmpty
                                ? (_seenFilter == _notSeenStatus
                                      ? 'No published unseen results are available right now.'
                                      : 'No seen results are available right now.')
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

                      return TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 320 + (index * 40)),
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
                          child: _ResultCard(
                            item: item,
                            submittedText: _formatDateTime(item.submittedAt),
                            moduleColor: _moduleColor(item.module),
                            moduleIcon: _moduleIcon(item.module),
                            moduleLabel: _moduleLabel(item.module),
                            isDark: isDark,
                            onViewTap: item.resultUuid.trim().isEmpty
                                ? null
                                : () => _openResult(item),
                          ),
                        ),
                      );
                    }),
                  if (!_isLoading && items.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _buildFooter(isDark),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class MyResultItem {
  final String module;
  final String title;
  final String resultUuid;
  final int attemptNo;
  final double score;
  final String? submittedAt;
  final Map<String, dynamic> raw;

  const MyResultItem({
    required this.module,
    required this.title,
    required this.resultUuid,
    required this.attemptNo,
    required this.score,
    required this.submittedAt,
    required this.raw,
  });

  factory MyResultItem.fromMap(Map<String, dynamic> map) {
    final game = map['game'] is Map
        ? Map<String, dynamic>.from(map['game'] as Map)
        : <String, dynamic>{};

    final result = map['result'] is Map
        ? Map<String, dynamic>.from(map['result'] as Map)
        : <String, dynamic>{};

    return MyResultItem(
      module: (map['module'] ?? '').toString().trim().toLowerCase(),
      title: (game['title'] ?? map['title'] ?? 'Untitled Result').toString(),
      resultUuid: (result['uuid'] ?? '').toString(),
      attemptNo: int.tryParse((result['attempt_no'] ?? 0).toString()) ?? 0,
      score: double.tryParse((result['score'] ?? 0).toString()) ?? 0,
      submittedAt: (result['result_created_at'] ?? result['created_at'])
          ?.toString(),
      raw: Map<String, dynamic>.from(map),
    );
  }

  Map<String, dynamic> toMap() {
    return Map<String, dynamic>.from(raw);
  }
}

class _ResultCard extends StatelessWidget {
  final MyResultItem item;
  final String submittedText;
  final Color moduleColor;
  final IconData moduleIcon;
  final String moduleLabel;
  final bool isDark;
  final VoidCallback? onViewTap;

  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);

  const _ResultCard({
    required this.item,
    required this.submittedText,
    required this.moduleColor,
    required this.moduleIcon,
    required this.moduleLabel,
    required this.isDark,
    required this.onViewTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF7C8090);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF1E4E6);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(isDark ? 0.18 : 0.08),
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
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: moduleColor.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(moduleIcon, color: moduleColor, size: 24),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: moduleColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: moduleColor.withOpacity(0.22),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        moduleLabel,
                        style: TextStyle(
                          color: moduleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
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
                    color: isDark
                        ? Colors.white.withOpacity(0.03)
                        : const Color(0xFFFFFAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF4E9EB),
                    ),
                  ),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.repeat_rounded,
                        iconColor: _primary,
                        label: 'Attempt',
                        value: '#${item.attemptNo}',
                        valueColor: _primary,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.bar_chart_rounded,
                        iconColor: _primary,
                        label: 'Score',
                        value: item.score % 1 == 0
                            ? item.score.toStringAsFixed(0)
                            : item.score.toStringAsFixed(2),
                        valueColor: _primary,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: Icons.schedule_rounded,
                        iconColor: _primary,
                        label: 'Submitted',
                        value: submittedText,
                        valueColor: _primary,
                        textSecondary: textSecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: onViewTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      disabledBackgroundColor: _primary.withOpacity(0.4),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white.withOpacity(0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text(
                      'View Result',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;
  final Color textSecondary;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PagerButton extends StatelessWidget {
  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback? onTap;

  const _PagerButton({
    required this.label,
    required this.active,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF9E363A);

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? primary : primary.withOpacity(0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultLoadingState extends StatelessWidget {
  final bool isDark;

  const _ResultLoadingState({required this.isDark});

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
            height: 225,
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
                                width: 170,
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
                    height: 80,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFFCF6F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(14),
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

class _ResultEmailGateDialog extends StatefulWidget {
  final bool isDark;
  final String title;
  final String existingEmail;
  final Future<void> Function(String email) onSendOtp;
  final Future<void> Function(String email, String otp) onVerifyOtp;
  final Future<void> Function(String email) onSendResultLink;

  const _ResultEmailGateDialog({
    required this.isDark,
    required this.title,
    required this.existingEmail,
    required this.onSendOtp,
    required this.onVerifyOtp,
    required this.onSendResultLink,
  });

  @override
  State<_ResultEmailGateDialog> createState() => _ResultEmailGateDialogState();
}

class _ResultEmailGateDialogState extends State<_ResultEmailGateDialog> {
  static const Color _primary = Color(0xFF9E363A);
  static const Color _deep = Color(0xFF2A0F10);
  static const Color _success = Color(0xFF16A34A);

  late final TextEditingController _emailController;
  late final TextEditingController _otpController;

  Timer? _countdownTimer;

  bool _otpStepVisible = false;
  bool _isVerified = false;

  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _sendingLink = false;

  String? _emailError;
  String? _otpError;
  String? _resultError;
  String? _successText;

  int _countdown = 0;

  bool get _hasExistingEmail => widget.existingEmail.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.existingEmail);
    _otpController = TextEditingController();
    _otpController.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpController.removeListener(_onOtpChanged);
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _onOtpChanged() {
    final digits = _otpController.text.replaceAll(RegExp(r'\D'), '');
    if (digits != _otpController.text) {
      _otpController.value = _otpController.value.copyWith(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }

    if (_isVerified || _verifyingOtp) return;

    if (digits.length == 6) {
      _verifyOtp();
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();

    setState(() {
      _countdown = seconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_countdown <= 1) {
        timer.cancel();
        setState(() {
          _countdown = 0;
        });
      } else {
        setState(() {
          _countdown -= 1;
        });
      }
    });
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^\S+@\S+\.\S+$').hasMatch(value.trim());
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();

    setState(() {
      _emailError = null;
      _otpError = null;
      _resultError = null;
      _successText = null;
    });

    if (!_isValidEmail(email)) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _sendingOtp = true;
    });

    try {
      await widget.onSendOtp(email);

      if (!mounted) return;
      setState(() {
        _otpStepVisible = true;
        _isVerified = false;
        _otpController.clear();
      });
      _startCountdown(120);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _sendingOtp = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.length < 6 || _verifyingOtp) return;

    setState(() {
      _otpError = null;
      _resultError = null;
      _successText = null;
      _verifyingOtp = true;
    });

    try {
      await widget.onVerifyOtp(email, otp);

      if (!mounted) return;

      _countdownTimer?.cancel();

      setState(() {
        _isVerified = true;
        _verifyingOtp = false;
        _otpStepVisible = false;
        _successText = 'Email verified successfully!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otpError = e.toString().replaceFirst('Exception: ', '');
        _verifyingOtp = false;
      });
      _otpController.clear();
    }
  }

  Future<void> _sendResultLink() async {
    final email = _emailController.text.trim();

    setState(() {
      _resultError = null;
      _successText = null;
      _sendingLink = true;
    });

    try {
      await widget.onSendResultLink(email);

      if (!mounted) return;
      setState(() {
        _successText = 'Result link sent to your email.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _sendingLink = false;
      });
    }
  }

  Widget _stepBar(bool active, bool done) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 4,
        decoration: BoxDecoration(
          color: done
              ? _primary
              : (active ? _primary.withOpacity(0.45) : const Color(0xFFE5D8DA)),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : _deep;
    final textSecondary = isDark
        ? const Color(0xFF9A9EAD)
        : const Color(0xFF7C8090);
    final borderColor = isDark
        ? const Color(0xFF2C2C33)
        : const Color(0xFFF1E4E6);
    final fieldBg = isDark
        ? Colors.white.withOpacity(0.04)
        : const Color(0xFFFFFAFB);

    final stepOneDone = _otpStepVisible || _isVerified;
    final stepTwoActive = _otpStepVisible && !_isVerified;
    final stepTwoDone = _isVerified;
    final stepThreeActive = _isVerified;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  _stepBar(!stepOneDone, stepOneDone),
                  const SizedBox(width: 6),
                  _stepBar(stepTwoActive, stepTwoDone),
                  const SizedBox(width: 6),
                  _stepBar(stepThreeActive, false),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.mark_email_read_rounded,
                      color: _primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify your email',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'To continue with "${widget.title}", verify your email first.',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 13.2,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded, color: textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (!_isVerified) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        readOnly: _hasExistingEmail,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your email address',
                          hintStyle: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          filled: true,
                          fillColor: fieldBg,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                            borderSide: BorderSide(color: _primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _sendingOtp ? null : _sendOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _sendingOtp
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Send OTP',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
                if (_hasExistingEmail) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your registered email is pre-filled.',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (_emailError != null) ...[
                  const SizedBox(height: 10),
                  _GateErrorText(text: _emailError!),
                ],
              ],
              if (_otpStepVisible && !_isVerified) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !_verifyingOtp,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 5,
                    fontSize: 18,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Enter 6-digit OTP',
                    hintStyle: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: fieldBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: _primary),
                    ),
                    suffixIcon: _verifyingOtp
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: _primary,
                              ),
                            ),
                          )
                        : const Icon(Icons.key_rounded, color: _primary),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'OTP sent to ${_emailController.text.trim()} — check inbox and spam.',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      "Didn't receive it?",
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: (_countdown > 0 || _sendingOtp)
                          ? null
                          : _sendOtp,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _countdown > 0
                            ? 'Resend in ${_countdown}s'
                            : 'Resend OTP',
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_otpError != null) ...[
                  const SizedBox(height: 10),
                  _GateErrorText(text: _otpError!),
                ],
              ],
              if (_isVerified) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _success.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _success.withOpacity(0.28)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: _success,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Email verified successfully!',
                          style: TextStyle(
                            color: _success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: _sendingLink ? null : _sendResultLink,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: BorderSide(color: _primary.withOpacity(0.28)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _sendingLink
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.1,
                                    color: _primary,
                                  ),
                                )
                              : const Icon(Icons.link_rounded, size: 18),
                          label: const Text(
                            'Send Link',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Continue',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_resultError != null) ...[
                const SizedBox(height: 12),
                _GateErrorText(text: _resultError!),
              ],
              if (_successText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primary.withOpacity(0.16)),
                  ),
                  child: Text(
                    _successText!,
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GateErrorText extends StatelessWidget {
  final String text;

  const _GateErrorText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFDC2626),
          fontSize: 12.8,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}
