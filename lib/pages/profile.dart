import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/tmdb_service.dart';
import '../widget/nav_bar.dart';
import '../widget/toast.dart';
import 'settings.dart';
import 'movies_watched.dart';
import 'series_watched.dart';
import '../main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TMDBService _tmdbService = TMDBService();

  String _name = 'User';
  String _email = '';
  String? _avatarUrl;

  int _watchlistMovies = 0;
  int _watchlistSeries = 0;
  int _watchedMovies = 0;
  int _watchedSeries = 0;

  Duration _totalMovieTime = Duration.zero;
  Duration _totalSeriesTime = Duration.zero;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    setState(() => _isLoading = true);
    try {
      final user = SupabaseService.currentUser();
      if (user != null) {
        _email = user.email ?? '';
        _name = user.userMetadata?['name'] ?? 'User';
        _avatarUrl = user.userMetadata?['avatar_url'];
      }

      final watchlist = await SupabaseService.getWatchlist();
      final watched = await SupabaseService.getWatched();

      _watchlistMovies = watchlist
          .where((i) => i['item_type'] == 'movie')
          .length;
      _watchlistSeries = watchlist.where((i) => i['item_type'] == 'tv').length;

      final watchedMoviesList = watched
          .where((i) => i['item_type'] == 'movie')
          .toList();
      final watchedSeriesList = watched
          .where((i) => i['item_type'] == 'tv')
          .toList();

      _watchedMovies = watchedMoviesList.length;
      _watchedSeries = watchedSeriesList.length;

      // Check for cached stats
      final movieMins = user?.userMetadata?['total_movie_minutes'];
      final seriesMins = user?.userMetadata?['total_series_minutes'];

      if (movieMins != null && seriesMins != null) {
        _totalMovieTime = Duration(minutes: movieMins as int);
        _totalSeriesTime = Duration(minutes: seriesMins as int);
      } else {
        // Calculate stats in background and save them
        _calculateAndSaveStats(watchedMoviesList, watchedSeriesList);
      }
    } catch (e) {
      print('Error fetching profile data: $e');
      if (mounted) {
        Toast.show(context, 'Error loading profile', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _calculateAndSaveStats(
    List<Map<String, dynamic>> movies,
    List<Map<String, dynamic>> series,
  ) async {
    int totalMovieMinutes = 0;
    int totalSeriesMinutes = 0;

    // Calculate Movie Time
    for (var movie in movies) {
      try {
        final details = await _tmdbService.getMovieDetails(movie['item_id']);
        final runtime = details['runtime'] as int?;
        if (runtime != null) {
          totalMovieMinutes += runtime;
        }
      } catch (e) {
        print('Error fetching movie details for stats: $e');
      }
    }

    // Calculate Series Time
    for (var show in series) {
      try {
        final details = await _tmdbService.getTVDetails(show['item_id']);
        final seasons = details['seasons'] as List<dynamic>;
        final runtimes = details['episode_run_time'] as List<dynamic>?;

        // Calculate average runtime
        int avgRuntime = 45; // Default fallback
        if (runtimes != null && runtimes.isNotEmpty) {
          final sum = runtimes.fold<int>(0, (p, c) => p + (c as int));
          avgRuntime = (sum / runtimes.length).round();
        }

        final watchedSeason = show['watched_season'] as int? ?? 0;
        final watchedEpisode = show['watched_episode'] as int? ?? 0;

        int episodesWatched = 0;

        for (var season in seasons) {
          final sNum = season['season_number'] as int;
          final epCount = season['episode_count'] as int;

          if (sNum < watchedSeason && sNum > 0) {
            episodesWatched += epCount;
          } else if (sNum == watchedSeason) {
            episodesWatched += watchedEpisode;
          }
        }

        totalSeriesMinutes += episodesWatched * avgRuntime;
      } catch (e) {
        print('Error fetching series details for stats: $e');
      }
    }

    if (mounted) {
      setState(() {
        _totalMovieTime = Duration(minutes: totalMovieMinutes);
        _totalSeriesTime = Duration(minutes: totalSeriesMinutes);
      });
    }

    // Save to Supabase metadata for future fast loading
    try {
      await SupabaseService.updateUserMetadata({
        'total_movie_minutes': totalMovieMinutes,
        'total_series_minutes': totalSeriesMinutes,
      });
    } catch (e) {
      print('Error saving stats to metadata: $e');
    }
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '0m';

    final years = duration.inDays ~/ 365;
    final remainingDaysAfterYears = duration.inDays % 365;
    final months = remainingDaysAfterYears ~/ 30;
    final days = remainingDaysAfterYears % 30;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    List<String> parts = [];
    if (years > 0) parts.add('${years}y');
    if (months > 0) parts.add('${months}m');
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}min');

    if (parts.isEmpty) return '0min';
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      // Removed backgroundColor and background gradient Container
      body: SafeArea(
        bottom: false, // Allow content to go behind navbar
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 120.0),
          child: Column(
            children: [
              // Header Section
              Stack(
                alignment: Alignment.center,
                children: [
                  // Settings & Theme Icons (Top Right)
                  Align(
                    alignment: Alignment.topRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: themeNotifier,
                          builder: (context, currentMode, child) {
                            final isDark = currentMode == ThemeMode.dark;
                            return IconButton(
                              icon: Icon(
                                isDark ? Icons.dark_mode : Icons.light_mode,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              onPressed: () {
                                themeNotifier.value = isDark
                                    ? ThemeMode.light
                                    : ThemeMode.dark;
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.settings,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingsPage(),
                              ),
                            ).then(
                              (_) => _fetchProfileData(),
                            ); // Refresh data on return
                          },
                        ),
                      ],
                    ),
                  ),

                  // Profile Info
                  Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.shadow.withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          backgroundImage: _avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: _avatarUrl == null
                              ? Text(
                                  _name.isNotEmpty
                                      ? _name[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'BitcountGridSingle',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _email,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Stats Grid
              if (_isLoading)
                Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              else
                Column(
                  children: [
                    // Row 1: Movies
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Movies Watchlist',
                            value: _watchlistMovies.toString(),
                            icon: Icons.bookmark_border,
                            color: Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MoviesWatchedPage(),
                                ),
                              ).then((_) => _fetchProfileData());
                            },
                            child: _buildStatCard(
                              title: 'Movies Watched',
                              value: _watchedMovies.toString(),
                              icon: Icons.movie_outlined,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 2: Series
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Series Watchlist',
                            value: _watchlistSeries.toString(),
                            icon: Icons.playlist_play,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SeriesWatchedPage(),
                                ),
                              ).then((_) => _fetchProfileData());
                            },
                            child: _buildStatCard(
                              title: 'Series Watched',
                              value: _watchedSeries.toString(),
                              icon: Icons.tv,
                              color: Colors.purpleAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 3: Watch Time
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Movie Time',
                            value: _formatDuration(_totalMovieTime),
                            icon: Icons.timer,
                            color: Colors.cyanAccent,
                            isSmallText: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Series Time',
                            value: _formatDuration(_totalSeriesTime),
                            icon: Icons.history,
                            color: Colors.pinkAccent,
                            isSmallText: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

              const SizedBox(height: 40),

              // Sign Out Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await SupabaseService.signOut();
                    if (mounted) {
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onErrorContainer,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withOpacity(0.5),
                      ),
                    ),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 4,
        onItemSelected: (index) {
          if (index == 4) return;
          FrostedNavBar.handleNavigation(context, index);
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isSmallText = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 140, // Square-ish shape
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 12),
              Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: isSmallText ? 16 : 28,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
