import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../widget/frosted_card.dart';
import '../widget/nav_bar.dart';
import '../pages/home_page.dart';
import '../pages/swipe_page.dart';
import '../pages/list_page.dart';
import '../pages/profile.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({Key? key}) : super(key: key);

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final TMDBService _tmdbService = TMDBService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchMixedContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMixedContent() async {
    setState(() => _isLoading = true);

    try {
      // Fetch both movies and TV series
      final allSections = await Future.wait([
        _tmdbService.getPopularMovies(),
        _tmdbService.getPopularTV(),
        _tmdbService.getTrendingMovies(),
        _tmdbService.getTrendingTV(),
      ]);

      // Combine and shuffle all items
      final List<dynamic> allItems = [];
      allItems.addAll(allSections[0]);
      allItems.addAll(allSections[1]);
      allItems.addAll(allSections[2]);
      allItems.addAll(allSections[3]);

      // Shuffle randomly
      allItems.shuffle();

      // Take 30 items (10 rows x 3 cards)
      final formattedItems = allItems
          .take(30)
          .map((item) => _formatItem(item))
          .toList();

      setState(() {
        _items = formattedItems;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching explore content: $e');
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _formatItem(dynamic item) {
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.isNotEmpty ? releaseDate.substring(0, 4) : '';

    return {
      'id': item['id'],
      'title': name,
      'year': year,
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          // VIEWPICK Title
          const Padding(
            padding: EdgeInsets.only(top: 50.0, bottom: 20.0),
            child: Text(
              'VIEWPICK',
              style: TextStyle(
                fontFamily: 'BitcountGridSingle',
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
          ),
          // Search bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search movies and series...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Grid view
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      16.0,
                      0,
                      16.0,
                      100.0,
                    ), // Added bottom padding for nav bar
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.5,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return FrostedCard(
                        imageUrl: item['image'] ?? '',
                        title: item['title'] ?? 'No Title',
                        year: item['year'] ?? '',
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 2, // Explore icon is selected
        onItemSelected: (index) {
          switch (index) {
            case 0:
              // Navigate to SwipePage
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const SwipePage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              break;
            case 1:
              // Navigate to HomePage
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const HomePage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              break;
            case 3:
              // Navigate to ListPage
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const ListPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              break;
            case 4:
              // Navigate to ProfilePage
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const ProfilePage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
              break;
          }
        },
      ),
    );
  }
}
