import 'package:flutter/material.dart';
import 'home_page.dart';
import '../widget/nav_bar.dart';

class SwipePage extends StatefulWidget {
  const SwipePage({Key? key}) : super(key: key);

  @override
  State<SwipePage> createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Swipe')),
      body: const Center(child: Text('Swipe page content goes here')),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 0,
        onItemSelected: (index) {
          if (index == 0) return; // already here
          // Navigate back to HomePage with requested tab selected (no animation)
          Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomePage(initialIndex: index),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ));
        },
      ),
    );
  }
}
