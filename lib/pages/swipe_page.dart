import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/nav_bar.dart';
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

  List<Map<String, dynamic>> _movies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _genreMap = await _tmdbService.getGenreList();
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
      final likedGenres = await SupabaseService.getLikedGenres();
      final likedGenreIds = _genreMap.entries
          .where((entry) => likedGenres.contains(entry.value))
          .map((entry) => entry.key)
          .toList();

      final Set<Map<String, dynamic>> personalizedMovies = {};
      if (likedGenreIds.isNotEmpty) {
        final randomGenreId = likedGenreIds[Random().nextInt(likedGenreIds.length)];
        final movies = await _tmdbService.getMoviesByGenre(randomGenreId);
        movies.shuffle();
        personalizedMovies.addAll(movies.take(3).map((movie) => _formatMovieData(movie)));
      }

      final popularMovies = await _tmdbService.getPopularMovies();
      popularMovies.shuffle();
      final randomMovies = popularMovies
          .where((movie) => !personalizedMovies.any((pMovie) => pMovie['id'] == movie['id']))
          .take(6 - personalizedMovies.length)
          .map((movie) => _formatMovieData(movie));

      final allMovies = {...personalizedMovies, ...randomMovies}.toList();
      allMovies.shuffle();

      if (mounted) {
        setState(() {
          _movies = allMovies;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching movies: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _formatMovieData(dynamic movie) {
    final genreIds = movie['genre_ids'] as List<dynamic>? ?? [];
    final genres = genreIds.map((id) => _genreMap[id]).where((name) => name != null).join(', ');
    return {
      'id': movie['id'],
      'image': 'https://image.tmdb.org/t/p/w500${movie['poster_path']}',
      'name': movie['title'],
      'year': (movie['release_date'] as String?)?.substring(0, 4) ?? '',
      'genre': genres,
      'description': movie['overview'],
    };
  }

  void _swipeUp() {
    controller.swipeTop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _movies.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      'Could not load movies. Please check your internet connection and TMDB API key.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0, top: 10.0),
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
    if (genre != null) {
      try {
        await SupabaseService.addLikedMovie(genre);
        print('Saved liked movie genre: $genre');
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