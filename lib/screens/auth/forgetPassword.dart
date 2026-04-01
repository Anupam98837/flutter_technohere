import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:technohere/config/appConfig.dart';
import 'package:technohere/theme/app_colors.dart';

enum ForgotPasswordStep {
  identifier,
  otp,
  reset,
  success,
}

enum ForgotNoticeType {
  success,
  error,
  warning,
}

class ForgotInlineNotice {
  final String message;
  final ForgotNoticeType type;

  const ForgotInlineNotice({
    required this.message,
    required this.type,
  });
}

class ForgotPasswordPage extends StatefulWidget {
  final VoidCallback? onBackToLogin;
  final String? initialIdentifier;

  const ForgotPasswordPage({
    super.key,
    this.onBackToLogin,
    this.initialIdentifier,
  });

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const String _sendOtpApi = '/api/auth/forgot-password/send-otp';
  static const String _resetApi = '/api/auth/forgot-password/reset';

  final GlobalKey<FormState> _identifierFormKey = GlobalKey<FormState>();

  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _otpFocusNodes;

  ForgotPasswordStep _step = ForgotPasswordStep.identifier;
  ForgotInlineNotice? _notice;

  bool _sendingOtp = false;
  bool _resendingOtp = false;
  bool _resettingPassword = false;

  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  String _resolvedTokenKey = '';
  String _verifiedOtp = '';

  int _resendSeconds = 0;
  bool _resendLockedTillTomorrow = false;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _identifierController.text = widget.initialIdentifier?.trim() ?? '';
    _otpControllers = List.generate(6, (_) => TextEditingController());
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _identifierController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();

    for (final controller in _otpControllers) {
      controller.dispose();
    }

    for (final node in _otpFocusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  void _setNotice(String message, ForgotNoticeType type) {
    setState(() {
      _notice = ForgotInlineNotice(message: message, type: type);
    });
  }

  void _clearNotice() {
    if (_notice != null) {
      setState(() {
        _notice = null;
      });
    }
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _extractMessage(
    Map<String, dynamic> data, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (data['message'] is String &&
        (data['message'] as String).trim().isNotEmpty) {
      return (data['message'] as String).trim();
    }

    if (data['error'] is String &&
        (data['error'] as String).trim().isNotEmpty) {
      return (data['error'] as String).trim();
    }

    if (data['errors'] is Map) {
      final map = data['errors'] as Map;
      for (final value in map.values) {
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
    }

    return fallback;
  }

  bool _looksLikeEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  }

  bool _looksLikePhone(String value) {
    return RegExp(r'^\+?[\d\s\-]{7,15}$').hasMatch(value.trim());
  }

  String get _otpCode =>
      _otpControllers.map((controller) => controller.text.trim()).join();

  String _titleForStep() {
    switch (_step) {
      case ForgotPasswordStep.identifier:
        return 'Forgot your password?';
      case ForgotPasswordStep.otp:
        return 'Enter your OTP';
      case ForgotPasswordStep.reset:
        return 'Set a new password';
      case ForgotPasswordStep.success:
        return 'All done!';
    }
  }

  String _subtitleForStep() {
    switch (_step) {
      case ForgotPasswordStep.identifier:
        return 'Enter your email or mobile number and we\'ll send you an OTP.';
      case ForgotPasswordStep.otp:
        return 'OTP sent to the mobile and email linked to your account.';
      case ForgotPasswordStep.reset:
        return 'Almost there — choose a strong password.';
      case ForgotPasswordStep.success:
        return 'Your password has been reset successfully.';
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

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();

    setState(() {
      _resendLockedTillTomorrow = false;
      _resendSeconds = seconds;
    });

    if (seconds <= 0) return;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() {
          _resendSeconds = 0;
        });
      } else {
        setState(() {
          _resendSeconds -= 1;
        });
      }
    });
  }

  void _lockResendTillTomorrow() {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = 0;
      _resendLockedTillTomorrow = true;
    });
  }

  String _formatCountdown(int seconds) {
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      final remaining = seconds % 60;
      return '(${minutes}m ${remaining.toString().padLeft(2, '0')}s)';
    }
    return '(${seconds}s)';
  }

  void _clearOtpBoxes() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
  }

  void _goToStep(ForgotPasswordStep step) {
    _clearNotice();

    setState(() {
      _step = step;
    });

    if (step == ForgotPasswordStep.identifier) {
      _resolvedTokenKey = '';
      _verifiedOtp = '';
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _clearOtpBoxes();
      _resendTimer?.cancel();
      _resendSeconds = 0;
      _resendLockedTillTomorrow = false;
    }

    if (step == ForgotPasswordStep.otp) {
      _clearOtpBoxes();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) {
          _otpFocusNodes.first.requestFocus();
        }
      });
    }

    if (step == ForgotPasswordStep.reset) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      });
    }
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    final identifier = _identifierController.text.trim();

    if (identifier.isEmpty) {
      _setNotice(
        'Please enter your email or mobile number.',
        ForgotNoticeType.error,
      );
      return;
    }

    if (!_looksLikeEmail(identifier) && !_looksLikePhone(identifier)) {
      _setNotice(
        'Please enter a valid email address or mobile number.',
        ForgotNoticeType.error,
      );
      return;
    }

    setState(() {
      if (isResend) {
        _resendingOtp = true;
      } else {
        _sendingOtp = true;
      }
    });

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}$_sendOtpApi',
        {
          'identifier': identifier,
        },
      );

      final statusCode = result['statusCode'] as int;
      final data = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        final message = _extractMessage(
          data,
          fallback: 'Failed to send OTP. Please try again.',
        );

        if (statusCode == 429) {
          final waitSeconds = _asInt(data['wait_seconds']);
          if (waitSeconds != null && waitSeconds > 0) {
            _startResendCountdown(waitSeconds);
          }
          _setNotice(message, ForgotNoticeType.warning);
        } else {
          _setNotice(message, ForgotNoticeType.error);
        }
        return;
      }

      final nested = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : <String, dynamic>{};

      _resolvedTokenKey =
          (nested['token_key'] ?? nested['email'] ?? identifier)
              .toString()
              .trim();

      final cooldownSeconds =
          _asInt(data['cooldown_seconds'] ?? nested['cooldown_seconds']) ?? 120;

      final isFinalAttempt =
          (data['is_final_attempt'] == true ||
              nested['is_final_attempt'] == true);

      if (_step != ForgotPasswordStep.otp) {
        _goToStep(ForgotPasswordStep.otp);
      }

      if (isFinalAttempt) {
        _lockResendTillTomorrow();
      } else {
        _startResendCountdown(cooldownSeconds);
      }

      _setNotice(
        isResend
            ? 'A new OTP has been sent to your mobile and email.'
            : 'OTP sent successfully.',
        ForgotNoticeType.success,
      );
    } on TimeoutException {
      _setNotice(
        'Request timed out while sending OTP.',
        ForgotNoticeType.error,
      );
    } catch (_) {
      _setNotice(
        'Network error. Please try again.',
        ForgotNoticeType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingOtp = false;
          _resendingOtp = false;
        });
      }
    }
  }

  void _verifyOtpAndContinue() {
    FocusScope.of(context).unfocus();
    _clearNotice();

    final otp = _otpCode;

    if (otp.length != 6) {
      _setNotice(
        'Please enter all 6 digits of your OTP.',
        ForgotNoticeType.error,
      );
      final index = _otpControllers.indexWhere((c) => c.text.trim().isEmpty);
      if (index >= 0 && index < _otpFocusNodes.length) {
        _otpFocusNodes[index].requestFocus();
      }
      return;
    }

    _verifiedOtp = otp;
    _goToStep(ForgotPasswordStep.reset);
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    final password = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.isEmpty || password.length < 8) {
      _setNotice(
        'Password must be at least 8 characters.',
        ForgotNoticeType.error,
      );
      return;
    }

    if (password != confirmPassword) {
      _setNotice(
        'Passwords do not match.',
        ForgotNoticeType.error,
      );
      return;
    }

    setState(() {
      _resettingPassword = true;
    });

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}$_resetApi',
        {
          'token_key': _resolvedTokenKey,
          'otp': _verifiedOtp,
          'password': password,
          'password_confirmation': confirmPassword,
        },
      );

      final statusCode = result['statusCode'] as int;
      final data = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        final message = _extractMessage(
          data,
          fallback: 'Unable to reset password.',
        );

        final lower = message.toLowerCase();
        final isOtpError = lower.contains('otp') ||
            lower.contains('invalid') ||
            lower.contains('expired');

        if (isOtpError) {
          _setNotice(message, ForgotNoticeType.error);
          _goToStep(ForgotPasswordStep.otp);
          return;
        }

        _setNotice(message, ForgotNoticeType.error);
        return;
      }

      _goToStep(ForgotPasswordStep.success);
      _setNotice(
        'Password updated successfully.',
        ForgotNoticeType.success,
      );
    } on TimeoutException {
      _setNotice(
        'Request timed out while resetting password.',
        ForgotNoticeType.error,
      );
    } catch (_) {
      _setNotice(
        'Network error. Please try again.',
        ForgotNoticeType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _resettingPassword = false;
        });
      }
    }
  }

  void _handleBackToLogin() {
    if (widget.onBackToLogin != null) {
      widget.onBackToLogin!();
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Color _noticeBg(BuildContext context, ForgotNoticeType type) {
    final dark = AppColors.isDark(context);

    switch (type) {
      case ForgotNoticeType.success:
        return dark ? const Color(0xFF0E2B1A) : const Color(0xFFEAF8EF);
      case ForgotNoticeType.error:
        return dark ? const Color(0xFF311213) : const Color(0xFFFDECEC);
      case ForgotNoticeType.warning:
        return dark ? const Color(0xFF33250E) : const Color(0xFFFFF7E8);
    }
  }

  Color _noticeBorder(ForgotNoticeType type) {
    switch (type) {
      case ForgotNoticeType.success:
        return AppColors.success;
      case ForgotNoticeType.error:
        return AppColors.error;
      case ForgotNoticeType.warning:
        return AppColors.warning;
    }
  }

  Color _noticeAccent(ForgotNoticeType type) {
    switch (type) {
      case ForgotNoticeType.success:
        return AppColors.success;
      case ForgotNoticeType.error:
        return AppColors.error;
      case ForgotNoticeType.warning:
        return AppColors.warning;
    }
  }

  IconData _noticeIcon(ForgotNoticeType type) {
    switch (type) {
      case ForgotNoticeType.success:
        return FontAwesomeIcons.circleCheck;
      case ForgotNoticeType.error:
        return FontAwesomeIcons.circleExclamation;
      case ForgotNoticeType.warning:
        return FontAwesomeIcons.triangleExclamation;
    }
  }

  int _stepIndex(ForgotPasswordStep step) {
    switch (step) {
      case ForgotPasswordStep.identifier:
        return 0;
      case ForgotPasswordStep.otp:
        return 1;
      case ForgotPasswordStep.reset:
        return 2;
      case ForgotPasswordStep.success:
        return 3;
    }
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(44),
      maximumSize: const Size(double.infinity, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      elevation: 0,
    );
  }

  ButtonStyle _secondaryButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary(context),
      side: BorderSide(color: AppColors.borderStrong(context)),
      minimumSize: const Size.fromHeight(44),
      maximumSize: const Size(double.infinity, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final border = AppColors.borderStrong(context);
    final current = _stepIndex(_step);

    return Row(
      children: List.generate(4, (index) {
        final done = index < current;
        final active = index == current;

        Color color;
        if (done) {
          color = AppColors.primary;
        } else if (active) {
          color = AppColors.primary.withOpacity(.45);
        } else {
          color = border;
        }

        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final surface = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final border = AppColors.borderStrong(context);
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
                  const Expanded(child: SizedBox()),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildStepIndicator(context),
                                const SizedBox(height: 16),
                                Text(
                                  _titleForStep(),
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _subtitleForStep(),
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
                                            color:
                                                _noticeAccent(_notice!.type),
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
                                if (_step == ForgotPasswordStep.identifier)
                                  _buildIdentifierStep(
                                    context,
                                    textPrimary,
                                    textSecondary,
                                  ),
                                if (_step == ForgotPasswordStep.otp)
                                  _buildOtpStep(
                                    context,
                                    textPrimary,
                                    textSecondary,
                                  ),
                                if (_step == ForgotPasswordStep.reset)
                                  _buildResetStep(
                                    context,
                                    textPrimary,
                                    textSecondary,
                                  ),
                                if (_step == ForgotPasswordStep.success)
                                  _buildSuccessStep(
                                    context,
                                    textPrimary,
                                    textSecondary,
                                  ),
                              ],
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

  Widget _buildIdentifierStep(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Form(
      key: _identifierFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface2(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enter your registered email address or mobile number. A 6-digit OTP valid for 10 minutes will be sent.',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _label('Email or Mobile Number', textPrimary),
          const SizedBox(height: 7),
          _inputField(
            context: context,
            controller: _identifierController,
            hint: 'you@example.com or 9000000000',
            prefixIcon: FontAwesomeIcons.userLarge,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _sendOtp(),
            onChanged: (_) => _clearNotice(),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) {
                return 'Please enter email or mobile number';
              }
              if (!_looksLikeEmail(text) && !_looksLikePhone(text)) {
                return 'Enter a valid email or mobile number';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _sendingOtp
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    if (_identifierFormKey.currentState?.validate() != true) {
                      return;
                    }
                    _sendOtp();
                  },
            icon: _sendingOtp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const FaIcon(
                    FontAwesomeIcons.paperPlane,
                    size: 14,
                    color: Colors.white,
                  ),
            label: Text(_sendingOtp ? 'Sending OTP...' : 'Send OTP'),
            style: _primaryButtonStyle(),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _handleBackToLogin,
            icon: const FaIcon(
              FontAwesomeIcons.arrowLeft,
              size: 13,
            ),
            label: const Text('Back to Login'),
            style: _secondaryButtonStyle(context),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface2(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderSoft(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'An OTP has been sent to the mobile number and email linked to your account. Enter all 6 digits below.',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(6, (index) {
              final filled = _otpControllers[index].text.trim().isNotEmpty;

              return SizedBox(
                width: 44,
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surface(context),
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: filled
                            ? AppColors.primary
                            : AppColors.borderStrong(context),
                        width: filled ? 1.4 : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    final clean = value.replaceAll(RegExp(r'\D'), '');
                    if (clean != value) {
                      _otpControllers[index].text = clean;
                      _otpControllers[index].selection =
                          TextSelection.collapsed(offset: clean.length);
                    }

                    setState(() {});

                    if (clean.isNotEmpty && index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    }

                    if (_otpCode.length == 6) {
                      FocusScope.of(context).unfocus();
                    }
                  },
                  onTap: () {
                    _otpControllers[index].selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _otpControllers[index].text.length,
                    );
                  },
                  onSubmitted: (_) => _verifyOtpAndContinue(),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                'Didn’t receive it?',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: (_resendSeconds > 0 ||
                        _resendLockedTillTomorrow ||
                        _resendingOtp)
                    ? null
                    : () => _sendOtp(isResend: true),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _resendLockedTillTomorrow
                      ? 'Try again tomorrow'
                      : _resendingOtp
                          ? 'Resending...'
                          : 'Resend OTP',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
                  ),
                ),
              ),
              if (_resendSeconds > 0)
                Text(
                  _formatCountdown(_resendSeconds),
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _verifyOtpAndContinue,
          icon: const FaIcon(
            FontAwesomeIcons.shieldHalved,
            size: 14,
            color: Colors.white,
          ),
          label: const Text('Verify OTP'),
          style: _primaryButtonStyle(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _goToStep(ForgotPasswordStep.identifier),
          icon: const FaIcon(
            FontAwesomeIcons.arrowLeft,
            size: 13,
          ),
          label: const Text('Change Email / Phone'),
          style: _secondaryButtonStyle(context),
        ),
      ],
    );
  }

  Widget _buildResetStep(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface2(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderSoft(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'OTP verified. Set your new password below.',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _label('New Password', textPrimary),
        const SizedBox(height: 7),
        _inputField(
          context: context,
          controller: _newPasswordController,
          hint: 'Minimum 8 characters',
          prefixIcon: FontAwesomeIcons.lock,
          obscureText: !_showNewPassword,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearNotice(),
          suffix: IconButton(
            onPressed: () {
              setState(() {
                _showNewPassword = !_showNewPassword;
              });
            },
            icon: FaIcon(
              _showNewPassword
                  ? FontAwesomeIcons.eye
                  : FontAwesomeIcons.eyeSlash,
              size: 15,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _label('Confirm New Password', textPrimary),
        const SizedBox(height: 7),
        _inputField(
          context: context,
          controller: _confirmPasswordController,
          hint: 'Repeat your new password',
          prefixIcon: FontAwesomeIcons.key,
          obscureText: !_showConfirmPassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _resetPassword(),
          onChanged: (_) => _clearNotice(),
          suffix: IconButton(
            onPressed: () {
              setState(() {
                _showConfirmPassword = !_showConfirmPassword;
              });
            },
            icon: FaIcon(
              _showConfirmPassword
                  ? FontAwesomeIcons.eye
                  : FontAwesomeIcons.eyeSlash,
              size: 15,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _resettingPassword ? null : _resetPassword,
          icon: _resettingPassword
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const FaIcon(
                  FontAwesomeIcons.key,
                  size: 14,
                  color: Colors.white,
                ),
          label: Text(
            _resettingPassword ? 'Resetting Password...' : 'Reset Password',
          ),
          style: _primaryButtonStyle(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _goToStep(ForgotPasswordStep.otp),
          icon: const FaIcon(
            FontAwesomeIcons.arrowLeft,
            size: 13,
          ),
          label: const Text('Back'),
          style: _secondaryButtonStyle(context),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(.12),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: FaIcon(
              FontAwesomeIcons.circleCheck,
              size: 30,
              color: AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Password updated!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your password has been successfully reset.\nYou can now log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: _handleBackToLogin,
          icon: const FaIcon(
            FontAwesomeIcons.rightToBracket,
            size: 14,
            color: Colors.white,
          ),
          label: const Text('Go to Login'),
          style: _primaryButtonStyle(),
        ),
      ],
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
                'assets/icons/logo.png',
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
}