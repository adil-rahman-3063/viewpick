import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';

class SeriesPage extends StatefulWidget {
  final int tvId;

  const SeriesPage({Key? key, required this.tvId}) : super(key: key);

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  Map<String, dynamic>? _tvDetails;
  Map<String, dynamic>? _providers;
  List<dynamic>? _cast;
  bool _isInWatchlist = false;
  bool _isLiked = false;

  // New state for watched progress
  int? _watchedSeason;
  int? _watchedEpisode;
  bool _isUpdatingWatched = false;

  YoutubePlayerController? _youtubeController;
  final Map<int, List<dynamic>> _seasonEpisodes = {};

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
      final details = await _tmdbService.getTVDetails(widget.tvId);

      List<dynamic> videos = [];
      try {
        videos = await _tmdbService.getTVVideos(widget.tvId);
      } catch (e) {
        print('Error fetching videos: $e');
      }

      Map<String, dynamic>? providers;
      try {
        providers = await _tmdbService.getWatchProviders(widget.tvId, false);
      } catch (e) {
        print('Error fetching providers: $e');
      }

      Map<String, dynamic>? credits;
      try {
        credits = await _tmdbService.getTVCredits(widget.tvId);
      } catch (e) {
        print('Error fetching credits: $e');
      }

      final inWatchlist = await SupabaseService.isInWatchlist(widget.tvId);

      // Fetch watched status
      final watchedItem = await SupabaseService.getWatchedItem(widget.tvId);
      int? wSeason;
      int? wEpisode;

      if (watchedItem != null) {
        wSeason = watchedItem['watched_season'];
        wEpisode = watchedItem['watched_episode'];
      }

      String? trailerId;
      final trailer = videos.firstWhere(
        (v) => v['site'] == 'YouTube' && v['type'] == 'Trailer',
        orElse: () => null,
      );

      if (trailer != null) {
        trailerId = trailer['key'];
      } else if (videos.isNotEmpty && videos.first['site'] == 'YouTube') {
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
          _tvDetails = details;
          _providers = providers;
          _cast = credits?['cast'];
          _isInWatchlist = inWatchlist;
          _watchedSeason = wSeason;
          _watchedEpisode = wEpisode;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching TV data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSeasonDetails(int seasonNumber) async {
    if (_seasonEpisodes.containsKey(seasonNumber)) return;

    try {
      final seasonData = await _tmdbService.getSeasonDetails(
        widget.tvId,
        seasonNumber,
      );
      if (mounted) {
        setState(() {
          _seasonEpisodes[seasonNumber] = seasonData['episodes'];
        });
      }
    } catch (e) {
      print('Error fetching season $seasonNumber: $e');
    }
  }

  Future<void> _toggleWatchlist() async {
    if (_tvDetails == null) return;

    try {
      if (_isInWatchlist) {
        // If in watchlist, "Mark Watched" logic (Mark entire series)
        await SupabaseService.markSeriesAsWatched(_tvDetails!, _tvDetails!);
        await SupabaseService.removeFromWatchlist(widget.tvId);

        setState(() => _isInWatchlist = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marked series as watched'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // If not in watchlist, "Add to Watchlist" logic
        await SupabaseService.addToWatchlist(_tvDetails!, false);
        setState(() => _isInWatchlist = true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to Watchlist'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleLike() async {
    if (_tvDetails == null) return;

    setState(() => _isLiked = true);

    final genres = (_tvDetails!['genres'] as List)
        .map((g) => g['name'])
        .join(',');

    await SupabaseService.addLikedTVGenres(genres);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added to your interests'),
        backgroundColor: Colors.pink,
      ),
    );
  }

  Future<void> _updateProgress(int seasonNumber, int episodeNumber) async {
    if (_isUpdatingWatched) return;
    setState(() => _isUpdatingWatched = true);

    final oldSeason = _watchedSeason;
    final oldEpisode = _watchedEpisode;

    // Optimistic update
    setState(() {
      _watchedSeason = seasonNumber;
      _watchedEpisode = episodeNumber;
    });

    try {
      // Ensure it's in the watched table first (if not already)
      final isWatched = await SupabaseService.isWatched(widget.tvId);
      if (!isWatched && _tvDetails != null) {
        await SupabaseService.addToWatched(
          _tvDetails!,
          false,
          watchedSeason: seasonNumber,
          watchedEpisode: episodeNumber,
        );
      } else {
        await SupabaseService.updateWatchedProgress(
          widget.tvId,
          seasonNumber,
          episodeNumber,
        );
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _watchedSeason = oldSeason;
        _watchedEpisode = oldEpisode;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating progress: $e')));
    } finally {
      if (mounted) setState(() => _isUpdatingWatched = false);
    }
  }

  bool _isEpisodeWatched(int season, int episode) {
    if (_watchedSeason == null || _watchedEpisode == null) return false;
    if (season < _watchedSeason!) return true;
    if (season == _watchedSeason! && episode <= _watchedEpisode!) return true;
    return false;
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

    if (_tvDetails == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(
          child: Text(
            'Failed to load series',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final posterPath = _tvDetails!['poster_path'];
    final backdropPath = _tvDetails!['backdrop_path'];
    final title = _tvDetails!['name'];
    final overview = _tvDetails!['overview'];
    final firstAirDate = _tvDetails!['first_air_date'] ?? '';
    final year = firstAirDate.length >= 4 ? firstAirDate.substring(0, 4) : '';
    final rating =
        (_tvDetails!['vote_average'] as num?)?.toStringAsFixed(1) ?? 'N/A';
    final genres = (_tvDetails!['genres'] as List)
        .map((g) => g['name'])
        .join(', ');
    final numberOfSeasons = _tvDetails!['number_of_seasons'];
    final seasons = _tvDetails!['seasons'] as List;

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
            if (_youtubeController != null)
              Container(
                height: 250,
                width: double.infinity,
                color: Colors.black,
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
                      Text(
                        '$numberOfSeasons Seasons',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
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

                  Row(
                    children: [
                      Expanded(
                        child: _buildFrostedButton(
                          icon: _isInWatchlist
                              ? Icons.check_circle_outline
                              : Icons.add,
                          label: _isInWatchlist ? 'Mark Watched' : 'Watchlist',
                          onTap: _toggleWatchlist,
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
                    const SizedBox(height: 24),
                  ],

                  if (buy != null && buy.isNotEmpty) ...[
                    const Text(
                      'Buy',
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
                      children: buy.map((provider) {
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

                  if (_cast != null && _cast!.isNotEmpty) ...[
                    const Text(
                      'Cast',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _cast!.length,
                        itemBuilder: (context, index) {
                          final actor = _cast![index];
                          final profilePath = actor['profile_path'];
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[800],
                                    child: profilePath != null
                                        ? Image.network(
                                            'https://image.tmdb.org/t/p/w200$profilePath',
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                                  Icons.person,
                                                  color: Colors.white,
                                                ),
                                          )
                                        : const Icon(
                                            Icons.person,
                                            color: Colors.white,
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  actor['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  actor['character'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  const Text(
                    'Seasons',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...seasons.map((season) {
                    final seasonNum = season['season_number'];
                    final episodeCount = season['episode_count'];
                    final episodes = _seasonEpisodes[seasonNum];

                    return Card(
                      color: Colors.white.withOpacity(0.05),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: ExpansionTile(
                        title: Text(
                          season['name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '$episodeCount Episodes',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        iconColor: Colors.white,
                        collapsedIconColor: Colors.white60,
                        onExpansionChanged: (expanded) {
                          if (expanded) {
                            _fetchSeasonDetails(seasonNum);
                          }
                        },
                        children: [
                          if (episodes == null)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            )
                          else
                            ...episodes.map<Widget>((episode) {
                              final epNum = episode['episode_number'];
                              final isWatched = _isEpisodeWatched(
                                seasonNum,
                                epNum,
                              );

                              return Dismissible(
                                key: Key('S${seasonNum}E$epNum'),
                                background: Container(
                                  color: Colors.green,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                  ),
                                ),
                                secondaryBackground: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                ),
                                confirmDismiss: (direction) async {
                                  if (direction ==
                                      DismissDirection.startToEnd) {
                                    // Mark as watched (and previous)
                                    await _updateProgress(seasonNum, epNum);
                                    return false; // Don't dismiss the tile
                                  } else {
                                    // Swipe left - maybe unmark?
                                    // For now, let's just treat it as unmark current?
                                    // Or maybe just do nothing for now as per plan
                                    return false;
                                  }
                                },
                                child: ListTile(
                                  title: Text(
                                    '${episode['episode_number']}. ${episode['name']}',
                                    style: TextStyle(
                                      color: isWatched
                                          ? Colors.greenAccent
                                          : Colors.white,
                                      fontWeight: isWatched
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (episode['overview'] != null &&
                                          episode['overview'].isNotEmpty)
                                        Text(
                                          episode['overview'],
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      isWatched
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: isWatched
                                          ? Colors.green
                                          : Colors.white54,
                                    ),
                                    onPressed: () =>
                                        _updateProgress(seasonNum, epNum),
                                  ),
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 40),
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
