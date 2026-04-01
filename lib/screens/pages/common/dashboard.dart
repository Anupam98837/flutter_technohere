import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';

class DashboardModule extends StatefulWidget {
  final String? userName;
  final bool isDark;

  const DashboardModule({
    super.key,
    this.userName,
    required this.isDark,
  });

  @override
  State<DashboardModule> createState() => _DashboardModuleState();
}

class _DashboardModuleState extends State<DashboardModule> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String _period = '30d';
  Map<String, dynamic> _data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _loadDashboard();
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
        'data': decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{},
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('student_token') ??
            prefs.getString('token') ??
            '')
        .trim();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _loadDashboard({bool refreshing = false}) async {
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
      final token = await _getStoredToken();

      if (token.isEmpty) {
        throw Exception('Login session not found. Please log in again.');
      }

      final endpoint =
          '${AppConfig.baseUrl}/api/dashboard/student?period=$_period';

      final result = await _getJsonWithToken(endpoint, token);

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> body =
          result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          (body['message'] ?? 'Failed to load dashboard').toString(),
        );
      }

      if ((body['status'] ?? '').toString().toLowerCase() != 'success') {
        throw Exception(
          (body['message'] ?? 'Failed to load dashboard').toString(),
        );
      }

      final data = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _data = data;
        _isLoading = false;
        _isRefreshing = false;
        _error = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _error = 'Dashboard request timed out.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDouble(dynamic value, {int fraction = 1}) {
    return _toDouble(value).toStringAsFixed(fraction);
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
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  String _formatDateShort(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;

    int hour = dt.hour;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;

    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}, $hour:$minute $suffix';
  }

  String _secondsToPretty(dynamic secValue) {
    final sec = _toInt(secValue);
    if (sec <= 0) return '0m';

    final minutes = sec ~/ 60;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours > 0) {
      return '${hours}h ${remainingMinutes}m';
    }
    return '${minutes}m';
  }

  String _periodLabel(String value) {
    switch (value) {
      case '7d':
        return 'Last 7 days';
      case '30d':
        return 'Last 30 days';
      case '90d':
        return 'Last 90 days';
      case '1y':
        return 'Last 12 months';
      default:
        return 'Custom range';
    }
  }

  String _rangeLabel() {
    final range = _map(_data['date_range']);
    if (range.isEmpty) return _periodLabel(_period);

    final period = _periodLabel((range['period'] ?? _period).toString());
    final start = _formatDateShort(range['start']?.toString());
    final end = _formatDateShort(range['end']?.toString());
    return '$period • $start - $end';
  }

  void _changePeriod(String value) {
    if (value == _period) return;
    setState(() {
      _period = value;
    });
    _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    const primary = Color(0xFF9E363A);
    const wine = Color(0xFF7A2730);
    const blush = Color(0xFFF8E8EB);
    const powder = Color(0xFFF1EEF8);
    const sage = Color(0xFFEEF6F1);
    const sky = Color(0xFFEAF2FC);
    const ink = Color(0xFF2A0F10);
    const muted = Color(0xFF7D8190);

    final bg = isDark ? const Color(0xFF121216) : const Color(0xFFF7F5F8);
    final card = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final softBorder = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFF2E6E9);
    final textPrimary = isDark ? Colors.white : ink;
    final textSecondary = isDark ? Colors.white70 : muted;

    final summary = _map(_data['summary_counts']);
    final quick = _map(_data['quick_stats']);
    final attemptsOverTime = _mapList(_data['attempts_over_time']);
    final scoresOverTime = _mapList(_data['scores_over_time']);
    final bestPerformance = _map(summary['best_performance']);

    final assignedQuizzes = _toInt(summary['assigned_quizzes']);
    final totalAttempts = _toInt(summary['total_attempts']);
    final completedAttempts = _toInt(summary['completed_attempts']);
    final totalResults = _toInt(summary['total_results']);
    final averagePercentage = _formatDouble(summary['average_percentage']);
    final completionRate = totalAttempts == 0
        ? 0
        : (completedAttempts * 100 / totalAttempts);

    final todayStarted = _toInt(quick['today_attempts_started']);
    final todayCompleted = _toInt(quick['today_attempts_completed']);
    final todayTimeSpent = _secondsToPretty(quick['today_time_spent_sec']);

    if (_isLoading) {
      return Container(
        color: bg,
        child: const Center(
          child: CircularProgressIndicator(
            color: primary,
          ),
        ),
      );
    }

    if (_error != null && _data.isEmpty) {
      return Container(
        color: bg,
        child: RefreshIndicator(
          color: primary,
          onRefresh: () => _loadDashboard(refreshing: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: softBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        color: primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _loadDashboard(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: bg,
      child: RefreshIndicator(
        color: primary,
        onRefresh: () => _loadDashboard(refreshing: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          child: Column(
            children: [
              _AnimatedBlock(
                delay: 0,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [wine, primary, Color(0xFFC15B66)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.24),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -32,
                        right: -24,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -42,
                        left: -18,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 58,
                        right: 18,
                        child: Transform.rotate(
                          angle: -0.18,
                          child: Icon(
                            Icons.auto_graph_rounded,
                            size: 70,
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.20),
                                  ),
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/icons/logo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.school_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              _PeriodMenuChip(
                                value: _period,
                                label: _periodLabel(_period),
                                onSelected: _changePeriod,
                              ),
                              const SizedBox(width: 8),
                              _RefreshIconButton(
                                isRefreshing: _isRefreshing,
                                onTap: _isRefreshing
                                    ? null
                                    : () => _loadDashboard(refreshing: true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '${_getGreeting()},',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Track activity, score trends and learning performance in a cleaner mobile view.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _rangeLabel(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (_error != null)
                _AnimatedBlock(
                  delay: 80,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: primary.withOpacity(0.14)),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

              _AnimatedBlock(
                delay: 120,
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 176,
                  ),
                  children: [
                    _DashboardStatCard(
                      title: 'Assigned',
                      value: '$assignedQuizzes',
                      subtitle: assignedQuizzes > 0
                          ? 'Active quizzes assigned to you'
                          : 'No active assignments right now',
                      icon: Icons.assignment_rounded,
                      iconBg: blush,
                      accent: primary,
                      isDark: isDark,
                    ),
                    _DashboardStatCard(
                      title: 'Attempts',
                      value: '$totalAttempts',
                      subtitle:
                          '$completedAttempts completed • ${completionRate.toStringAsFixed(1)}% completion',
                      icon: Icons.timer_rounded,
                      iconBg: powder,
                      accent: const Color(0xFF8458A8),
                      isDark: isDark,
                    ),
                    _DashboardStatCard(
                      title: 'Results',
                      value: '$totalResults',
                      subtitle: bestPerformance.isNotEmpty
                          ? 'Best: ${_formatDouble(bestPerformance['percentage'])}%'
                          : 'Best: —',
                      icon: Icons.bar_chart_rounded,
                      iconBg: sky,
                      accent: const Color(0xFF4B76A8),
                      isDark: isDark,
                    ),
                    _DashboardStatCard(
                      title: 'Performance',
                      value: '$averagePercentage%',
                      subtitle:
                          'Today: $todayStarted started • $todayCompleted completed',
                      icon: Icons.trending_up_rounded,
                      iconBg: sage,
                      accent: const Color(0xFF4F8D68),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _AnimatedBlock(
                delay: 180,
                child: _SectionCard(
                  title: 'Today Snapshot',
                  subtitle: 'Your activity today',
                  isDark: isDark,
                  child: Row(
                    children: [
                      Expanded(
                        child: _MiniMetricCard(
                          label: 'Started',
                          value: '$todayStarted',
                          bgColor: powder,
                          valueColor: ink,
                          labelColor: muted,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniMetricCard(
                          label: 'Completed',
                          value: '$todayCompleted',
                          bgColor: blush,
                          valueColor: ink,
                          labelColor: muted,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniMetricCard(
                          label: 'Time',
                          value: todayTimeSpent,
                          bgColor: sage,
                          valueColor: ink,
                          labelColor: muted,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _AnimatedBlock(
                delay: 240,
                child: _SectionCard(
                  title: 'Attempts Over Time',
                  subtitle: 'Daily attempts in selected period',
                  isDark: isDark,
                  child: attemptsOverTime.isEmpty
                      ? _EmptyState(
                          isDark: isDark,
                          text: 'No attempt data available',
                        )
                      : _ModernLineChart(
                          isDark: isDark,
                          lineColor: primary,
                          fillColor: primary.withOpacity(0.14),
                          pointColor: primary,
                          ySuffix: '',
                          points: attemptsOverTime
                              .map(
                                (e) => _TrendPoint(
                                  label: _formatDateShort(
                                    e['date']?.toString(),
                                  ),
                                  value: _toDouble(e['count']),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
              const SizedBox(height: 14),

              _AnimatedBlock(
                delay: 300,
                child: _SectionCard(
                  title: 'Average Score Over Time',
                  subtitle: 'Daily average percentage',
                  isDark: isDark,
                  child: scoresOverTime.isEmpty
                      ? _EmptyState(
                          isDark: isDark,
                          text: 'No score data available',
                        )
                      : _ModernLineChart(
                          isDark: isDark,
                          lineColor: const Color(0xFF8458A8),
                          fillColor: const Color(0xFF8458A8).withOpacity(0.14),
                          pointColor: const Color(0xFF8458A8),
                          ySuffix: '%',
                          maxY: 100,
                          points: scoresOverTime
                              .map(
                                (e) => _TrendPoint(
                                  label: _formatDateShort(
                                    e['date']?.toString(),
                                  ),
                                  value: _toDouble(e['avg_percentage']),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedBlock extends StatelessWidget {
  final Widget child;
  final int delay;

  const _AnimatedBlock({
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 520 + delay),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 22),
            child: child,
          ),
        );
      },
    );
  }
}

class _PeriodMenuChip extends StatelessWidget {
  final String value;
  final String label;
  final ValueChanged<String> onSelected;

  const _PeriodMenuChip({
    required this.value,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onSelected,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: '7d',
          child: Text('Last 7 days'),
        ),
        PopupMenuItem(
          value: '30d',
          child: Text('Last 30 days'),
        ),
        PopupMenuItem(
          value: '90d',
          child: Text('Last 90 days'),
        ),
        PopupMenuItem(
          value: '1y',
          child: Text('Last 12 months'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshIconButton extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback? onTap;

  const _RefreshIconButton({
    required this.isRefreshing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
          ),
        ),
      ),
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color accent;
  final bool isDark;

  const _DashboardStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF2A0F10);
    final textSecondary =
        isDark ? Colors.white70 : const Color(0xFF7D8190);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFF2E6E9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.14 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.07) : iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: accent,
                  size: 20,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDark;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF2A0F10);
    final textSecondary =
        isDark ? Colors.white70 : const Color(0xFF7D8190);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFF2E6E9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.14 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MiniMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color bgColor;
  final Color valueColor;
  final Color labelColor;
  final bool isDark;

  const _MiniMetricCard({
    required this.label,
    required this.value,
    required this.bgColor,
    required this.valueColor,
    required this.labelColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? Colors.white.withOpacity(0.05) : bgColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white : valueColor,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : labelColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final String text;

  const _EmptyState({
    required this.isDark,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white70 : const Color(0xFF7D8190),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TrendPoint {
  final String label;
  final double value;

  const _TrendPoint({
    required this.label,
    required this.value,
  });
}

class _ModernLineChart extends StatelessWidget {
  final List<_TrendPoint> points;
  final Color lineColor;
  final Color fillColor;
  final Color pointColor;
  final String ySuffix;
  final double? maxY;
  final bool isDark;

  const _ModernLineChart({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.pointColor,
    required this.ySuffix,
    required this.isDark,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF2A0F10);
    final textSecondary =
        isDark ? Colors.white70 : const Color(0xFF7D8190);

    final maxValue = maxY ??
        math.max(
          1,
          points
              .map((e) => e.value)
              .fold<double>(0, (a, b) => math.max(a, b)),
        );

    final minWidth = math.max(
      MediaQuery.of(context).size.width - 64,
      points.length * 52.0,
    );

    final latest = points.isNotEmpty ? points.last.value : 0;
    final highest = points.isEmpty
        ? 0
        : points
            .map((e) => e.value)
            .reduce((a, b) => math.max(a, b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ChartInfoChip(
              title: 'Latest',
              value:
                  '${latest.toStringAsFixed(latest % 1 == 0 ? 0 : 1)}$ySuffix',
              dotColor: lineColor,
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _ChartInfoChip(
              title: 'Peak',
              value:
                  '${highest.toStringAsFixed(highest % 1 == 0 ? 0 : 1)}$ySuffix',
              dotColor: pointColor,
              isDark: isDark,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 950),
            tween: Tween(begin: 0, end: 1),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) {
              return SizedBox(
                width: minWidth,
                height: 220,
                child: CustomPaint(
                  painter: _LineChartPainter(
                    points: points,
                    progress: progress,
                    lineColor: lineColor,
                    fillColor: fillColor,
                    pointColor: pointColor,
                    labelColor: textSecondary,
                    axisColor: textSecondary.withOpacity(0.14),
                    valueColor: textPrimary,
                    ySuffix: ySuffix,
                    maxY: maxValue,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChartInfoChip extends StatelessWidget {
  final String title;
  final String value;
  final Color dotColor;
  final bool isDark;

  const _ChartInfoChip({
    required this.title,
    required this.value,
    required this.dotColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Colors.white.withOpacity(0.05)
        : const Color(0xFFFAF6F7);
    final textPrimary = isDark ? Colors.white : const Color(0xFF2A0F10);
    final textSecondary =
        isDark ? Colors.white70 : const Color(0xFF7D8190);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$title: ',
            style: TextStyle(
              color: textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double progress;
  final Color lineColor;
  final Color fillColor;
  final Color pointColor;
  final Color labelColor;
  final Color axisColor;
  final Color valueColor;
  final String ySuffix;
  final double maxY;

  _LineChartPainter({
    required this.points,
    required this.progress,
    required this.lineColor,
    required this.fillColor,
    required this.pointColor,
    required this.labelColor,
    required this.axisColor,
    required this.valueColor,
    required this.ySuffix,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const double leftPad = 8;
    const double rightPad = 10;
    const double topPad = 16;
    const double bottomPad = 34;

    final double chartWidth = size.width - leftPad - rightPad;
    final double chartHeight = size.height - topPad - bottomPad;

    final gridPaint = Paint()
      ..color = axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = topPad + (chartHeight * i / 3);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );
    }

    final double stepX =
        points.length == 1 ? 0 : chartWidth / (points.length - 1);

    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = leftPad + (i * stepX);
      final safeMax = maxY <= 0 ? 1 : maxY;
      final y =
          topPad + chartHeight - ((points[i].value / safeMax) * chartHeight);
      offsets.add(Offset(x, y));
    }

    final int lastFullSegment =
        ((points.length - 1) * progress).floor().clamp(0, points.length - 1);
    final double segmentProgress =
        (((points.length - 1) * progress) - lastFullSegment).clamp(0.0, 1.0);

    final visiblePath = Path();
    visiblePath.moveTo(offsets.first.dx, offsets.first.dy);

    for (int i = 1; i <= lastFullSegment && i < offsets.length; i++) {
      visiblePath.lineTo(offsets[i].dx, offsets[i].dy);
    }

    if (lastFullSegment < offsets.length - 1) {
      final current = offsets[lastFullSegment];
      final next = offsets[lastFullSegment + 1];
      final partial = Offset.lerp(current, next, segmentProgress)!;
      visiblePath.lineTo(partial.dx, partial.dy);
    }

    final fillPath = Path.from(visiblePath);
    fillPath.lineTo(
      offsets[lastFullSegment < offsets.length
          ? lastFullSegment
          : offsets.length - 1]
          .dx,
      size.height - bottomPad,
    );
    fillPath.lineTo(offsets.first.dx, size.height - bottomPad);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          fillColor,
          fillColor.withOpacity(0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(
        Rect.fromLTWH(leftPad, topPad, chartWidth, chartHeight),
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(visiblePath, linePaint);

    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    final pointBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final visiblePointCount =
        math.max(1, (points.length * progress).ceil()).clamp(1, points.length);

    for (int i = 0; i < visiblePointCount; i++) {
      canvas.drawCircle(offsets[i], 4.5, pointBorderPaint);
      canvas.drawCircle(offsets[i], 3, pointPaint);
    }

    for (int i = 0; i < points.length; i++) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(
            color: labelColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 48);

      labelPainter.paint(
        canvas,
        Offset(offsets[i].dx - (labelPainter.width / 2), size.height - 20),
      );
    }

    final topValuePainter = TextPainter(
      text: TextSpan(
        text: '${maxY.toStringAsFixed(maxY % 1 == 0 ? 0 : 1)}$ySuffix',
        style: TextStyle(
          color: valueColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    topValuePainter.paint(canvas, const Offset(8, 0));
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.progress != progress ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}