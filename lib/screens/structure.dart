import 'package:flutter/material.dart';
import 'package:technohere/screens/pages/common/dashboard.dart';
import 'package:technohere/screens/pages/doubts/doubt.dart';
import 'package:technohere/screens/pages/exam/myExam.dart';
import 'package:technohere/screens/pages/common/profile.dart';
import 'package:technohere/widgets/appBottomNavbar.dart';
import 'package:technohere/widgets/appHeader.dart';

class StructurePage extends StatefulWidget {
  final String? userName;

  const StructurePage({
    super.key,
    this.userName,
  });

  @override
  State<StructurePage> createState() => _StructurePageState();
}

class _StructurePageState extends State<StructurePage> {
  int _currentIndex = 0;

  String get _safeUserName {
    final name = widget.userName?.trim();
    if (name == null || name.isEmpty) return 'User';
    return name;
  }

  void _handleBottomNavTap(int index) {
    if (_currentIndex == index) return;

    setState(() {
      _currentIndex = index;
    });
  }

  Widget _buildCurrentModule(bool isDark) {
    switch (_currentIndex) {
      case 0:
        return DashboardModule(
          userName: _safeUserName,
          isDark: isDark,
        );

      case 1:
        return MyExamPage(
          isDark: isDark,
        );

      case 2:
        return AppModulePlaceholder(
          title: 'Results',
          subtitle: 'Your results module will appear here.',
          icon: Icons.bar_chart_rounded,
          isDark: isDark,
        );

      case 3:
        return DoubtPage(
          isDark: isDark,
        );

      case 4:
        return ProfilePage(
          isDark: isDark,
        );

      default:
        return DashboardModule(
          userName: _safeUserName,
          isDark: isDark,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121214) : const Color(0xFFF8F9FC),
      appBar: const AppHeader(),
      body: _buildCurrentModule(isDark),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: _handleBottomNavTap,
      ),
    );
  }
}

class AppModulePlaceholder extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDark;

  const AppModulePlaceholder({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1F23) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFF9E363A).withOpacity(0.12),
                  child: Icon(
                    icon,
                    size: 34,
                    color: const Color(0xFF9E363A),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF2A0F10),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: isDark ? Colors.white70 : const Color(0xFF5F6368),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9E363A).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Module Ready',
                    style: TextStyle(
                      color: Color(0xFF9E363A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}