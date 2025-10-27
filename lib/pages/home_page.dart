import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/tmdb_service.dart';
import '../widget/nav_bar.dart';
import '../widget/movie_series_toggle.dart';
import '../widget/frosted_card.dart';
import 'swipe_page.dart';
import 'dart:math';

class HomePage extends StatefulWidget {
  final int? initialIndex;
  HomePage({Key? key, this.initialIndex}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedIndex;
  bool _isMovieMode = true; // For toggle widget

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex ?? 1;
  }

  List<Widget> _buildPages() {
    return [
      const SwapTab(),
      HomeTab(isMovieMode: _isMovieMode),
      const ListTab(),
      const ProfileTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    return Scaffold(
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
          // Movie/Series Toggle
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: MovieSeriesToggle(
              isMovieMode: _isMovieMode,
              onToggle: (isMovie) {
                setState(() {
                  _isMovieMode = isMovie;
                });
              },
            ),
          ),
          // Content with scrolling
          Expanded(
            child: SingleChildScrollView(
              child: pages[_selectedIndex],
            ),
          ),
        ],
      ),
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

class HomeTab extends StatefulWidget {
  final bool isMovieMode;
  const HomeTab({Key? key, required this.isMovieMode}) : super(key: key);

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _youMayLike = [];
  List<Map<String, dynamic>> _newlyReleased = [];
  List<Map<String, dynamic>> _watchlist = [];
  List<Map<String, dynamic>> _trending = [];

  @override
  void initState() {
    super.initState();
    _fetchAllSections();
  }

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMovieMode != widget.isMovieMode) {
      _fetchAllSections();
    }
  }

  Future<void> _fetchAllSections() async {
    setState(() => _isLoading = true);
    
    try {
      // Fetch all sections
      final allSections = await Future.wait([
        _fetchYouMayLike(),
        _fetchNewlyReleased(),
        _fetchWatchlist(),
        _fetchTrending(),
      ]);

      setState(() {
        _youMayLike = allSections[0];
        _newlyReleased = allSections[1];
        _watchlist = allSections[2];
        _trending = allSections[3];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchYouMayLike() async {
    try {
      final likedGenres = await SupabaseService.getLikedGenres();
      print('=== FETCHING YOU MAY LIKE ===');
      print('Liked genres from DB: $likedGenres');
      
      if (likedGenres.isEmpty) {
        print('No liked genres, showing popular content');
        // Fallback to popular content
        final items = widget.isMovieMode
            ? await _tmdbService.getPopularMovies()
            : await _tmdbService.getPopularTV();
        return items.take(10).map((item) => _formatItem(item)).toList();
      }

      // Get user's language preference
      final language = SupabaseService.getUserLanguage();
      print('User language: $language');

      final genreMap = widget.isMovieMode 
          ? await _tmdbService.getGenreList()
          : await _tmdbService.getTVGenreList();
      
      print('Genre map keys: ${genreMap.keys.toList()}');
      print('Genre map values: ${genreMap.values.toList()}');
      
      // Case-insensitive matching with fuzzy logic
      final likedGenreIds = <int>[];
      for (final likedGenre in likedGenres) {
        for (final entry in genreMap.entries) {
          if (entry.value.toLowerCase().trim() == likedGenre.toLowerCase().trim()) {
            likedGenreIds.add(entry.key);
            print('Matched: "$likedGenre" -> ${entry.key} (${entry.value})');
            break;
          }
        }
      }

      print('Matched genre IDs: $likedGenreIds');

      if (likedGenreIds.isEmpty) {
        print('No genre IDs matched, falling back to popular');
        // Fallback to popular content
        final items = widget.isMovieMode
            ? await _tmdbService.getPopularMovies()
            : await _tmdbService.getPopularTV();
        return items.take(10).map((item) => _formatItem(item)).toList();
      }

      final randomGenreId = likedGenreIds[Random().nextInt(likedGenreIds.length)];
      print('Using genre ID: $randomGenreId');
      
      final items = widget.isMovieMode
          ? await _tmdbService.getMoviesByGenre(randomGenreId, language: language)
          : await _tmdbService.getTVByGenre(randomGenreId, language: language);
      
      print('Fetched ${items.length} items');
      final result = items.take(10).map((item) => _formatItem(item)).toList();
      print('Returning ${result.length} formatted items');
      return result;
    } catch (e, stackTrace) {
      print('Error in _fetchYouMayLike: $e');
      print('Stack trace: $stackTrace');
      // Return popular content as fallback
      try {
        final items = widget.isMovieMode
            ? await _tmdbService.getPopularMovies()
            : await _tmdbService.getPopularTV();
        return items.take(10).map((item) => _formatItem(item)).toList();
      } catch (e2) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNewlyReleased() async {
    try {
      final items = widget.isMovieMode
          ? await _tmdbService.getNowPlayingMovies()
          : await _tmdbService.getOnTheAirTV();
      
      return items.take(10).map((item) => _formatItem(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchWatchlist() async {
    try {
      final watchlist = await SupabaseService.getWatchlist();
      return watchlist.map((item) => {
        'id': item['item_id'],
        'title': item['title'],
        'year': item['release_date']?.substring(0, 4) ?? '',
        'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
        'subtitle': item['overview'] ?? 'No description',
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTrending() async {
    try {
      final items = widget.isMovieMode
          ? await _tmdbService.getTrendingMovies()
          : await _tmdbService.getTrendingTV();
      
      return items.take(10).map((item) => _formatItem(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Map<String, dynamic> _formatItem(dynamic item) {
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.isNotEmpty ? releaseDate.substring(0, 4) : '';
    final subtitle = (item['overview'] as String?) ?? 'No description';
    
    return {
      'id': item['id'],
      'title': name,
      'year': year,
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
      'subtitle': subtitle.length > 50 ? subtitle.substring(0, 50) + '...' : subtitle,
    };
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return FrostedCard(
                imageUrl: item['image'] ?? '',
                title: item['title'] ?? 'No Title',
                year: item['year'] ?? '',
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('You May Like', _youMayLike),
          _buildSection('Newly Released', _newlyReleased),
          _buildSection('From Watchlist', _watchlist),
          _buildSection('Trending This Week', _trending),
        ],
      ),
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