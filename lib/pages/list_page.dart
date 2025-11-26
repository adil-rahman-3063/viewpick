import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';

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
          if (isMovie) {
            details = await _tmdbService.getMovieDetails(id);
          } else {
            details = await _tmdbService.getTVDetails(id);
          }

          // Extract genres
          final genres =
              (details['genres'] as List?)
                  ?.map((g) => g['name'] as String)
                  .take(2) // Take first 2 genres
                  .join(', ') ??
              '';

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
          };
        }
      });

      final results = await Future.wait(futures);
      formattedList.addAll(results);

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
    return GestureDetector(
      onTap: () {
        if (item['is_movie'] == true) {
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
                    Expanded(
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
