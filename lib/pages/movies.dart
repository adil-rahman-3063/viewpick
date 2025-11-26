import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';

class MoviePage extends StatefulWidget {
  final int movieId;

  const MoviePage({Key? key, required this.movieId}) : super(key: key);

  @override
  State<MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends State<MoviePage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  Map<String, dynamic>? _movieDetails;
  List<dynamic> _videos = [];
  Map<String, dynamic>? _providers;
  bool _isInWatchlist = false;
  bool _isLiked = false; // Tracks if the user has liked this genre/movie
  YoutubePlayerController? _youtubeController;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final details = await _tmdbService.getMovieDetails(widget.movieId);
      final videos = await _tmdbService.getMovieVideos(widget.movieId);
      final providers = await _tmdbService.getWatchProviders(
        widget.movieId,
        true,
      );
      final inWatchlist = await SupabaseService.isInWatchlist(widget.movieId);

      // Check if user has liked any genre of this movie (approximation for "Liked")
      // Since we don't have a specific "Liked Movies" table for items yet, we use genres.
      // But for UI feedback, we can just toggle the local state for now or check genres.
      // For now, let's just default to false and allow "liking" to add genres.

      String? trailerId;
      // Find the first official trailer on YouTube
      final trailer = videos.firstWhere(
        (v) => v['site'] == 'YouTube' && v['type'] == 'Trailer',
        orElse: () => null,
      );

      if (trailer != null) {
        trailerId = trailer['key'];
      } else if (videos.isNotEmpty && videos.first['site'] == 'YouTube') {
        // Fallback to any YouTube video
        trailerId = videos.first['key'];
      }

      if (trailerId != null) {
        _youtubeController = YoutubePlayerController(
          initialVideoId: trailerId,
          flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
        );
      }

      if (mounted) {
        setState(() {
          _movieDetails = details;
          _videos = videos;
          _providers = providers;
          _isInWatchlist = inWatchlist;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching movie data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleWatchlist() async {
    if (_movieDetails == null) return;

    setState(() => _isInWatchlist = !_isInWatchlist); // Optimistic update

    try {
      if (_isInWatchlist) {
        await SupabaseService.addToWatchlist(_movieDetails!, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to Watchlist'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await SupabaseService.removeFromWatchlist(widget.movieId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from Watchlist'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Revert on error
      setState(() => _isInWatchlist = !_isInWatchlist);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleLike() async {
    if (_movieDetails == null) return;

    // Since we only support adding genres, we'll just do that for now.
    // And show a visual feedback.
    setState(() => _isLiked = true);

    final genres = (_movieDetails!['genres'] as List)
        .map((g) => g['name'])
        .join(',');

    await SupabaseService.addLikedMovieGenres(genres);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to your interests'),
        backgroundColor: Colors.pink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_movieDetails == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(
          child: Text(
            'Failed to load movie',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final posterPath = _movieDetails!['poster_path'];
    final backdropPath = _movieDetails!['backdrop_path'];
    final title = _movieDetails!['title'];
    final overview = _movieDetails!['overview'];
    final releaseDate = _movieDetails!['release_date'] ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
    final rating =
        (_movieDetails!['vote_average'] as num?)?.toStringAsFixed(1) ?? 'N/A';
    final genres = (_movieDetails!['genres'] as List)
        .map((g) => g['name'])
        .join(', ');

    // Get providers for US (or default to first available)
    final usProviders = _providers?['US'] ?? _providers?.values.firstOrNull;
    final flatrate = usProviders?['flatrate'] as List?;
    final rent = usProviders?['rent'] as List?;
    final buy = usProviders?['buy'] as List?;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Trailer or Poster
            if (_youtubeController != null)
              Container(
                height: 250,
                width: double.infinity,
                color: Colors.black, // Keep black for video player
                child: YoutubePlayer(
                  controller: _youtubeController!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: Colors.red,
                  progressColors: const ProgressBarColors(
                    playedColor: Colors.red,
                    handleColor: Colors.redAccent,
                  ),
                ),
              )
            else
              Container(
                height: 400,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      'https://image.tmdb.org/t/p/w500${backdropPath ?? posterPath}',
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        backgroundColor.withOpacity(0.8),
                        backgroundColor,
                      ],
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Year
                  Text(
                    '$title ($year)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'BitcountGridSingle',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Rating and Genres
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        rating,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          genres,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _buildFrostedButton(
                          icon: _isInWatchlist ? Icons.check : Icons.add,
                          label: _isInWatchlist
                              ? 'In Watchlist'
                              : 'Add to Watchlist',
                          onTap: _toggleWatchlist,
                          isActive: _isInWatchlist,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFrostedButton(
                          icon: _isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          label: 'Like',
                          onTap: _toggleLike,
                          isActive: _isLiked,
                          activeColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Overview
                  const Text(
                    'Overview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overview ?? 'No description available.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Where to Watch
                  if (flatrate != null && flatrate.isNotEmpty) ...[
                    const Text(
                      'Stream On',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: flatrate.map((provider) {
                        return Tooltip(
                          message: provider['provider_name'],
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              'https://image.tmdb.org/t/p/original${provider['logo_path']}',
                              width: 50,
                              height: 50,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (rent != null && rent.isNotEmpty) ...[
                    const Text(
                      'Rent',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: rent.map((provider) {
                        return Tooltip(
                          message: provider['provider_name'],
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              'https://image.tmdb.org/t/p/original${provider['logo_path']}',
                              width: 50,
                              height: 50,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrostedButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color activeColor = Colors.white,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? Colors.white.withOpacity(0.5)
                  : Colors.white.withOpacity(0.2),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: isActive ? activeColor : Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
