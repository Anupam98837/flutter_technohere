import 'package:flutter/material.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = Color(0xFF9E363A);
    const inactiveLightColor = Color(0xFF7A7A7A);
    const inactiveDarkColor = Color(0xFF9A9EAD);

    final inactiveColor = isDark ? inactiveDarkColor : inactiveLightColor;
    final backgroundColor = isDark ? const Color(0xFF1C1C21) : Colors.white;
    final elevationColor = isDark ? Colors.black12 : Colors.white12;

    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: backgroundColor,
        indicatorColor: Colors.transparent,
        elevation: 4,
        shadowColor: elevationColor,
        height: 72,
        iconTheme: MaterialStateProperty.resolveWith<IconThemeData>((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(
              color: primaryColor,
              size: 26,
            );
          }
          return IconThemeData(
            color: inactiveColor,
            size: 24,
          );
        }),
        labelTextStyle: MaterialStateProperty.resolveWith<TextStyle>((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            );
          }
          return TextStyle(
            color: inactiveColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        height: 72,
        backgroundColor: backgroundColor,
        indicatorColor: Colors.transparent,
        elevation: 4,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Exams',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Results',
          ),
          NavigationDestination(
            icon: Icon(Icons.live_help_outlined),
            selectedIcon: Icon(Icons.live_help_rounded),
            label: 'Doubts',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}