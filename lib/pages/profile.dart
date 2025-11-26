import 'package:flutter/material.dart';
import '../widget/nav_bar.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Or use theme background
      body: const Center(
        child: Text(
          'Profile Page',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 4, // Profile icon index
        onItemSelected: (index) {
          if (index == 4) return;
          FrostedNavBar.handleNavigation(context, index);
        },
      ),
    );
  }
}
