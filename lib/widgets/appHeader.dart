import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:technohere/config/appConfig.dart';
import 'package:technohere/screens/auth/login.dart';

class AppHeader extends StatefulWidget implements PreferredSizeWidget {
  const AppHeader({super.key});

  @override
  State<AppHeader> createState() => _AppHeaderState();

  @override
  Size get preferredSize => const Size.fromHeight(64);
}

class _AppHeaderState extends State<AppHeader> {
  bool _isLoggingOut = false;

  Future<Map<String, dynamic>> _postJsonWithToken(
    String endpoint,
    String token,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient();

    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
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

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('token') ?? '').trim();

    try {
      if (token.isNotEmpty) {
        await _postJsonWithToken(
          '${AppConfig.baseUrl}/api/auth/logout',
          token,
          {},
        );
      }
    } on TimeoutException {
      // ignore and continue local logout
    } catch (_) {
      // ignore and continue local logout
    }

    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('keep_logged_in');
    await prefs.remove('user_name');
    await prefs.remove('user');
    await prefs.remove('student');
    await prefs.remove('profile');

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _logout();
    }
  }

  Widget _buildLogo() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: ClipOval(
          child: Image.asset(
            'assets/icons/app_icon.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.school_rounded,
              color: Color(0xFF9E363A),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isLoggingOut ? null : () => _confirmLogout(context),
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            Icons.logout_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppBar(
          toolbarHeight: 64,
          backgroundColor: const Color(0xFF9E363A),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          titleSpacing: 0,
          title: const SizedBox.shrink(),
          leadingWidth: 64,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildLogo(),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildLogoutButton(context),
              ),
            ),
          ],
        ),
        if (_isLoggingOut)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.18),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}