import 'package:flutter/material.dart';

import 'movies.dart';
import 'series.dart';
import '../services/supabase_service.dart';
import '../services/tmdb_service.dart';
import '../widget/nav_bar.dart';
import '../widget/movie_series_toggle.dart';
import '../widget/frosted_card.dart';

import 'dart:math';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isMovieMode = true; // For toggle widget

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Page Content (HomeTab handles its own scrolling)
          HomeTab(isMovieMode: _isMovieMode),

          // Static Title
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'VIEWPICK',
                style: TextStyle(
                  fontFamily: 'BitcountGridSingle',
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),

          // Floating Movie/Series Toggle
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Center(
              child: MovieSeriesToggle(
                isMovieMode: _isMovieMode,
                onToggle: (isMovie) {
                  setState(() {
                    _isMovieMode = isMovie;
                  });
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 1, // Home is always index 1
        onItemSelected: (index) {
          // Navigation is handled by FrostedNavBar internally
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
      // "You May Like" uses user's preferred languages
      // Other sections use random language from preferences
      final allSections = await Future.wait([
        _fetchYouMayLike(),
        _fetchNewlyReleased(SupabaseService.getUserLanguage()),
        _fetchWatchlist(),
        _fetchTrending(SupabaseService.getUserLanguage()),
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
      // 1. Get Liked Genres
      final likedGenres = widget.isMovieMode
          ? await SupabaseService.getLikedMovieGenres()
          : await SupabaseService.getLikedTVGenres();

      // 2. Get User Languages
      final userLanguages = SupabaseService.getUserLanguages();

      // 3. Map Genres to IDs
      final genreMap = widget.isMovieMode
          ? await _tmdbService.getGenreList()
          : await _tmdbService.getTVGenreList();

      final likedGenreIds = <int>[];
      for (final likedGenre in likedGenres) {
        for (final entry in genreMap.entries) {
          if (entry.value.toLowerCase().trim() ==
              likedGenre.toLowerCase().trim()) {
            likedGenreIds.add(entry.key);
            break;
          }
        }
      }

      // 4. Determine Languages to fetch from
      // If no user languages, default to English
      // If multiple, take up to 3 random ones to mix content
      List<String> targetLanguages = [];
      if (userLanguages.isEmpty) {
        targetLanguages = ['en-US'];
      } else {
        targetLanguages = List.from(userLanguages)..shuffle();
        if (targetLanguages.length > 3) {
          targetLanguages = targetLanguages.take(3).toList();
        }
      }

      List<dynamic> allRawItems = [];

      // 5. Fetch content for each language
      final futures = targetLanguages.map((language) async {
        // Extract language code (e.g. 'ml' from 'ml-IN') for strict filtering
        final langCode = language.split('-')[0];

        if (likedGenreIds.isNotEmpty) {
          // If we have liked genres, pick a random one for this language
          final randomGenreId =
              likedGenreIds[Random().nextInt(likedGenreIds.length)];
          return widget.isMovieMode
              ? await _tmdbService.getMoviesByGenre(
                  randomGenreId,
                  language: language,
                  withOriginalLanguage: langCode,
                )
              : await _tmdbService.getTVByGenre(
                  randomGenreId,
                  language: language,
                  withOriginalLanguage: langCode,
                );
        } else {
          // If no liked genres, fetch popular/trending for this language
          return widget.isMovieMode
              ? await _tmdbService.getMoviesByOriginalLanguage(
                  langCode,
                  language: language,
                )
              : await _tmdbService.getTVByOriginalLanguage(
                  langCode,
                  language: language,
                );
        }
      });

      final results = await Future.wait(futures);
      for (var list in results) {
        allRawItems.addAll(list);
      }

      // 6. Deduplicate and Shuffle
      final uniqueItems = <int, Map<String, dynamic>>{};
      for (var item in allRawItems) {
        if (item['id'] != null) {
          uniqueItems[item['id']] = _formatItem(item);
        }
      }

      final finalList = uniqueItems.values.toList()..shuffle();

      return finalList.take(10).toList();
    } catch (e) {
      print('Error in _fetchYouMayLike: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNewlyReleased(
    String language,
  ) async {
    try {
      final items = widget.isMovieMode
          ? await _tmdbService.getNowPlayingMovies(language: language)
          : await _tmdbService.getOnTheAirTV(language: language);

      // Filter for items released in the last 3 months (approx 90 days)
      final now = DateTime.now();
      final threeMonthsAgo = now.subtract(const Duration(days: 90));

      final recentItems = items.where((item) {
        final dateStr = item['release_date'] ?? item['first_air_date'];
        if (dateStr == null || dateStr.isEmpty) return false;
        try {
          final date = DateTime.parse(dateStr);
          return date.isAfter(threeMonthsAgo) &&
              date.isBefore(
                now.add(const Duration(days: 7)),
              ); // Allow slightly future releases (e.g. this week)
        } catch (e) {
          return false;
        }
      }).toList();

      // Sort by release date descending (newest first)
      recentItems.sort((a, b) {
        final dateA = a['release_date'] ?? a['first_air_date'] ?? '';
        final dateB = b['release_date'] ?? b['first_air_date'] ?? '';
        return dateB.compareTo(dateA);
      });

      return recentItems.take(10).map((item) => _formatItem(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchWatchlist() async {
    try {
      final watchlist = await SupabaseService.getWatchlist();

      // Filter based on current mode
      final filteredItems = watchlist.where((item) {
        final isMovie = item['item_type'] == 'movie';
        return isMovie == widget.isMovieMode;
      }).toList();

      // Fetch details in parallel
      final futures = filteredItems.map((item) async {
        try {
          final int id = item['item_id'];
          final bool isMovie = item['item_type'] == 'movie';

          Map<String, dynamic> details;
          if (isMovie) {
            details = await _tmdbService.getMovieDetails(id);
          } else {
            details = await _tmdbService.getTVDetails(id);
          }

          final name = details['title'] ?? details['name'] ?? 'No Title';
          final releaseDate =
              details['release_date'] ?? details['first_air_date'] ?? '';
          final year = releaseDate.isNotEmpty
              ? releaseDate.substring(0, 4)
              : '';
          final overview = details['overview'] ?? 'No description';

          return {
            'id': id,
            'title': name,
            'year': year,
            'image': 'https://image.tmdb.org/t/p/w500${details['poster_path']}',
            'subtitle': overview.length > 50
                ? overview.substring(0, 50) + '...'
                : overview,
          };
        } catch (e) {
          print(
            'Error fetching details for watchlist item ${item['item_id']}: $e',
          );
          // Fallback to Supabase data
          return {
            'id': item['item_id'],
            'title': item['title'],
            'year': item['release_date']?.substring(0, 4) ?? '',
            'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
            'subtitle': item['overview'] ?? 'No description',
          };
        }
      });

      final results = await Future.wait(futures);
      return results;
    } catch (e) {
      print('Error fetching watchlist: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTrending(String language) async {
    try {
      final items = widget.isMovieMode
          ? await _tmdbService.getTrendingMovies(language: language)
          : await _tmdbService.getTrendingTV(language: language);

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
      'subtitle': subtitle.length > 50
          ? subtitle.substring(0, 50) + '...'
          : subtitle,
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
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
              return GestureDetector(
                onTap: () async {
                  if (widget.isMovieMode) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MoviePage(movieId: item['id']),
                      ),
                    );
                  } else {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SeriesPage(tvId: item['id']),
                      ),
                    );
                  }
                  _fetchAllSections();
                },
                child: FrostedCard(
                  imageUrl: item['image'] ?? '',
                  title: item['title'] ?? 'No Title',
                  year: item['year'] ?? '',
                ),
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
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('You May Like', _youMayLike),
          _buildSection('Newly Released', _newlyReleased),
          _buildSection('From Watchlist', _watchlist),
          _buildSection('Trending This Week', _trending),
          const SizedBox(height: 100), // For bottom nav bar
        ],
      ),
    );
  }
}
