import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:technohere/config/app_config.dart';
import 'package:technohere/theme/app_colors.dart';

import 'login.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _otpSent = false;
  bool _phoneVerified = false;
  bool _keepLoggedIn = false;

  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _submitting = false;

  bool _showPassword = false;
  bool _showConfirmPassword = false;

  String _verificationToken = '';
  String _verifiedPhone = '';
  Timer? _resendTimer;
  int _resendSeconds = 0;

  InlineNotice? _notice;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _phoneVerified && !_submitting;

  String get _sendOtpButtonText {
    if (_sendingOtp) return '';
    if (_resendSeconds > 0) {
      final m = _resendSeconds ~/ 60;
      final s = _resendSeconds % 60;
      if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
      return '${_resendSeconds}s';
    }
    return _otpSent ? 'Resend' : 'OTP';
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

  String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  String _normalizeOtp(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    return cleaned.length > 6 ? cleaned.substring(0, 6) : cleaned;
  }

  bool _validPhone(String value) => _normalizePhone(value).length == 10;

  void _resetVerificationState({bool hideOtp = false}) {
    _phoneVerified = false;
    _verificationToken = '';
    _verifiedPhone = '';
    _passwordController.clear();
    _confirmPasswordController.clear();

    if (hideOtp) {
      _otpSent = false;
      _otpController.clear();
      _resendTimer?.cancel();
      _resendSeconds = 0;
    }
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = seconds;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() {
          _resendSeconds = 0;
        });
      } else {
        setState(() {
          _resendSeconds--;
        });
      }
    });
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

  void _openLoginPage({
    bool replace = false,
    String? phone,
    String? password,
  }) {
    final route = MaterialPageRoute(
      builder: (_) => LoginPage(
        initialIdentifier: (phone ?? '').trim(),
        initialPassword: password ?? '',
      ),
    );

    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    final phone = _normalizePhone(_phoneController.text);

    if (phone.isEmpty) {
      _setNotice('Please enter your phone number first.', NoticeType.warning);
      return;
    }

    if (!_validPhone(phone)) {
      _setNotice(
        'Please enter a valid 10 digit phone number.',
        NoticeType.warning,
      );
      return;
    }

    if (_resendSeconds > 0) return;

    setState(() {
      _sendingOtp = true;
    });

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}/api/auth/send-phone-otp',
        {'phone_number': phone},
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode == 422) {
        _setNotice(
          _extractMessage(data, fallback: 'Please check the phone number.'),
          NoticeType.warning,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        if (data['wait_seconds'] is int) {
          _startResendCountdown(data['wait_seconds'] as int);
        } else if (data['cooldown_seconds'] is int) {
          _startResendCountdown(data['cooldown_seconds'] as int);
        }

        _setNotice(
          _extractMessage(data, fallback: 'Failed to send OTP.'),
          NoticeType.error,
        );
        return;
      }

      setState(() {
        _otpSent = true;
        _phoneVerified = false;
        _verificationToken =
            (data['verification_token'] ??
                    data['token'] ??
                    data['session_id'] ??
                    '')
                .toString();
      });

      if (data['is_final_attempt'] == true) {
        _startResendCountdown(3600);
      } else if (data['cooldown_seconds'] is int) {
        _startResendCountdown(data['cooldown_seconds'] as int);
      }

      _setNotice(
        _extractMessage(data, fallback: 'OTP sent successfully.'),
        NoticeType.success,
      );
    } on TimeoutException {
      _setNotice('Request timed out while sending OTP.', NoticeType.error);
    } catch (_) {
      _setNotice('Network error while sending OTP.', NoticeType.error);
    } finally {
      if (mounted) {
        setState(() {
          _sendingOtp = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    final phone = _normalizePhone(_phoneController.text);
    final otp = _normalizeOtp(_otpController.text);

    if (!_otpSent) {
      _setNotice('Please send OTP first.', NoticeType.warning);
      return;
    }

    if (!_validPhone(phone)) {
      _setNotice('Please enter a valid phone number.', NoticeType.warning);
      return;
    }

    if (otp.length != 6) {
      _setNotice('Please enter a valid 6 digit OTP.', NoticeType.warning);
      return;
    }

    setState(() {
      _verifyingOtp = true;
    });

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}/api/auth/verify-phone-otp',
        {
          'phone_number': phone,
          'otp': otp,
          'verification_token': _verificationToken,
        },
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode == 422) {
        _setNotice(
          _extractMessage(data, fallback: 'Please check the OTP.'),
          NoticeType.warning,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        _setNotice(
          _extractMessage(data, fallback: 'OTP verification failed.'),
          NoticeType.error,
        );
        return;
      }

      setState(() {
        _phoneVerified = true;
        _verifiedPhone = phone;
        _verificationToken =
            (data['verification_token'] ?? _verificationToken).toString();
      });

      _setNotice(
        _extractMessage(data, fallback: 'Phone verified successfully.'),
        NoticeType.success,
      );
    } on TimeoutException {
      _setNotice('Request timed out while verifying OTP.', NoticeType.error);
    } catch (_) {
      _setNotice('Network error while verifying OTP.', NoticeType.error);
    } finally {
      if (mounted) {
        setState(() {
          _verifyingOtp = false;
        });
      }
    }
  }

  Future<void> _submitRegister() async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    if (!_formKey.currentState!.validate()) return;

    if (!_phoneVerified) {
      _setNotice('Please verify your phone number first.', NoticeType.warning);
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final phone = _normalizePhone(_phoneController.text);
      final password = _passwordController.text;

      final result = await _postJson(
        '${AppConfig.baseUrl}/api/auth/student-register',
        {
          'name': _nameController.text.trim(),
          'phone_number': phone,
          'password': password,
          'password_confirmation': _confirmPasswordController.text,
        },
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode == 422) {
        _setNotice(
          _extractMessage(
            data,
            fallback: 'Please fix the highlighted fields.',
          ),
          NoticeType.warning,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        _setNotice(
          _extractMessage(data, fallback: 'Registration failed.'),
          NoticeType.error,
        );
        return;
      }

      _setNotice(
        _extractMessage(data, fallback: 'Registered successfully!'),
        NoticeType.success,
      );

      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      _openLoginPage(
        replace: true,
        phone: phone,
        password: password,
      );
    } on TimeoutException {
      _setNotice('Request timed out while registering.', NoticeType.error);
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
                      _buildHeroHeader(context, textSecondary),
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
                                    'Create your account',
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Register with your phone number to continue.',
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
                                  _label('Full Name', textPrimary),
                                  const SizedBox(height: 7),
                                  _inputField(
                                    context: context,
                                    controller: _nameController,
                                    hint: 'Enter your full name',
                                    prefixIcon: FontAwesomeIcons.user,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().length < 2) {
                                        return 'Please enter your full name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  _label('Phone Number', textPrimary),
                                  const SizedBox(height: 7),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _inputField(
                                          context: context,
                                          controller: _phoneController,
                                          hint: '9000000000',
                                          prefixIcon: FontAwesomeIcons.phone,
                                          enabled: !_phoneVerified,
                                          keyboardType: TextInputType.phone,
                                          maxLength: 10,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(10),
                                          ],
                                          onChanged: (value) {
                                            _clearNotice();
                                            if (_phoneVerified &&
                                                _normalizePhone(value) !=
                                                    _verifiedPhone) {
                                              setState(() {
                                                _resetVerificationState(
                                                  hideOtp: false,
                                                );
                                              });
                                              _setNotice(
                                                'Phone number changed. Please verify again.',
                                                NoticeType.warning,
                                              );
                                            }
                                          },
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'Please enter phone number';
                                            }
                                            if (!_validPhone(value)) {
                                              return 'Enter valid 10 digit number';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 92,
                                        child: ElevatedButton(
                                          onPressed: (_sendingOtp ||
                                                  _phoneVerified ||
                                                  _resendSeconds > 0)
                                              ? null
                                              : _sendOtp,
                                          child: _sendingOtp
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : Text(_sendOtpButtonText),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: FaIcon(
                                          _phoneVerified
                                              ? FontAwesomeIcons.circleCheck
                                              : FontAwesomeIcons.message,
                                          size: 12,
                                          color: _phoneVerified
                                              ? AppColors.success
                                              : textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _phoneVerified
                                              ? 'Phone number verified successfully.'
                                              : 'Click OTP to receive a verification code on your phone.',
                                          style: TextStyle(
                                            color: _phoneVerified
                                                ? AppColors.success
                                                : textSecondary,
                                            fontSize: 12.2,
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_otpSent) ...[
                                    const SizedBox(height: 14),
                                    _label('Enter OTP', textPrimary),
                                    const SizedBox(height: 7),
                                    _inputField(
                                      context: context,
                                      controller: _otpController,
                                      hint: 'Enter 6 digit OTP',
                                      prefixIcon: FontAwesomeIcons.key,
                                      enabled:
                                          !_phoneVerified && !_verifyingOtp,
                                      keyboardType: TextInputType.number,
                                      maxLength: 6,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6),
                                      ],
                                      onChanged: (value) {
                                        final normalized = _normalizeOtp(value);
                                        if (normalized != value) {
                                          _otpController.value =
                                              TextEditingValue(
                                            text: normalized,
                                            selection:
                                                TextSelection.collapsed(
                                              offset: normalized.length,
                                            ),
                                          );
                                        }
                                        if (normalized.length == 6 &&
                                            _otpSent &&
                                            !_phoneVerified &&
                                            !_verifyingOtp) {
                                          _verifyOtp();
                                        }
                                      },
                                      validator: (value) {
                                        if (_otpSent && !_phoneVerified) {
                                          if (value == null ||
                                              value.trim().length != 6) {
                                            return 'Please enter 6 digit OTP';
                                          }
                                        }
                                        return null;
                                      },
                                      suffix: _verifyingOtp
                                          ? const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  _label('Password', textPrimary),
                                  const SizedBox(height: 7),
                                  _inputField(
                                    context: context,
                                    controller: _passwordController,
                                    hint: 'Minimum 8+ characters',
                                    prefixIcon: FontAwesomeIcons.lock,
                                    enabled: _phoneVerified,
                                    obscureText: !_showPassword,
                                    suffix: IconButton(
                                      onPressed: _phoneVerified
                                          ? () {
                                              setState(() {
                                                _showPassword =
                                                    !_showPassword;
                                              });
                                            }
                                          : null,
                                      icon: FaIcon(
                                        _showPassword
                                            ? FontAwesomeIcons.eye
                                            : FontAwesomeIcons.eyeSlash,
                                        size: 15,
                                        color: textSecondary,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (!_phoneVerified) return null;
                                      if (value == null || value.length < 8) {
                                        return 'Password must be at least 8 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  _label('Confirm Password', textPrimary),
                                  const SizedBox(height: 7),
                                  _inputField(
                                    context: context,
                                    controller: _confirmPasswordController,
                                    hint: 'Re-type password',
                                    prefixIcon: FontAwesomeIcons.lock,
                                    enabled: _phoneVerified,
                                    obscureText: !_showConfirmPassword,
                                    suffix: IconButton(
                                      onPressed: _phoneVerified
                                          ? () {
                                              setState(() {
                                                _showConfirmPassword =
                                                    !_showConfirmPassword;
                                              });
                                            }
                                          : null,
                                      icon: FaIcon(
                                        _showConfirmPassword
                                            ? FontAwesomeIcons.eye
                                            : FontAwesomeIcons.eyeSlash,
                                        size: 15,
                                        color: textSecondary,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (!_phoneVerified) return null;
                                      if (value == null || value.isEmpty) {
                                        return 'Please confirm password';
                                      }
                                      if (value != _passwordController.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
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
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed:
                                        _canSubmit ? _submitRegister : null,
                                    icon: _submitting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : FaIcon(
                                            _phoneVerified
                                                ? FontAwesomeIcons.userPlus
                                                : FontAwesomeIcons
                                                    .mobileScreenButton,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                    label: Text(
                                      _submitting
                                          ? 'Creating account...'
                                          : _phoneVerified
                                              ? 'Create Account'
                                              : 'Verify phone to continue',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(44),
                                      maximumSize:
                                          const Size(double.infinity, 44),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
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
                                          'Already have account?',
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.8,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            _openLoginPage(
                                              phone: _normalizePhone(
                                                _phoneController.text,
                                              ),
                                              password:
                                                  _passwordController.text,
                                            );
                                          },
                                          child: Text(
                                            'Login',
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

  Widget _buildHeroHeader(BuildContext context, Color textSecondary) {
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
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    final textSecondary = AppColors.textSecondary(context);

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontWeight: FontWeight.w700,
        fontSize: 14,
        height: 1.15,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
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