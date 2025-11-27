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

  bool _isFetchingMore = false;

  Future<void> _fetchMovies() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final newContent = await _fetchContentBatch();

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

  Future<List<Map<String, dynamic>>> _fetchContentBatch() async {
    try {
      // Use appropriate genre map based on mode
      final activeGenreMap = _isMovieMode ? _genreMap : _tvGenreMap;

      final Set<Map<String, dynamic>> personalizedContent = {};

      // Get user's preferred languages
      final userLanguages = SupabaseService.getUserLanguages();

      // Get 3 personalized cards from user's preferred languages and genres
      // Check if user has liked content
      final hasLikedContent = await SupabaseService.hasLikedContent(
        _isMovieMode,
      );

      if (userLanguages.isNotEmpty) {
        try {
          // Pick a random language from user preferences
          final randomLanguage =
              userLanguages[Random().nextInt(userLanguages.length)];
          final randomLanguageCode = randomLanguage.split('-')[0];

          // Check if user has liked content to refine by genre
          if (hasLikedContent) {
            // User has liked content - get their genre preferences
            final likedGenres = _isMovieMode
                ? await SupabaseService.getLikedMovieGenres()
                : await SupabaseService.getLikedTVGenres();
            final likedGenreIds = activeGenreMap.entries
                .where((entry) => likedGenres.contains(entry.value))
                .map((entry) => entry.key)
                .toList();

            if (likedGenreIds.isNotEmpty) {
              // Get personalized content using random genre from user preferences
              final randomGenreId =
                  likedGenreIds[Random().nextInt(likedGenreIds.length)];
              final randomPage =
                  Random().nextInt(20) + 1; // Random page between 1 and 20

              final content = _isMovieMode
                  ? await _tmdbService.getMoviesByGenre(
                      randomGenreId,
                      language: randomLanguage,
                      page: randomPage,
                    )
                  : await _tmdbService.getTVByGenre(
                      randomGenreId,
                      language: randomLanguage,
                      page: randomPage,
                    );
              content.shuffle();
              personalizedContent.addAll(
                content.take(3).map((item) => _formatData(item)),
              );
            }
          }

          // If we didn't get enough personalized content (or user has no liked genres),
          // fetch popular/discover content in their preferred language
          if (personalizedContent.length < 3) {
            final randomPage = Random().nextInt(10) + 1;
            final content = _isMovieMode
                ? await _tmdbService.getMoviesByOriginalLanguage(
                    randomLanguageCode,
                    page: randomPage,
                  )
                : await _tmdbService
                      .getTVByOriginalLanguage(
                        randomLanguageCode,
                        page: randomPage,
                      )
                      .catchError((e) async {
                        print('Error fetching TV by language: $e');
                        return <Map<String, dynamic>>[];
                      });

            content.shuffle();
            final needed = 3 - personalizedContent.length;
            personalizedContent.addAll(
              content.take(needed).map((item) => _formatData(item)),
            );
          }
        } catch (e) {
          print('Error fetching personalized content: $e');
          // Continue to fetch random content
        }
      }

      // Get 3 random cards (any genre, any language)
      final randomPage =
          Random().nextInt(50) +
          1; // Random page between 1 and 50 for popular content

      // Pick a random language from supported languages
      final supportedLanguages = SupabaseService.supportedLanguageCodes;
      final randomLanguageCode =
          supportedLanguages[Random().nextInt(supportedLanguages.length)].split(
            '-',
          )[0];

      final randomContent = _isMovieMode
          ? await _tmdbService
                .getMoviesByOriginalLanguage(
                  randomLanguageCode,
                  page: randomPage,
                )
                .then(
                  (res) => res
                      .where(
                        (item) =>
                            item['overview'] != null &&
                            item['overview'].isNotEmpty,
                      )
                      .toList(),
                )
          : await _tmdbService
                .getTVByOriginalLanguage(randomLanguageCode, page: randomPage)
                .then(
                  (res) => res
                      .where(
                        (item) =>
                            item['overview'] != null &&
                            item['overview'].isNotEmpty,
                      )
                      .toList(),
                )
                .catchError((e) async {
                  print('Error fetching TV by language: $e');
                  return await _tmdbService.getPopularTV(page: randomPage);
                });
      randomContent.shuffle();

      // Get 3 random content, avoiding duplicates
      final totalNeeded = 6 - personalizedContent.length;
      final remainingContent = randomContent
          .where(
            (item) => !personalizedContent.any(
              (pContent) => pContent['id'] == item['id'],
            ),
          )
          .take(totalNeeded)
          .map((item) => _formatData(item));

      final allContent = {...personalizedContent, ...remainingContent}.toList();
      allContent.shuffle();

      // Final fallback: If we still have no content, fetch popular items
      if (allContent.isEmpty) {
        print('Batch empty, fetching popular fallback...');
        final fallbackContent = _isMovieMode
            ? await _tmdbService.getPopularMovies(page: 1)
            : await _tmdbService.getPopularTV(page: 1);

        return fallbackContent
            .take(6)
            .map((item) => _formatData(item))
            .toList();
      }

      return allContent;
    } catch (e) {
      print('Error in _fetchContentBatch: $e');
      return [];
    }
  }

  Future<void> _loadMoreContent() async {
    if (_isFetchingMore) return;

    _isFetchingMore = true;
    print('Fetching more content...');

    try {
      final newContent = await _fetchContentBatch();
      if (newContent.isNotEmpty && mounted) {
        setState(() {
          _movies.addAll(newContent);
        });
        print('Added ${newContent.length} new items. Total: ${_movies.length}');
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
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
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
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _fetchMovies,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
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
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Icon(
                              Icons.movie,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
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
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        movie['genre'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
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
    }

    // Infinite scroll trigger: Load more when reaching the 3rd card (index 2)
    // or when we are close to the end of the list
    if (previousIndex >= _movies.length - 2 || previousIndex == 2) {
      _loadMoreContent();
    }

    return true;
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
              color: Colors.black.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.2)),
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
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  movie['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Add to...',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Added ${movie['name']} to Watchlist',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
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
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Marked ${movie['name']} as Watched',
                                  ),
                                  backgroundColor: Colors.blue,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
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
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Marked ${show['name']} as fully watched'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      print('Error marking all as watched: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark as watched'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showWatchedTillDialog(Map<String, dynamic> show) async {
    print('Fetching details for TV Show ID: ${show['id']}');
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
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
                color: Colors.black.withOpacity(0.85),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Watched till...',
                    style: const TextStyle(
                      color: Colors.white,
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
                            title: const Text(
                              'None (Watched All / Clear)',
                              style: TextStyle(color: Colors.white),
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
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '$episodeCount Episodes',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            iconColor: Colors.white,
                            collapsedIconColor: Colors.white70,
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
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Text(
                                        '$epNum',
                                        style: const TextStyle(
                                          color: Colors.white,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to load seasons. Please check your connection.',
            ),
            backgroundColor: Colors.red,
          ),
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
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked as watched'),
          backgroundColor: Colors.blue,
        ),
      );
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
        print('Saved liked ${_isMovieMode ? "movie" : "TV"} genres: $genre');
      } catch (e) {
        print('Error saving liked content: $e');
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
