import 'package:flutter/material.dart';
import 'dart:async';
import '../services/tmdb_service.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchMixedContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchMixedContent() async {
    setState(() => _isLoading = true);

    try {
      // Fetch both movies and TV series
      final allSections = await Future.wait([
        _tmdbService.getPopularMovies(),
        _tmdbService.getPopularTV(),
        _tmdbService.getTrendingMovies(),
        _tmdbService.getTrendingTV(),
      ]);

      // Combine and shuffle all items
      final List<dynamic> allItems = [];
      allItems.addAll(allSections[0]);
      allItems.addAll(allSections[1]);
      allItems.addAll(allSections[2]);
      allItems.addAll(allSections[3]);

      // Shuffle randomly
      allItems.shuffle();

      // Take 30 items (10 rows x 3 cards)
      final formattedItems = allItems
          .take(30)
          .map((item) => _formatItem(item))
          .toList();

      setState(() {
        _items = formattedItems;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching explore content: $e');
      setState(() => _isLoading = false);
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
          // Search bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
          const SizedBox(height: 16),
          // Grid view
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
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
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
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
