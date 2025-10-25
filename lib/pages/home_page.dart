import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../widget/nav_bar.dart';
import 'swipe_page.dart';

class HomePage extends StatefulWidget {
  final int? initialIndex;
  HomePage({Key? key, this.initialIndex}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedIndex;

  final List<Widget> _pages = [
    const SwapTab(),
    const HomeTab(),
    const SearchTab(), // acts as Explore
    const ListTab(),
    const ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ViewPick'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await SupabaseService.signOut();
              if (!mounted) return;
              Navigator.of(context).pushReplacementNamed('/');
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: _selectedIndex,
        onItemSelected: (index) {
          if (index == 0) {
            // Navigate to swipe page with no transition (smooth instant change)
            Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, __, ___) => const SwipePage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ));
            return;
          }
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Home Tab - Your Feed'),
    );
  }
}

class SearchTab extends StatelessWidget {
  const SearchTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Search Tab - Discover Content'),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Profile Tab - Your Info'),
    );
  }
}

class SwapTab extends StatelessWidget {
  const SwapTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Swap Tab'));
  }
}

class ListTab extends StatelessWidget {
  const ListTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('List Tab'));
  }
}