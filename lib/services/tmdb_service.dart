import 'dart:convert';
import 'package:http/http.dart' as http;

class TMDBService {
  final String _baseUrl = 'https://tmdb-proxy-sz5v.onrender.com';

  Future<List<dynamic>> getPopularMovies({
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/movies/popular?language=$language&page=$page'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load popular movies');
    }
  }

  Future<List<dynamic>> getMoviesByGenre(
    int genreId, {
    String language = 'en-US',
    int page = 1,
    String? withOriginalLanguage,
  }) async {
    String url =
        '$_baseUrl/discover/movie?with_genres=$genreId&language=$language&page=$page';
    if (withOriginalLanguage != null) {
      url += '&with_original_language=$withOriginalLanguage';
    }
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load movies by genre');
    }
  }

  Future<Map<int, String>> getGenreList() async {
    final response = await http.get(Uri.parse('$_baseUrl/genre/movie/list'));
    if (response.statusCode == 200) {
      final genres = json.decode(response.body)['genres'] as List<dynamic>;
      return {for (var genre in genres) genre['id']: genre['name']};
    } else {
      throw Exception('Failed to load genre list');
    }
  }

  Future<List<dynamic>> getMoviesByOriginalLanguage(
    String languageCode, {
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$_baseUrl/discover/movie?with_original_language=$languageCode&language=$language&sort_by=popularity.desc&page=$page',
      ),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load movies by language');
    }
  }

  Future<Map<String, dynamic>> getMovieDetails(
    int movieId, {
    String language = 'en-US',
  }) async {
    final url = '$_baseUrl/movie/$movieId?language=$language';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) {
        throw Exception(
          data['status_message'] ?? 'Failed to load movie details',
        );
      }
      return data;
    } else {
      throw Exception('Failed to load movie details: ${response.statusCode}');
    }
  }

  // TV Series methods
  Future<List<dynamic>> getPopularTV({
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/tv/popular?language=$language&page=$page'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load popular TV series');
    }
  }

  Future<List<dynamic>> getTVByGenre(
    int genreId, {
    String language = 'en-US',
    int page = 1,
    String? withOriginalLanguage,
  }) async {
    String url =
        '$_baseUrl/discover/tv?with_genres=$genreId&language=$language&page=$page';
    if (withOriginalLanguage != null) {
      url += '&with_original_language=$withOriginalLanguage';
    }
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load TV series by genre');
    }
  }

  Future<Map<int, String>> getTVGenreList() async {
    final response = await http.get(Uri.parse('$_baseUrl/genre/tv/list'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final genres = data['genres'] as List<dynamic>? ?? [];
      return {for (var genre in genres) genre['id']: genre['name']};
    } else {
      throw Exception('Failed to load TV genre list');
    }
  }

  Future<List<dynamic>> getTVByOriginalLanguage(
    String languageCode, {
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$_baseUrl/discover/tv?with_original_language=$languageCode&language=$language&sort_by=popularity.desc&page=$page',
      ),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load TV series by language');
    }
  }

  Future<Map<String, dynamic>> getTVDetails(
    int tvId, {
    String language = 'en-US',
  }) async {
    final url = '$_baseUrl/tv/$tvId?language=$language';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) {
        throw Exception(data['status_message'] ?? 'Failed to load TV details');
      }
      return data;
    } else {
      print(
        'Failed to load TV details. URL: $url, Status: ${response.statusCode}, Body: ${response.body}',
      );
      throw Exception('Failed to load TV details: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getSeasonDetails(
    int tvId,
    int seasonNumber, {
    String language = 'en-US',
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/tv/$tvId/season/$seasonNumber?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) {
        throw Exception(
          data['status_message'] ?? 'Failed to load season details',
        );
      }
      return data;
    } else {
      throw Exception('Failed to load season details');
    }
  }

  // Trending and newly released methods
  Future<List<dynamic>> getTrendingMovies({String language = 'en-US'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/trending/movie?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load trending movies');
    }
  }

  Future<List<dynamic>> getTrendingTV({String language = 'en-US'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/trending/tv?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load trending TV');
    }
  }

  Future<List<dynamic>> getNowPlayingMovies({String language = 'en-US'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/movie/now-playing?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load now playing movies');
    }
  }

  Future<List<dynamic>> getOnTheAirTV({String language = 'en-US'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/tv/on-the-air?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load on-air TV');
    }
  }

  Future<List<dynamic>> getMovieVideos(
    int movieId, {
    String language = 'en-US',
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/movie/$movieId/videos?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      // Return empty list instead of throwing for auxiliary data
      return [];
    }
  }

  Future<List<dynamic>> getTVVideos(
    int tvId, {
    String language = 'en-US',
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/tv/$tvId/videos?language=$language'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getWatchProviders(int id, bool isMovie) async {
    final type = isMovie ? 'movie' : 'tv';
    final response = await http.get(
      Uri.parse('$_baseUrl/$type/$id/watch/providers'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'];
    } else {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getMovieCredits(int movieId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/movie/$movieId/credits'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) return null;
      return data;
    } else {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTVCredits(int tvId) async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/$tvId/credits'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) return null;
      return data;
    } else {
      return null;
    }
  }

  Future<List<dynamic>> searchMulti(
    String query, {
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$_baseUrl/search/multi?query=$query&language=$language&page=$page',
      ),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to search');
    }
  }
}
