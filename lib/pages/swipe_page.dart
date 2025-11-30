import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/nav_bar.dart';
import '../widget/movie_series_toggle.dart';
import 'home_page.dart';
import 'explore.dart';
import 'list_page.dart';
import 'profile.dart';
import '../widget/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'movies.dart';
import 'series.dart';

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
  int _languageCycleIndex = 0; // To track rotation of preferred languages

  @override
  void initState() {
    super.initState();
    _initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstTime());
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_swipe_instructions') ?? false;
    if (!seen) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'How to Swipe',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.swipe_right,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Swipe Right to Like',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.swipe_left,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Swipe Left to Dislike',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.swipe_up,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Swipe Up to Skip',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  prefs.setBool('seen_swipe_instructions', true);
                },
                child: Text(
                  'Got it!',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _initialize() async {
    try {
      try {
        _genreMap = await _tmdbService.getGenreList();
      } catch (e) {
        print('Error loading movie genres: $e');
      }

      try {
        _tvGenreMap = await _tmdbService.getTVGenreList();
      } catch (e) {
        print('Error loading TV genres: $e');
      }

      // Ensure we have at least some genres or handle empty map later
      if (_tvGenreMap.isEmpty) {
        print('Warning: TV Genre map is empty. Retrying...');
        try {
          _tvGenreMap = await _tmdbService.getTVGenreList();
        } catch (e) {
          print('Retry failed: $e');
        }
      }

      // Initial fetch (small batch for speed)
      await _fetchMovies(count: 6);

      // Pre-fetch more content in background
      _loadMoreContent(count: 15);
    } catch (e) {
      print('Error initializing page: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isFetchingMore = false;

  Future<void> _fetchMovies({int count = 6}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final newContent = await _fetchContentBatch(targetCount: count);

      if (mounted) {
        setState(() {
          _movies = newContent;
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

  Future<List<Map<String, dynamic>>> _fetchContentBatch({
    int targetCount = 6,
  }) async {
    try {
      final activeGenreMap = _isMovieMode ? _genreMap : _tvGenreMap;

      // 1. Parallel Supabase Calls
      final results = await Future.wait([
        SupabaseService.getDislikes(),
        _isMovieMode
            ? SupabaseService.getLikedMovieGenres()
            : SupabaseService.getLikedTVGenres(),
      ]);

      final dislikes = results[0] as List<Map<String, dynamic>>;
      final likedGenres = results[1] as List<String>;
      final hasLikedContent = likedGenres.isNotEmpty;
      final userLanguages = SupabaseService.getUserLanguages();

      bool isDisliked(Map<String, dynamic> item) {
        final itemYear =
            int.tryParse(
              (item['release_date'] ?? item['first_air_date'] ?? '')
                  .toString()
                  .substring(0, 4),
            ) ??
            0;
        final itemGenres = (item['genre_ids'] as List<dynamic>? ?? [])
            .map((id) => activeGenreMap[id])
            .where((name) => name != null)
            .toList();

        for (final dislike in dislikes) {
          final reason = dislike['reason'];
          final details = dislike['details'];

          if (reason == 'genre') {
            if (itemGenres.contains(details['genre'])) return true;
          } else if (reason == 'year_exact') {
            if (itemYear == details['year']) return true;
          } else if (reason == 'year_before') {
            if (itemYear < details['year']) return true;
          } else if (reason == 'language') {
            if (item['original_language'] == details['language_code'])
              return true;
          }
        }
        return false;
      }

      final Set<Map<String, dynamic>> personalizedContent = {};
      final Set<Map<String, dynamic>> randomContent = {};

      // 2. Prepare Personalized Content Fetch
      Future<void> fetchPersonalized() async {
        if (userLanguages.isEmpty) return;

        final dislikedLanguages = dislikes
            .where((d) => d['reason'] == 'language')
            .map((d) => d['details']['language_code'])
            .toSet();

        final availableLanguages = userLanguages.where((lang) {
          return !dislikedLanguages.any((dl) => lang.contains(dl));
        }).toList();

        if (availableLanguages.isEmpty) return;

        // Prepare futures for 3 cards
        final futures = List.generate(3, (i) async {
          final langIndex =
              (_languageCycleIndex + i) % availableLanguages.length;
          final targetLanguage = availableLanguages[langIndex];
          final targetLanguageCode = targetLanguage.split('-')[0];

          // Try Genre-based first
          if (hasLikedContent) {
            final dislikedGenreNames = dislikes
                .where((d) => d['reason'] == 'genre')
                .map((d) => d['details']['genre'])
                .toSet();

            final validGenreIds = activeGenreMap.entries
                .where(
                  (entry) =>
                      likedGenres.contains(entry.value) &&
                      !dislikedGenreNames.contains(entry.value),
                )
                .map((entry) => entry.key)
                .toList();

            if (validGenreIds.isNotEmpty) {
              final randomGenreId =
                  validGenreIds[Random().nextInt(validGenreIds.length)];
              // Use a wider range of pages to avoid collisions if fetching same genre multiple times
              final randomPage = Random().nextInt(10) + 1;

              try {
                final content = _isMovieMode
                    ? await _tmdbService.getMoviesByGenre(
                        randomGenreId,
                        language: targetLanguage,
                        withOriginalLanguage: targetLanguageCode,
                        page: randomPage,
                      )
                    : await _tmdbService.getTVByGenre(
                        randomGenreId,
                        language: targetLanguage,
                        withOriginalLanguage: targetLanguageCode,
                        page: randomPage,
                      );

                content.shuffle();
                final validItems = content
                    .where((item) => !isDisliked(item))
                    .toList();
                if (validItems.isNotEmpty) {
                  return _formatData(validItems.first);
                }
              } catch (e) {
                // ignore
              }
            }
          }

          // Fallback to Language-based
          final randomPage = Random().nextInt(15) + 1;
          try {
            final content = _isMovieMode
                ? await _tmdbService.getMoviesByOriginalLanguage(
                    targetLanguageCode,
                    page: randomPage,
                  )
                : await _tmdbService.getTVByOriginalLanguage(
                    targetLanguageCode,
                    page: randomPage,
                  );

            content.shuffle();
            final validItems = content
                .where((item) => !isDisliked(item))
                .toList();
            if (validItems.isNotEmpty) {
              return _formatData(validItems.first);
            }
          } catch (e) {
            // ignore
          }
          return null;
        });

        // Update cycle index
        _languageCycleIndex += 3;

        final items = await Future.wait(futures);
        for (var item in items) {
          if (item != null) personalizedContent.add(item);
        }
      }

      // 3. Prepare Random Content Fetch
      Future<void> fetchRandom() async {
        int attempts = 0;
        final supportedLanguages = SupabaseService.supportedLanguageCodes;

        while (randomContent.length < 3 && attempts < 5) {
          attempts++;
          try {
            // Use safer page limit (20 instead of 50) to avoid empty pages
            final randomPage = Random().nextInt(20) + 1;
            final randomLangString =
                supportedLanguages[Random().nextInt(supportedLanguages.length)];
            final randomLangCode = randomLangString.split('-')[0];

            final content = _isMovieMode
                ? await _tmdbService.getMoviesByOriginalLanguage(
                    randomLangCode,
                    page: randomPage,
                  )
                : await _tmdbService.getTVByOriginalLanguage(
                    randomLangCode,
                    page: randomPage,
                  );

            content.shuffle();
            final filteredRandom = content.where((item) => !isDisliked(item));

            for (var item in filteredRandom) {
              if (randomContent.length >= 3) break;
              // Check for duplicates against personalized content too
              if (!personalizedContent.any((p) => p['id'] == item['id']) &&
                  !randomContent.any((r) => r['id'] == item['id'])) {
                randomContent.add(_formatData(item));
              }
            }
          } catch (e) {
            print('Error in random fetch attempt $attempts: $e');
          }
        }
      }

      // 4. Execute in Parallel
      await Future.wait([fetchPersonalized(), fetchRandom()]);

      // 5. Combine and Deduplicate
      final allContent = [...personalizedContent];
      for (var item in randomContent) {
        if (!allContent.any((p) => p['id'] == item['id'])) {
          allContent.add(item);
        }
      }

      // If we haven't met the target count, loop to fetch more
      if (allContent.length < targetCount) {
        // Recursive call or loop could be used, but let's just do a simple fallback fill
        // to avoid infinite recursion complexity.
        int attempts = 0;
        while (allContent.length < targetCount && attempts < 3) {
          attempts++;
          try {
            final randomPage = Random().nextInt(20) + 1;
            final fallback = _isMovieMode
                ? await _tmdbService.getPopularMovies(page: randomPage)
                : await _tmdbService.getPopularTV(page: randomPage);

            final formattedFallback = fallback
                .where((item) => !isDisliked(item))
                .map((item) => _formatData(item));

            for (var item in formattedFallback) {
              if (allContent.length >= targetCount) break;
              if (!allContent.any((existing) => existing['id'] == item['id'])) {
                allContent.add(item);
              }
            }
          } catch (e) {
            print('Error filling batch: $e');
          }
        }
      }

      // Fallback
      if (allContent.isEmpty) {
        debugPrint('Batch empty, fetching popular fallback...');
        final randomPage = Random().nextInt(20) + 1;
        final fallback = _isMovieMode
            ? await _tmdbService.getPopularMovies(page: randomPage)
            : await _tmdbService.getPopularTV(page: randomPage);

        return fallback
            .where((item) => !isDisliked(item))
            .take(6)
            .map((item) => _formatData(item))
            .toList();
      }

      return allContent;
    } catch (e) {
      debugPrint('Error in _fetchContentBatch: $e');
      return [];
    }
  }

  Future<void> _loadMoreContent({int count = 15}) async {
    if (_isFetchingMore) return;

    _isFetchingMore = true;
    print('Fetching more content...');

    int retryCount = 0;
    bool addedContent = false;

    try {
      while (!addedContent && retryCount < 3) {
        if (retryCount > 0) {
          print('Retrying fetch (attempt ${retryCount + 1})...');
          await Future.delayed(const Duration(milliseconds: 500));
        }

        final newContent = await _fetchContentBatch(targetCount: count);
        if (newContent.isNotEmpty && mounted) {
          // Filter out duplicates
          final uniqueContent = newContent.where((newItem) {
            return !_movies.any(
              (existingItem) => existingItem['id'] == newItem['id'],
            );
          }).toList();

          if (uniqueContent.isNotEmpty) {
            setState(() {
              _movies.addAll(uniqueContent);
            });
            print(
              'Added ${uniqueContent.length} new items. Total: ${_movies.length}',
            );
            addedContent = true;
          } else {
            print('Fetched content was all duplicates.');
          }
        }
        retryCount++;
      }
    } catch (e) {
      print('Error loading more content: $e');
    } finally {
      _isFetchingMore = false;
    }
  }

  Map<String, dynamic> _formatData(dynamic item) {
    final activeGenreMap = _isMovieMode ? _genreMap : _tvGenreMap;
    final genreIds = item['genre_ids'] as List<dynamic>? ?? [];
    final genres = genreIds
        .map((id) => activeGenreMap[id])
        .where((name) => name != null)
        .join(', ');

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
      'original_language': item['original_language'],
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
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : _movies.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'Could not load ${_isMovieMode ? "movies" : "series"}. Please check your internet connection.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _fetchMovies,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.68,
                      width: MediaQuery.of(context).size.width * 0.9,
                      child: CardSwiper(
                        controller: controller,
                        cardsCount: _movies.length,
                        onSwipe: _onSwipe,
                        onUndo: _onUndo,
                        isLoop: false,
                        numberOfCardsDisplayed: _movies.length < 3
                            ? _movies.length
                            : 3,
                        backCardOffset: const Offset(40, 40),
                        padding: const EdgeInsets.all(24.0),
                        cardBuilder:
                            (
                              context,
                              index,
                              horizontalThresholdPercentage,
                              verticalThresholdPercentage,
                            ) {
                              final movie = _movies[index];
                              return _buildMovieCard(
                                movie,
                                horizontalThresholdPercentage,
                              );
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
                  _buildControlButton(Icons.undo, () => controller.undo()),
                  _buildControlButton(Icons.arrow_upward, _swipeUp),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 0, // First icon is selected for SwipePage
        onItemSelected: (index) {
          switch (index) {
            case 0:
              // Already on SwipePage
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
            case 2:
              // Navigate to ExplorePage
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const ExplorePage(),
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

  Widget _buildControlButton(IconData icon, VoidCallback onPressed) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: IconButton(
            icon: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildMovieCard(
    Map<String, dynamic> movie, [
    int horizontalThresholdPercentage = 0,
  ]) {
    Color? overlayColor;
    double opacity = 0.0;

    if (horizontalThresholdPercentage != 0) {
      if (horizontalThresholdPercentage > 0) {
        // Swiping Right - Green (Like)
        overlayColor = Theme.of(context).colorScheme.primary;
      } else {
        // Swiping Left - Red (Dislike)
        overlayColor = Theme.of(context).colorScheme.error;
      }

      // Calculate opacity based on swipe distance
      // Assuming threshold percentage goes up to 100 or more
      // We want visible hue starting early but maxing out around 0.5 opacity
      opacity = (horizontalThresholdPercentage.abs() / 100.0).clamp(0.0, 0.5);
    }

    return GestureDetector(
      onTap: () {
        if (_isMovieMode) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MoviePage(movieId: movie['id']),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SeriesPage(tvId: movie['id']),
            ),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
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
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                                  child: Icon(
                                    Icons.movie,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    size: 50,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        movie['name'] ?? 'No Title',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            movie['year'] ?? '',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              movie['genre'] ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        movie['description'] ?? 'No Description',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (overlayColor != null)
                  Container(
                    decoration: BoxDecoration(
                      color: overlayColor.withOpacity(opacity),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    debugPrint(
      'The card $previousIndex was swiped to the ${direction.name}. Now the card $currentIndex is on top',
    );
    if (direction == CardSwiperDirection.right) {
      // Handle 'like'
      final movie = _movies[previousIndex];
      _saveLikedMovie(movie);

      // Add to watchlist automatically on swipe right
      SupabaseService.addToWatchlist(movie, _isMovieMode);

      // Show action dialog after a short delay to allow swipe animation to complete
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _showActionDialog(movie);
        }
      });
    } else if (direction == CardSwiperDirection.left) {
      // Handle 'dislike'
      final movie = _movies[previousIndex];
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _showDislikeReasonDialog(movie);
        }
      });
    }

    // Infinite scroll trigger: Load more when we have fewer than 10 cards remaining
    // This ensures we have a buffer.
    if (_movies.length - previousIndex <= 10) {
      _loadMoreContent(count: 15);
    }

    // If we are at the very last card, try to load more immediately
    if (previousIndex == _movies.length - 1) {
      _loadMoreContent(count: 6); // Emergency fetch
    }

    return true;
  }

  void _showDislikeReasonDialog(Map<String, dynamic> movie) {
    String currentView = 'main'; // 'main', 'genre', 'language', 'year'

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget content;
            void navigateTo(String view) {
              setSheetState(() => currentView = view);
            }

            switch (currentView) {
              case 'genre':
                content = _buildGenreView(movie, navigateTo);
                break;
              case 'language':
                content = _buildLanguageView(movie, navigateTo);
                break;
              case 'year':
                content = _buildYearView(movie, navigateTo);
                break;
              default:
                content = _buildMainDislikeView(movie, navigateTo);
            }

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    content,
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDislikeOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainDislikeView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Why did you dislike this?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        _buildDislikeOption(
          icon: Icons.category,
          label: 'Genre',
          onTap: () => onNavigate('genre'),
        ),
        const SizedBox(height: 16),
        _buildDislikeOption(
          icon: Icons.language,
          label: 'Language',
          onTap: () => onNavigate('language'),
        ),
        const SizedBox(height: 16),
        _buildDislikeOption(
          icon: Icons.calendar_today,
          label: 'Year',
          onTap: () => onNavigate('year'),
        ),
        const SizedBox(height: 16),
        _buildDislikeOption(
          icon: Icons.close,
          label: 'None',
          onTap: () {
            SupabaseService.addDislike(
              itemId: movie['id'],
              isMovie: _isMovieMode,
              reason: 'none',
            );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildGenreView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    final genres = (movie['genre'] as String).split(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => onNavigate('main'),
            ),
            Expanded(
              child: Text(
                'Which genre?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48), // Balance back button
          ],
        ),
        const SizedBox(height: 20),
        ...genres.map(
          (genre) => ListTile(
            title: Text(
              genre,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () {
              SupabaseService.addDislike(
                itemId: movie['id'],
                isMovie: _isMovieMode,
                reason: 'genre',
                details: {'genre': genre},
              );
              Navigator.pop(context);
              Toast.show(context, 'We\'ll show less $genre');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => onNavigate('main'),
            ),
            Expanded(
              child: Text(
                'Language Preference',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Show less content in this language?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'No',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
              onPressed: () {
                SupabaseService.addDislike(
                  itemId: movie['id'],
                  isMovie: _isMovieMode,
                  reason: 'language',
                  details: {
                    'language_code': movie['original_language'] ?? 'en',
                  },
                );
                Navigator.pop(context);
                Toast.show(context, 'We\'ll show less from this language');
              },
              child: Text(
                'Yes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildYearView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    final year = int.tryParse(movie['year'] ?? '') ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => onNavigate('main'),
            ),
            Expanded(
              child: Text(
                'Year Preference',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 20),
        ListTile(
          title: Text(
            'Less from $year',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () {
            SupabaseService.addDislike(
              itemId: movie['id'],
              isMovie: _isMovieMode,
              reason: 'year_exact',
              details: {'year': year},
            );
            Navigator.pop(context);
            Toast.show(context, 'We\'ll show less from $year');
          },
        ),
        ListTile(
          title: Text(
            'Less before $year',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () {
            SupabaseService.addDislike(
              itemId: movie['id'],
              isMovie: _isMovieMode,
              reason: 'year_before',
              details: {'year': year},
            );
            Navigator.pop(context);
            Toast.show(context, 'We\'ll show less before $year');
          },
        ),
      ],
    );
  }

  void _showActionDialog(Map<String, dynamic> movie) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  movie['name'],
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Add to...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: _isMovieMode
                            ? Icons.bookmark_add_outlined
                            : Icons.playlist_play, // Changed icon for Series
                        label: _isMovieMode ? 'Watchlist' : 'Watched Till',
                        onTap: () async {
                          Navigator.pop(context);
                          if (_isMovieMode) {
                            await SupabaseService.addToWatchlist(
                              movie,
                              _isMovieMode,
                            );
                            if (mounted) {
                              if (mounted) {
                                Toast.show(
                                  context,
                                  'Added ${movie['name']} to Watchlist',
                                );
                              }
                            }
                          } else {
                            // Series: "Watchlist" button now triggers "Watched Till"
                            _showWatchedTillDialog(movie);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.check_circle_outline,
                        label: _isMovieMode ? 'Watched' : 'Watched All',
                        onTap: () async {
                          Navigator.pop(context);
                          if (_isMovieMode) {
                            await SupabaseService.addToWatched(movie, true);
                            await SupabaseService.removeFromWatchlist(
                              movie['id'],
                            );
                            if (mounted) {
                              if (mounted) {
                                Toast.show(
                                  context,
                                  'Marked ${movie['name']} as Watched',
                                );
                              }
                            }
                          } else {
                            // Series: "Watched" button now marks ALL as watched
                            _markAllWatched(movie);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _markAllWatched(Map<String, dynamic> show) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    try {
      final details = await _tmdbService.getTVDetails(show['id']);
      final seasons = details['seasons'] as List<dynamic>;

      // Find the last season (ignoring season 0 if possible, or just taking max season number)
      // Usually we want the latest season that has episodes.
      int maxSeason = 0;
      int maxEpisode = 0;

      for (var season in seasons) {
        final seasonNum = season['season_number'] as int;
        final episodeCount = season['episode_count'] as int;

        if (seasonNum > 0 && seasonNum >= maxSeason) {
          maxSeason = seasonNum;
          maxEpisode = episodeCount;
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Pop loading

      if (maxSeason > 0 && maxEpisode > 0) {
        await SupabaseService.addToWatched(
          show,
          false,
          watchedSeason: maxSeason,
          watchedEpisode: maxEpisode,
        );
        await SupabaseService.removeFromWatchlist(show['id']);

        if (mounted) {
          if (mounted) {
            Toast.show(context, 'Marked ${show['name']} as fully watched');
          }
        }
      }
    } catch (e) {
      print('Error marking all as watched: $e');
      if (mounted) {
        Navigator.pop(context);
        Toast.show(context, 'Failed to mark as watched', isError: true);
      }
    }
  }

  Future<void> _showWatchedTillDialog(Map<String, dynamic> show) async {
    print('Fetching details for TV Show ID: ${show['id']}');
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    try {
      // Fetch details to get seasons
      final details = await _tmdbService.getTVDetails(show['id']);
      final seasons = details['seasons'] as List<dynamic>;
      // Sort seasons by season_number
      seasons.sort(
        (a, b) =>
            (a['season_number'] as int).compareTo(b['season_number'] as int),
      );

      if (!mounted) {
        Navigator.pop(context); // Pop the loading dialog
        return;
      }

      // Pop the loading dialog
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Watched till...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: seasons.length + 1, // +1 for "None"
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // "None" option
                          return ListTile(
                            title: Text(
                              'None (Watched All / Clear)',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              // Maybe clear progress or mark all as watched?
                              // For now, let's assume it means "I watched everything"
                              // Or maybe just close the dialog.
                              // Based on user request "1st option none", let's just close it for now
                              // or maybe mark as watched without specific episode?
                              // Let's just close it as a "Cancel" or "No specific episode" option.
                            },
                          );
                        }

                        final season = seasons[index - 1];
                        final seasonNum = season['season_number'];
                        final episodeCount = season['episode_count'];

                        if (seasonNum == 0)
                          return const SizedBox.shrink(); // Skip specials if desired

                        return Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            title: Text(
                              season['name'],
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              '$episodeCount Episodes',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            iconColor: Theme.of(context).colorScheme.onSurface,
                            collapsedIconColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            children: [
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 5,
                                      childAspectRatio: 1.5,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: episodeCount,
                                itemBuilder: (context, epIndex) {
                                  final epNum = epIndex + 1;
                                  return InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      _markWatchedTill(
                                        show,
                                        details,
                                        seasonNum,
                                        epNum,
                                      );
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                      child: Text(
                                        '$epNum',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error fetching seasons: $e');
      if (mounted) {
        // Pop the loading dialog
        Navigator.pop(context);
        Toast.show(
          context,
          'Failed to load seasons. Please check your connection.',
          isError: true,
        );
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurface,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markWatchedTill(
    Map<String, dynamic> show,
    Map<String, dynamic> showDetails,
    int seasonNum,
    int episodeNum,
  ) async {
    // Use addToWatched to ensure it handles both insert (new) and update (existing)
    await SupabaseService.addToWatched(
      show,
      false, // isMovie = false for TV shows
      watchedSeason: seasonNum,
      watchedEpisode: episodeNum,
    );

    if (mounted) {
      Toast.show(context, 'Marked as watched');
    }
  }

  Future<void> _saveLikedMovie(Map<String, dynamic> movie) async {
    final genre = movie['genre'] as String?;
    if (genre != null && genre.isNotEmpty) {
      try {
        if (_isMovieMode) {
          await SupabaseService.addLikedMovieGenres(genre);
        } else {
          await SupabaseService.addLikedTVGenres(genre);
        }
        debugPrint(
          'Saved liked ${_isMovieMode ? "movie" : "TV"} genres: $genre',
        );
      } catch (e) {
        debugPrint('Error saving liked content: $e');
      }
    }
  }

  bool _onUndo(
    int? previousIndex,
    int currentIndex,
    CardSwiperDirection direction,
  ) {
    debugPrint('The card $currentIndex was undod from the ${direction.name}.');
    return true;
  }
}
