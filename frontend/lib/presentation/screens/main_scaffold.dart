import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kSurfaceContLowest,
          border: Border(top: BorderSide(color: kOutlineVariant, width: 1)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: kSurfaceContLowest,
          selectedItemColor: kPrimary,
          unselectedItemColor: kOnSurfaceVariant,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          elevation: 0,
          currentIndex: navigationShell.currentIndex,
          onTap: (int idx) => navigationShell.goBranch(
            idx,
            initialLocation: idx == navigationShell.currentIndex,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sports_esports_rounded),
              activeIcon: Icon(Icons.sports_esports_rounded),
              label: 'Play',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.group_rounded),
              activeIcon: Icon(Icons.group_rounded),
              label: 'Friends',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights_rounded),
              activeIcon: Icon(Icons.insights_rounded),
              label: 'Analysis',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories_rounded),
              activeIcon: Icon(Icons.auto_stories_rounded),
              label: 'Learn',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.cell_tower_rounded),
              activeIcon: Icon(Icons.cell_tower_rounded),
              label: 'Connect',
            ),
          ],
        ),
      ),
    );
  }
}
