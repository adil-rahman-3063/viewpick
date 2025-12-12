import 'package:flutter/material.dart';
import 'dart:async';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/frosted_card.dart';
import '../widget/nav_bar.dart';
import '../pages/movies.dart';
import '../pages/series.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({Key? key}) : super(key: key);

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final TMDBService _tmdbService = TMDBService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];

  // Search state
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounce;

  // Filter state
  bool _isFilterExpanded = false;
  String _selectedType = 'All'; // 'All', 'Movie', 'TV Series'

  // New Filter States
  RangeValues _selectedYearRange = const RangeValues(1950, 2025);
  final Set<int> _selectedGenreIds = {};
  final Set<int> _selectedProviderIds = {};

  // Data
  Map<int, String> _movieGenres = {};
  Map<int, String> _tvGenres = {};
  List<dynamic> _watchProviders = [];
  bool _genresLoaded = false;
  bool _providersLoaded = false;

  final Set<int> _addedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchGenres();
    _fetchProviders();
    _fetchMixedContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchGenres() async {
    try {
      final results = await Future.wait([
        _tmdbService.getGenreList(),
        _tmdbService.getTVGenreList(),
      ]);

      if (mounted) {
        setState(() {
          _movieGenres = results[0] as Map<int, String>;
          _tvGenres = results[1] as Map<int, String>;
          _genresLoaded = true;
        });
      }
    } catch (e) {
      print('Error fetching genres: $e');
    }
  }

  Future<void> _fetchProviders() async {
    // Helper to fetch with error swallowing
    Future<List<dynamic>> fetchSafe(String region) async {
      try {
        return await _tmdbService.getAvailableWatchProviders(
          watchRegion: region,
        );
      } catch (e) {
        print('Error fetching providers for $region: $e');
        return [];
      }
    }

    try {
      // Fetch for both IN and US to cover all requested services
      // We run them in parallel but handle errors individually so one failure doesn't kill all
      final results = await Future.wait([fetchSafe('IN'), fetchSafe('US')]);

      final allProviders = [...results[0], ...results[1]];

      if (allProviders.isEmpty) {
        print('No providers fetched from any region.');
        // Even if empty, we might want to set loaded to true so UI doesn't break?
        // But better to leave it false so we don't show empty section.
        return;
      }

      // Deduplicate by provider_id
      final uniqueProviders = <int, Map<String, dynamic>>{};
      for (var p in allProviders) {
        uniqueProviders[p['provider_id']] = p;
      }

      // Map of requested providers to their TMDB IDs
      final targetProviderIds = {
        8, // Netflix
        122, // Hotstar
        119, // Amazon Prime Video
        220, // JioCinema
        237, // Sony LIV
        232, // Zee5
        283, // Crunchyroll
        337, // Disney+
        15, // Hulu
        1899, // Max
        2, // Apple TV
        350, // Apple TV Plus
        257, // Fubo
        299, // Sling TV
        386, // Peacock
        531, // Paramount+
        73, // Tubi
        300, // Pluto TV
        319, // ALTBalaji
        309, // Sun NXT
        218, // Eros Now
        284, // MX Player
      };

      final filtered = uniqueProviders.values
          .where((p) => targetProviderIds.contains(p['provider_id']))
          .toList();

      if (mounted) {
        setState(() {
          _watchProviders = filtered;
          _providersLoaded = true;
        });
      }
    } catch (e) {
      print('Error in _fetchProviders: $e');
    }
  }

  Future<void> _fetchMixedContent() async {
    setState(() {
      _isLoading = true;
      _items.clear();
      _addedIds.clear();
    });

    try {
      final excludedIds = await SupabaseService.getExcludedIds();

      // If providers are selected, use DISCOVER API
      if (_selectedProviderIds.isNotEmpty) {
        await _fetchDiscoverContent(excludedIds);
      } else {
        // Otherwise use POPULAR/TRENDING mix
        await _fetchPopularTrendingContent(excludedIds);
      }
    } catch (e) {
      print('Error fetching explore content: $e');
      if (mounted && _items.isEmpty) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDiscoverContent(Set<int> excludedIds) async {
    final providerString = _selectedProviderIds.join('|'); // OR logic
    final genreString = _selectedGenreIds.isNotEmpty
        ? _selectedGenreIds.join('|')
        : null;
    final dateGte = '${_selectedYearRange.start.round()}-01-01';
    final dateLte = '${_selectedYearRange.end.round()}-12-31';

    // Fetch Movies and TV
    final results = await Future.wait([
      _tmdbService.discoverMovies(
        withWatchProviders: providerString,
        withGenres: genreString,
        releaseDateGte: dateGte,
        releaseDateLte: dateLte,
        page: 1,
      ),
      _tmdbService.discoverMovies(
        withWatchProviders: providerString,
        withGenres: genreString,
        releaseDateGte: dateGte,
        releaseDateLte: dateLte,
        page: 2,
      ),
      _tmdbService.discoverTV(
        withWatchProviders: providerString,
        withGenres: genreString,
        firstAirDateGte: dateGte,
        firstAirDateLte: dateLte,
        page: 1,
      ),
      _tmdbService.discoverTV(
        withWatchProviders: providerString,
        withGenres: genreString,
        firstAirDateGte: dateGte,
        firstAirDateLte: dateLte,
        page: 2,
      ),
    ]);

    await _processAndAddItems(results, excludedIds);
  }

  Future<void> _fetchPopularTrendingContent(Set<int> excludedIds) async {
    // Batch 1: Popular Page 1
    final batch1 = await Future.wait([
      _tmdbService.getPopularMovies(page: 1),
      _tmdbService.getPopularTV(page: 1),
    ]);
    await _processAndAddItems(batch1, excludedIds);

    // Batch 2: Trending
    final batch2 = await Future.wait([
      _tmdbService.getTrendingMovies(),
      _tmdbService.getTrendingTV(),
    ]);
    await _processAndAddItems(batch2, excludedIds);

    // Batch 3: Popular Page 2
    final batch3 = await Future.wait([
      _tmdbService.getPopularMovies(page: 2),
      _tmdbService.getPopularTV(page: 2),
    ]);
    await _processAndAddItems(batch3, excludedIds);

    // Batch 4: Popular Page 3 (ensure we reach 90)
    if (_items.length < 90) {
      final batch4 = await Future.wait([
        _tmdbService.getPopularMovies(page: 3),
        _tmdbService.getPopularTV(page: 3),
      ]);
      await _processAndAddItems(batch4, excludedIds);
    }
  }

  Future<void> _processAndAddItems(
    List<List<dynamic>> results,
    Set<int> excludedIds,
  ) async {
    final List<dynamic> newItems = [];
    for (var list in results) {
      newItems.addAll(list);
    }

    final filtered = newItems
        .where(
          (item) =>
              !excludedIds.contains(item['id']) &&
              !_addedIds.contains(item['id']),
        )
        .toList();

    for (var item in filtered) {
      _addedIds.add(item['id']);
    }

    filtered.shuffle();

    final formatted = filtered.map((item) => _formatItem(item)).toList();

    // Add row by row (3 items per row) for visual engagement
    for (var i = 0; i < formatted.length; i += 3) {
      if (!mounted) return;
      if (_items.length >= 90) break;

      final end = (i + 3 < formatted.length) ? i + 3 : formatted.length;
      final chunk = formatted.sublist(i, end);

      setState(() {
        _items.addAll(chunk);
        _isLoading = false;
      });

      // Short delay to create "row by row" loading effect
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> _formatItem(dynamic item) {
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.isNotEmpty ? releaseDate.substring(0, 4) : '';
    final type = item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv');

    return {
      'id': item['id'],
      'title': name,
      'year': year,
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
      'type': type,
      'description': item['overview'] ?? 'No description',
      'genre_ids': item['genre_ids'],
    };
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isEmpty) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
        return;
      }
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    try {
      final results = await _tmdbService.searchMulti(query);
      final formatted = results
          .where(
            (item) =>
                item['media_type'] == 'movie' || item['media_type'] == 'tv',
          )
          .map((item) => _formatItem(item))
          .toList();

      setState(() {
        _searchResults = formatted;
        _isSearching = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error searching: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((item) {
      // 1. Type Filter
      if (_selectedType == 'Movie' && item['type'] != 'movie') return false;
      if (_selectedType == 'TV Series' && item['type'] != 'tv') return false;

      // 2. Year Filter (Only apply if NOT fetching discover content, or apply anyway as safety)
      // If we used discover API, year is already filtered. But applying it here doesn't hurt.
      final int? year = int.tryParse(item['year']);
      if (year != null) {
        if (year < _selectedYearRange.start || year > _selectedYearRange.end) {
          return false;
        }
      }

      // 3. Genre Filter (Only apply if NOT fetching discover content)
      // If we used discover API, genre is already filtered.
      // However, if we are in "Popular" mode, we need to filter client-side.
      if (_selectedProviderIds.isEmpty && _selectedGenreIds.isNotEmpty) {
        final itemGenres = item['genre_ids'] as List<dynamic>?;
        if (itemGenres == null || itemGenres.isEmpty) return false;

        bool hasGenre = false;
        for (var id in itemGenres) {
          if (_selectedGenreIds.contains(id)) {
            hasGenre = true;
            break;
          }
        }
        if (!hasGenre) return false;
      }

      return true;
    }).toList();
  }

  Widget _buildSearchResultCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () {
        if (item['type'] == 'movie') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MoviePage(movieId: item['id']),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SeriesPage(tvId: item['id']),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.error,
                    color: Theme.of(context).colorScheme.error,
                  ),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Year | Type
                    Text(
                      '${item['year']} | ${item['type'] == 'movie' ? 'Movie' : 'TV Series'}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Description
                    Flexible(
                      child: Text(
                        item['description'],
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedType == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildGenreChip(int id, String label) {
    final isSelected = _selectedGenreIds.contains(id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedGenreIds.remove(id);
          } else {
            _selectedGenreIds.add(id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildProviderChip(Map<String, dynamic> provider) {
    final id = provider['provider_id'];
    final name = provider['provider_name'];
    final logoPath = provider['logo_path'];
    final isSelected = _selectedProviderIds.contains(id);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedProviderIds.remove(id);
          } else {
            _selectedProviderIds.add(id);
          }
          // Re-fetch content when provider changes
          _fetchMixedContent();
        });
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: logoPath != null
              ? Image.network(
                  'https://image.tmdb.org/t/p/original$logoPath',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Center(child: Icon(Icons.tv, size: 24)),
                )
              : Center(
                  child: Text(
                    name[0],
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          // VIEWPICK Title
          Padding(
            padding: const EdgeInsets.only(top: 50.0, bottom: 20.0),
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
          // Search bar and Filter Button
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search movies and series...',
                      hintStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isFilterExpanded = !_isFilterExpanded;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isFilterExpanded
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isFilterExpanded
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      color: _isFilterExpanded
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter Options Panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: _isFilterExpanded
                ? 350 // Adjusted height
                : 0,
            curve: Curves.easeInOutCubic,
            child: ClipRect(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type Filter
                      Row(
                        children: [
                          _buildFilterChip('All'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Movie'),
                          const SizedBox(width: 8),
                          _buildFilterChip('TV Series'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedType = 'All';
                                _selectedYearRange = const RangeValues(
                                  1950,
                                  2025,
                                );
                                _selectedGenreIds.clear();
                                _selectedProviderIds.clear();
                              });
                              _fetchMixedContent();
                            },
                            icon: Icon(
                              Icons.clear_all_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            label: Text(
                              'Clear',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.errorContainer.withOpacity(0.2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Streaming Services Filter
                      if (_providersLoaded) ...[
                        Text(
                          'Streaming Services',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _watchProviders
                                .map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: _buildProviderChip(p),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Year Range Filter
                      Text(
                        'Year Range: ${_selectedYearRange.start.round()} - ${_selectedYearRange.end.round()}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      RangeSlider(
                        values: _selectedYearRange,
                        min: 1950,
                        max: 2025,
                        divisions: 75,
                        labels: RangeLabels(
                          _selectedYearRange.start.round().toString(),
                          _selectedYearRange.end.round().toString(),
                        ),
                        onChanged: (RangeValues values) {
                          setState(() {
                            _selectedYearRange = values;
                          });
                        },
                      ),

                      // Genre Filter
                      if (_genresLoaded) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Genres',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._movieGenres.entries
                                .take(8)
                                .map((e) => _buildGenreChip(e.key, e.value)),
                            // Combine a few TV genres if needed or just show common ones
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Grid view
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollNotification) {
                if (scrollNotification is ScrollStartNotification) {
                  if (_isFilterExpanded) {
                    setState(() {
                      _isFilterExpanded = false;
                    });
                  }
                }
                return false;
              },
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : _items.isEmpty && !_isSearching
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load content',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _fetchMixedContent();
                              if (!_genresLoaded) _fetchGenres();
                              if (!_providersLoaded) _fetchProviders();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _isSearching
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 100.0),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        return _buildSearchResultCard(_searchResults[index]);
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        16.0,
                        0,
                        16.0,
                        100.0,
                      ), // Added bottom padding for nav bar
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.5,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        return GestureDetector(
                          onTap: () {
                            if (item['type'] == 'movie') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      MoviePage(movieId: item['id']),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SeriesPage(tvId: item['id']),
                                ),
                              );
                            }
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
          ),
        ],
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 2, // Explore icon is selected
        onItemSelected: (index) {
          // Navigation is handled by FrostedNavBar internally
        },
      ),
    );
  }
}
