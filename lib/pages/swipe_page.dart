import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/nav_bar.dart';
import '../widget/movie_series_toggle.dart';
import 'home_page.dart';

class SwipePage extends StatefulWidget {
  const SwipePage({Key? key}) : super(key: key);

  @override
  State<SwipePage> createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage> {
  final CardSwiperController controller = CardSwiperController();
  final TMDBService _tmdbService = TMDBService();
  Map<int, String> _genreMap = {};
  Map<int, String> _tvGenreMap = {};

  List<Map<String, dynamic>> _movies = [];
  bool _isLoading = true;
  bool _isMovieMode = true; // true for movies, false for series

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _genreMap = await _tmdbService.getGenreList();
      _tvGenreMap = await _tmdbService.getTVGenreList();
      await _fetchMovies();
    } catch (e) {
      print('Error initializing page: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchMovies() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Use appropriate genre map based on mode
      final activeGenreMap = _isMovieMode ? _genreMap : _tvGenreMap;
      
      // Check if user has liked content
      final hasLikedContent = await SupabaseService.hasLikedMovies();
      
      final Set<Map<String, dynamic>> personalizedContent = {};
      
      if (hasLikedContent) {
        // User has liked content - get their genre preferences
        final likedGenres = await SupabaseService.getLikedGenres();
        final likedGenreIds = activeGenreMap.entries
            .where((entry) => likedGenres.contains(entry.value))
            .map((entry) => entry.key)
            .toList();

        if (likedGenreIds.isNotEmpty) {
          // Get 3 personalized content based on liked genres
          final randomGenreId = likedGenreIds[Random().nextInt(likedGenreIds.length)];
          final content = _isMovieMode
              ? await _tmdbService.getMoviesByGenre(randomGenreId)
              : await _tmdbService.getTVByGenre(randomGenreId);
          content.shuffle();
          personalizedContent.addAll(content.take(3).map((item) => _formatData(item)));
        }
      }
      
      // Always get popular content for random selection
      final popularContent = _isMovieMode
          ? await _tmdbService.getPopularMovies()
          : await _tmdbService.getPopularTV();
      popularContent.shuffle();
      
      // Get remaining content (3 random if personalized, 6 total random if not)
      final totalNeeded = 6 - personalizedContent.length;
      final remainingContent = popularContent
          .where((item) => !personalizedContent.any((pContent) => pContent['id'] == item['id']))
          .take(totalNeeded)
          .map((item) => _formatData(item));

      final allContent = {...personalizedContent, ...remainingContent}.toList();
      allContent.shuffle();

      if (mounted) {
        setState(() {
          _movies = allContent;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching content: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _formatData(dynamic item) {
    final activeGenreMap = _isMovieMode ? _genreMap : _tvGenreMap;
    final genreIds = item['genre_ids'] as List<dynamic>? ?? [];
    final genres = genreIds.map((id) => activeGenreMap[id]).where((name) => name != null).join(', ');
    
    // Handle movies vs TV series (different field names)
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.isNotEmpty ? releaseDate.substring(0, 4) : '';
    
    return {
      'id': item['id'],
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
      'name': name,
      'year': year,
      'genre': genres,
      'description': item['overview'],
    };
  }

  void _swipeUp() {
    controller.swipeTop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Toggle buttons for Movies/Series - always visible
          Padding(
            padding: const EdgeInsets.only(top: 30.0, bottom: 8.0),
            child: MovieSeriesToggle(
              isMovieMode: _isMovieMode,
              onToggle: (isMovie) {
                setState(() {
                  _isMovieMode = isMovie;
                });
                _fetchMovies();
              },
            ),
          ),
          // Card area - shows loading or content
          Expanded(
            child: _isLoading
                ? Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: MediaQuery.of(context).size.height * 0.68,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  )
                : _movies.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'Could not load ${_isMovieMode ? "movies" : "series"}. Please check your internet connection.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    :                     Center(
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.68,
                          width: MediaQuery.of(context).size.width * 0.9,
                          child: CardSwiper(
                            controller: controller,
                            cardsCount: _movies.length,
                            onSwipe: _onSwipe,
                            onUndo: _onUndo,
                            numberOfCardsDisplayed:
                                _movies.length < 3 ? _movies.length : 3,
                            backCardOffset: const Offset(40, 40),
                            padding: const EdgeInsets.all(24.0),
                            cardBuilder: (
                              context,
                              index,
                              horizontalThresholdPercentage,
                              verticalThresholdPercentage,
                            ) {
                              final movie = _movies[index];
                              return _buildMovieCard(movie);
                            },
                          ),
                        ),
                      ),
          ),
          // Control buttons - only show when not loading and has movies
          if (!_isLoading && _movies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                      Icons.undo, () => controller.undo()),
                  _buildControlButton(Icons.arrow_upward, _swipeUp),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 0, // First icon is selected for SwipePage
        onItemSelected: (index) {
          if (index == 0) {
            // Already on SwipePage, do nothing.
            return;
          }
          // For any other icon, navigate to HomePage with the selected index.
          // We use pushReplacement to avoid stacking swipe pages.
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => HomePage(initialIndex: index),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildMovieCard(Map<String, dynamic> movie) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      movie['image'] ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.movie, color: Colors.white, size: 50)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  movie['name'] ?? 'No Title',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      movie['year'] ?? '',
                      style: const TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        movie['genre'] ?? '',
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  movie['description'] ?? 'No Description',
                  style: const TextStyle(fontSize: 14, color: Colors.white60),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _onSwipe(int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    debugPrint(
        'The card $previousIndex was swiped to the ${direction.name}. Now the card $currentIndex is on top');
    if (direction == CardSwiperDirection.right) {
      // Handle 'like'
      final movie = _movies[previousIndex];
      _saveLikedMovie(movie);
    }
    return true;
  }

  Future<void> _saveLikedMovie(Map<String, dynamic> movie) async {
    final genre = movie['genre'] as String?;
    if (genre != null && genre.isNotEmpty) {
      try {
        await SupabaseService.addLikedGenres(genre);
        print('Saved liked movie genres: $genre');
      } catch (e) {
        print('Error saving liked movie: $e');
      }
    }
  }

  bool _onUndo(int? previousIndex, int currentIndex, CardSwiperDirection direction) {
    debugPrint('The card $currentIndex was undod from the ${direction.name}.');
    return true;
  }
}