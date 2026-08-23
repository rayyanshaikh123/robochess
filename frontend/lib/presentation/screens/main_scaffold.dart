import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: navigationShell.currentIndex,
        onTap: (int idx) => navigationShell.goBranch(
          idx,
          initialLocation: idx == navigationShell.currentIndex,
        ),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.videogame_asset), label: 'Play'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Friends'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Analysis'),
          BottomNavigationBarItem(icon: Icon(Icons.school), label: 'Learn'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Connect'),
        ],
      ),
    );
  }
}
