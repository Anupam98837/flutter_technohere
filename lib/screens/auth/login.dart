import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';
import 'package:technohere/theme/app_colors.dart';
import 'package:technohere/screens/structure.dart';
import 'register.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onOpenRegister;
  final VoidCallback? onForgotPassword;
  final String? initialIdentifier;
  final String? initialPassword;

  const LoginPage({
    super.key,
    this.onOpenRegister,
    this.onForgotPassword,
    this.initialIdentifier,
    this.initialPassword,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _keepLoggedIn = false;
  bool _submitting = false;
  bool _showPassword = false;

  InlineNotice? _notice;

  @override
  void initState() {
    super.initState();
    _identifierController.text = widget.initialIdentifier?.trim() ?? '';
    _passwordController.text = widget.initialPassword ?? '';
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setNotice(String message, NoticeType type) {
    setState(() {
      _notice = InlineNotice(message: message, type: type);
    });
  }

  void _clearNotice() {
    if (_notice != null) {
      setState(() {
        _notice = null;
      });
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient();

    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(payload)));

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

  String _extractMessage(
    Map<String, dynamic> data, {
    String fallback = 'Something went wrong.',
  }) {
    if (data['message'] is String &&
        (data['message'] as String).trim().isNotEmpty) {
      return data['message'] as String;
    }

    if (data['error'] is String &&
        (data['error'] as String).trim().isNotEmpty) {
      return data['error'] as String;
    }

    if (data['errors'] is Map) {
      final map = data['errors'] as Map;
      for (final value in map.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value != null) return value.toString();
      }
    }

    return fallback;
  }

  Future<void> _storeAuthIfNeeded({
  required String token,
  required String role,
}) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setString('token', token);
  await prefs.setString('role', role);
  await prefs.setBool('keep_logged_in', _keepLoggedIn);
}

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
    });

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}/api/auth/login',
        {
          'login': _identifierController.text.trim(),
          'password': _passwordController.text,
          'remember': _keepLoggedIn,
        },
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode == 422) {
        _setNotice(
          _extractMessage(
            data,
            fallback: 'Please check your login details.',
          ),
          NoticeType.warning,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        _setNotice(
          _extractMessage(data, fallback: 'Unable to log in.'),
          NoticeType.error,
        );
        return;
      }

      final String token =
          (data['access_token'] ?? data['token'] ?? '').toString().trim();

      final Map<String, dynamic> userMap = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : <String, dynamic>{};

      final String role =
          (userMap['role'] ?? 'student').toString().trim().toLowerCase();

      if (token.isEmpty) {
        _setNotice('No token received from server.', NoticeType.error);
        return;
      }

      await _storeAuthIfNeeded(
        token: token,
        role: role.isEmpty ? 'student' : role,
      );

      _setNotice('Login successful.', NoticeType.success);

      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StructurePage(
            // userName: (userMap['name'] ?? 'User').toString(),
          ),
        ),
      );
    } on TimeoutException {
      _setNotice('Request timed out while logging in.', NoticeType.error);
    } catch (_) {
      _setNotice('Network error. Please try again.', NoticeType.error);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Color _noticeBg(BuildContext context, NoticeType type) {
    final dark = AppColors.isDark(context);

    switch (type) {
      case NoticeType.success:
        return dark ? const Color(0xFF0E2B1A) : const Color(0xFFEAF8EF);
      case NoticeType.error:
        return dark ? const Color(0xFF311213) : const Color(0xFFFDECEC);
      case NoticeType.warning:
        return dark ? const Color(0xFF33250E) : const Color(0xFFFFF7E8);
    }
  }

  Color _noticeBorder(NoticeType type) {
    switch (type) {
      case NoticeType.success:
        return AppColors.success;
      case NoticeType.error:
        return AppColors.error;
      case NoticeType.warning:
        return AppColors.warning;
    }
  }

  Color _noticeAccent(NoticeType type) {
    switch (type) {
      case NoticeType.success:
        return AppColors.success;
      case NoticeType.error:
        return AppColors.error;
      case NoticeType.warning:
        return AppColors.warning;
    }
  }

  IconData _noticeIcon(NoticeType type) {
    switch (type) {
      case NoticeType.success:
        return FontAwesomeIcons.circleCheck;
      case NoticeType.error:
        return FontAwesomeIcons.circleExclamation;
      case NoticeType.warning:
        return FontAwesomeIcons.triangleExclamation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final surface = AppColors.surface(context);
    final surface2 = AppColors.surface2(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final border = AppColors.borderStrong(context);
    final borderSoft = AppColors.borderSoft(context);
    final ink = AppColors.ink(context);
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  Container(
                    height: 310,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary,
                          AppColors.secondary,
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.elliptical(220, 70),
                        bottomRight: Radius.elliptical(220, 70),
                      ),
                    ),
                  ),
                  Expanded(child: Container(color: bg)),
                ],
              ),
            ),
            Positioned(
              top: -70,
              right: -30,
              child: _glowOrb(
                Colors.white.withOpacity(isDark ? 0.05 : 0.09),
                170,
              ),
            ),
            Positioned(
              top: 70,
              left: -40,
              child: _glowOrb(
                AppColors.accent.withOpacity(isDark ? 0.10 : 0.14),
                140,
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildHeroHeader(context),
                      Transform.translate(
                        offset: const Offset(0, -26),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  isDark ? 0.24 : 0.09,
                                ),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Welcome back',
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Login with your email or phone number to continue.',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (_notice != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _noticeBg(context, _notice!.type),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: _noticeBorder(_notice!.type)
                                              .withOpacity(.30),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 1.5),
                                            child: FaIcon(
                                              _noticeIcon(_notice!.type),
                                              size: 14,
                                              color: _noticeAccent(
                                                _notice!.type,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _notice!.message,
                                              style: TextStyle(
                                                color: textPrimary,
                                                fontSize: 12.8,
                                                fontWeight: FontWeight.w700,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  _label('Email or Phone Number', textPrimary),
                                  const SizedBox(height: 7),
                                  _inputField(
                                    context: context,
                                    controller: _identifierController,
                                    hint: 'you@example.com or 9000000000',
                                    prefixIcon: FontAwesomeIcons.userLarge,
                                    textInputAction: TextInputAction.next,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter email or phone number';
                                      }
                                      return null;
                                    },
                                    onChanged: (_) => _clearNotice(),
                                  ),
                                  const SizedBox(height: 14),
                                  _label('Password', textPrimary),
                                  const SizedBox(height: 7),
                                  _inputField(
                                    context: context,
                                    controller: _passwordController,
                                    hint: 'Enter at least 8+ characters',
                                    prefixIcon: FontAwesomeIcons.lock,
                                    obscureText: !_showPassword,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submitLogin(),
                                    suffix: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _showPassword = !_showPassword;
                                        });
                                      },
                                      icon: FaIcon(
                                        _showPassword
                                            ? FontAwesomeIcons.eye
                                            : FontAwesomeIcons.eyeSlash,
                                        size: 15,
                                        color: textSecondary,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter password';
                                      }
                                      if (value.length < 8) {
                                        return 'Password must be at least 8 characters';
                                      }
                                      return null;
                                    },
                                    onChanged: (_) => _clearNotice(),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: surface2,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderSoft),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: _keepLoggedIn,
                                          onChanged: (value) {
                                            setState(() {
                                              _keepLoggedIn = value ?? false;
                                            });
                                          },
                                        ),
                                        Expanded(
                                          child: Text(
                                            'Keep me logged in',
                                            style: TextStyle(
                                              color: textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: widget.onForgotPassword ??
                                          () {
                                            _setNotice(
                                              'Forgot password screen coming soon.',
                                              NoticeType.warning,
                                            );
                                          },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                      ),
                                      child: const Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: _submitting ? null : _submitLogin,
                                    icon: _submitting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const FaIcon(
                                            FontAwesomeIcons.rightToBracket,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                    label: Text(
                                      _submitting ? 'Signing in...' : 'Login',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(44),
                                      maximumSize:
                                          const Size(double.infinity, 44),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 5,
                                      children: [
                                        Text(
                                          'Don’t have an account?',
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.8,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: widget.onOpenRegister ?? _openRegisterPage,
                                          child: const Text(
                                            'Register',
                                            style: TextStyle(
                                              color: AppColors.secondary,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12.8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 46),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(.72)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'TechnoHere',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'An Initiative of',
            style: TextStyle(
              color: Colors.white.withOpacity(.84),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Netaji Subhas Engineering College',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(.96),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowOrb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _inputField({
    required BuildContext context,
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    String? Function(String?)? validator,
    bool obscureText = false,
    bool enabled = true,
    TextInputType? keyboardType,
    Widget? suffix,
    ValueChanged<String>? onChanged,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    final textSecondary = AppColors.textSecondary(context);

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontWeight: FontWeight.w700,
        fontSize: 14,
        height: 1.15,
      ),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: FaIcon(
              prefixIcon,
              size: 15,
              color: textSecondary,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 42,
          maxWidth: 42,
          minHeight: 42,
          maxHeight: 42,
        ),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          maxWidth: 40,
          minHeight: 40,
          maxHeight: 40,
        ),
      ),
    );
  }

  void _openRegisterPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegisterPage(),
      ),
    );
  }
}

enum NoticeType { success, error, warning }

class InlineNotice {
  final String message;
  final NoticeType type;

  const InlineNotice({
    required this.message,
    required this.type,
  });
}