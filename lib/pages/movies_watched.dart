import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/toast.dart';
import 'movies.dart';

class MoviesWatchedPage extends StatefulWidget {
  const MoviesWatchedPage({Key? key}) : super(key: key);

  @override
  State<MoviesWatchedPage> createState() => _MoviesWatchedPageState();
}

class _MoviesWatchedPageState extends State<MoviesWatchedPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _watchedMovies = [];

  @override
  void initState() {
    super.initState();
    _fetchWatchedMovies();
  }

  Future<void> _fetchWatchedMovies() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.getWatched();

      // Filter for movies only
      final movieData = data
          .where((item) => item['item_type'] == 'movie')
          .toList();

      final List<Map<String, dynamic>> formattedList = [];

      // Fetch details for each item in parallel
      final futures = movieData.map((item) async {
        try {
          final int id = item['item_id'];
          final details = await _tmdbService.getMovieDetails(id);

          // Extract genres
          final genres =
              (details['genres'] as List?)
                  ?.map((g) => g['name'] as String)
                  .take(2)
                  .join(', ') ??
              '';

          return {
            'id': id,
            'title': details['title'] ?? 'No Title',
            'year': (details['release_date'] as String?)?.substring(0, 4) ?? '',
            'image': 'https://image.tmdb.org/t/p/w200${details['poster_path']}',
            'description': details['overview'] ?? 'No description',
            'genre': genres.isNotEmpty ? genres : 'Movie',
            'is_movie': true,
            'raw_item': item,
            'details': details,
            'watched_date': item['watched_date'],
            'rating': item['rating'],
          };
        } catch (e) {
          print('Error fetching details for movie ${item['item_id']}: $e');
          return {
            'id': item['item_id'],
            'title': item['title'] ?? 'No Title',
            'year': (item['release_date'] as String?)?.substring(0, 4) ?? '',
            'image': 'https://image.tmdb.org/t/p/w200${item['poster_path']}',
            'description': item['overview'] ?? 'No description',
            'genre': 'Movie',
            'is_movie': true,
            'raw_item': item,
            'watched_date': item['watched_date'],
            'rating': item['rating'],
          };
        }
      });

      final results = await Future.wait(futures);
      formattedList.addAll(results.whereType<Map<String, dynamic>>());

      if (mounted) {
        setState(() {
          _watchedMovies = formattedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching watched movies: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildMovieCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MoviePage(movieId: item['id']),
          ),
        );
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item['watched_date'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Watched: ${item['watched_date']}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movies Watched'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _watchedMovies.isEmpty
          ? const Center(
              child: Text(
                'No movies watched yet',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _watchedMovies.length,
              itemBuilder: (context, index) {
                final item = _watchedMovies[index];
                return _buildMovieCard(item);
              },
            ),
    );
  }
}
