import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/nav_bar.dart';
import '../widget/movie_series_toggle.dart';
import 'movies.dart';
import 'series.dart';

class ListPage extends StatefulWidget {
  const ListPage({Key? key}) : super(key: key);

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  bool _isMovieMode = true;
  List<Map<String, dynamic>> _watchlist = [];

  @override
  void initState() {
    super.initState();
    _fetchWatchlist();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstTime());
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_list_instructions') ?? false;
    if (!seen) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Manage List',
              style: TextStyle(color: Colors.white),
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Swipe Right to Left to Mark Watched',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Swipe Left to Right to Remove',
                        style: TextStyle(color: Colors.white70),
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
                  prefs.setBool('seen_list_instructions', true);
                },
                child: const Text(
                  'Got it!',
                  style: TextStyle(
                    color: Colors.blueAccent,
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

  Future<void> _fetchWatchlist() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.getWatchlist();

      final List<Map<String, dynamic>> formattedList = [];

      // Fetch details for each item in parallel
      final futures = data.map((item) async {
        try {
          final int id = item['item_id'];
          final bool isMovie = item['item_type'] == 'movie';

          Map<String, dynamic> details;
          int? nextSeason;
          int? nextEpisode;

          if (isMovie) {
            details = await _tmdbService.getMovieDetails(id);
          } else {
            details = await _tmdbService.getTVDetails(id);

            // Calculate next episode for series
            final watchedItem = await SupabaseService.getWatchedItem(id);
            final currentSeason = watchedItem?['watched_season'] as int? ?? 1;
            final currentEpisode = watchedItem?['watched_episode'] as int? ?? 0;

            // Logic to determine next episode
            // We need to know how many episodes are in the current season
            final seasons = details['seasons'] as List;
            final seasonData = seasons.firstWhere(
              (s) => s['season_number'] == currentSeason,
              orElse: () => null,
            );

            if (seasonData != null) {
              final episodeCount = seasonData['episode_count'] as int;

              // If current episode is less than total episodes, just increment episode
              if (currentEpisode < episodeCount) {
                nextSeason = currentSeason;
                nextEpisode = currentEpisode + 1;
              } else {
                // If current episode is equal to (or greater than) episode count,
                // we have finished this season. Move to next season, episode 1.
                nextSeason = currentSeason + 1;
                nextEpisode = 1;

                // Check if next season exists in the data
                final nextSeasonData = seasons.firstWhere(
                  (s) => s['season_number'] == nextSeason,
                  orElse: () => null,
                );

                if (nextSeasonData == null) {
                  // No more seasons, user is caught up
                  nextSeason = null;
                  nextEpisode = null;
                }
              }
            } else {
              // Fallback
              nextSeason = 1;
              nextEpisode = 1;
            }
          }

          // Extract genres
          final genres =
              (details['genres'] as List?)
                  ?.map((g) => g['name'] as String)
                  .take(2)
                  .join(', ') ??
              '';

          // If it's a series and we have no next episode, don't show it
          if (!isMovie && (nextSeason == null || nextEpisode == null)) {
            return null;
          }

          return {
            'id': id,
            'title': details['title'] ?? details['name'] ?? 'No Title',
            'year':
                (details['release_date'] ??
                        details['first_air_date'] as String?)
                    ?.substring(0, 4) ??
                '',
            'image': 'https://image.tmdb.org/t/p/w200${details['poster_path']}',
            'description': details['overview'] ?? 'No description',
            'genre': genres.isNotEmpty
                ? genres
                : (isMovie ? 'Movie' : 'TV Series'),
            'is_movie': isMovie,
            'next_season': nextSeason,
            'next_episode': nextEpisode,
            'raw_item': item,
            'details': details,
          };
        } catch (e) {
          print('Error fetching details for item ${item['item_id']}: $e');
          // Fallback to Supabase data if TMDB fetch fails
          return {
            'id': item['item_id'],
            'title': item['title'] ?? 'No Title',
            'year': (item['release_date'] as String?)?.substring(0, 4) ?? '',
            'image': 'https://image.tmdb.org/t/p/w200${item['poster_path']}',
            'description': item['overview'] ?? 'No description',
            'genre': (item['item_type'] == 'tv' ? 'TV Series' : 'Movie'),
            'is_movie': item['item_type'] == 'movie',
            'raw_item': item,
          };
        }
      });

      final results = await Future.wait(futures);
      // Filter out nulls (caught up series)
      formattedList.addAll(results.whereType<Map<String, dynamic>>());

      if (mounted) {
        setState(() {
          _watchlist = formattedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching watchlist: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildIdCard(Map<String, dynamic> item) {
    return Dismissible(
      key: Key('watchlist_${item['id']}'),
      direction: DismissDirection.horizontal,
      // Swipe Left to Right (Start to End) -> Remove (Red)
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 30),
            SizedBox(height: 4),
            Text(
              'Remove',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      // Swipe Right to Left (End to Start) -> Mark Watched (Green)
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check, color: Colors.white, size: 30),
            SizedBox(height: 4),
            Text(
              'Mark Watched',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Remove from watchlist
          await SupabaseService.removeFromWatchlist(item['id']);
          Toast.show(
            context,
            'Removed ${item['title']} from watchlist',
            isError: true,
          );
          return true;
        } else {
          // Mark as watched
          if (item['is_movie'] == true) {
            await SupabaseService.addToWatched(
              item['details'] ?? item['raw_item'],
              true,
            );
            await SupabaseService.removeFromWatchlist(item['id']);

            Toast.show(context, 'Marked ${item['title']} as watched');
            return true;
          } else {
            final nextSeason = item['next_season'];
            final nextEpisode = item['next_episode'];

            if (nextSeason != null && nextEpisode != null) {
              await SupabaseService.updateWatchedProgress(
                item['id'],
                nextSeason,
                nextEpisode,
              );

              _fetchWatchlist();

              Toast.show(
                context,
                'Marked S${nextSeason} E${nextEpisode} as watched',
              );
            }
            return false;
          }
        }
      },
      child: GestureDetector(
        onTap: () async {
          if (item['is_movie'] == true) {
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
          _fetchWatchlist();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                child: Image.network(
                  item['image'],
                  width: 100,
                  height: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 100,
                    height: 140,
                    color: Colors.grey[800],
                    child: const Icon(Icons.error, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        item['title'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Year | Genre
                      Text(
                        '${item['year']} | ${item['genre']}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Description
                      Flexible(
                        child: Text(
                          item['description'],
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item['is_movie'] == false &&
                          item['next_season'] != null &&
                          item['next_episode'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Up Next: S${item['next_season']} E${item['next_episode']}',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter watchlist based on toggle
    final filteredList = _watchlist.where((item) {
      return item['is_movie'] == _isMovieMode;
    }).toList();

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Content
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : filteredList.isEmpty
              ? Center(
                  child: Text(
                    _isMovieMode
                        ? 'Your movie watchlist is empty'
                        : 'Your series watchlist is empty',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    180,
                    16,
                    100,
                  ), // Top padding for toggle + title
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final item = filteredList[index];
                    return _buildIdCard(item);
                  },
                ),

          // Title
          const Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'YOUR LIST',
                style: TextStyle(
                  fontFamily: 'BitcountGridSingle',
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Floating Toggle
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
        selectedIndex: 3, // List icon index
        onItemSelected: (index) {
          // Navigation is handled by FrostedNavBar internally
        },
      ),
    );
  }
}
