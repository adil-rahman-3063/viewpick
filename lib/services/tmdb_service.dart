import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TMDBService {
  final String _baseUrl = 'https://api.themoviedb.org/3';
  final String _apiKey =
      dotenv.env['TMDB_API_KEY'] ?? 'a92961c9d1ffb10b5688204638171d0d';

  Future<http.Response> _get(String url, {int retries = 3}) async {
    print('TMDBService: Requesting $url');

    // Append API key
    final uri = Uri.parse(url);
    final newUri = uri.replace(
      queryParameters: {...uri.queryParameters, 'api_key': _apiKey},
    );

    int attempt = 0;
    while (attempt < retries) {
      try {
        final response = await http
            .get(newUri)
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          return response;
        } else if (response.statusCode == 429) {
          // Rate limit hit, wait and retry
          print('TMDBService: Rate limit hit, waiting...');
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        } else {
          print('TMDBService: Response status: ${response.statusCode}');
          print('TMDBService: Response body: ${response.body}');
          print('TMDBService: Request failed for $url');
          // Don't retry on 4xx errors other than 429
          if (response.statusCode >= 400 && response.statusCode < 500) {
            return response;
          }
        }
      } catch (e) {
        print(
          'TMDBService: Error making request (Attempt ${attempt + 1}/$retries): $e',
        );
        if (attempt == retries - 1) rethrow;
        // Wait before retrying
        await Future.delayed(Duration(seconds: 1 * (attempt + 1)));
      }
      attempt++;
    }
    throw Exception('Failed to request $url after $retries attempts');
  }

  Future<List<dynamic>> getPopularMovies({
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await _get(
      '$_baseUrl/movie/popular?language=$language&page=$page',
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
    final response = await _get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load movies by genre');
    }
  }

  Future<Map<int, String>> getGenreList() async {
    final response = await _get('$_baseUrl/genre/movie/list');
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
    final response = await _get(
      '$_baseUrl/discover/movie?with_original_language=$languageCode&language=$language&sort_by=popularity.desc&page=$page',
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
    final response = await _get(url);
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
    final response = await _get(
      '$_baseUrl/tv/popular?language=$language&page=$page',
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
    final response = await _get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load TV series by genre');
    }
  }

  Future<Map<int, String>> getTVGenreList() async {
    final response = await _get('$_baseUrl/genre/tv/list');
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
    final response = await _get(
      '$_baseUrl/discover/tv?with_original_language=$languageCode&language=$language&sort_by=popularity.desc&page=$page',
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
    final response = await _get(url);
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
    final response = await _get(
      '$_baseUrl/tv/$tvId/season/$seasonNumber?language=$language',
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
    final response = await _get(
      '$_baseUrl/trending/movie/week?language=$language',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load trending movies');
    }
  }

  Future<List<dynamic>> getTrendingTV({String language = 'en-US'}) async {
    final response = await _get(
      '$_baseUrl/trending/tv/week?language=$language',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load trending TV');
    }
  }

  Future<List<dynamic>> getNowPlayingMovies({String language = 'en-US'}) async {
    final response = await _get(
      '$_baseUrl/movie/now_playing?language=$language',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load now playing movies');
    }
  }

  Future<List<dynamic>> getOnTheAirTV({String language = 'en-US'}) async {
    final response = await _get('$_baseUrl/tv/on_the_air?language=$language');
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
    final response = await _get(
      '$_baseUrl/movie/$movieId/videos?language=$language',
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
    final response = await _get('$_baseUrl/tv/$tvId/videos?language=$language');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getWatchProviders(int id, bool isMovie) async {
    final type = isMovie ? 'movie' : 'tv';
    final response = await _get('$_baseUrl/$type/$id/watch/providers');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'];
    } else {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getMovieCredits(int movieId) async {
    final response = await _get('$_baseUrl/movie/$movieId/credits');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) return null;
      return data;
    } else {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTVCredits(int tvId) async {
    final response = await _get('$_baseUrl/tv/$tvId/credits');
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
    final response = await _get(
      '$_baseUrl/search/multi?query=$query&language=$language&page=$page',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to search');
    }
  }

  // Person methods
  Future<Map<String, dynamic>> getPersonDetails(
    int personId, {
    String language = 'en-US',
  }) async {
    final response = await _get(
      '$_baseUrl/person/$personId?language=$language',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) {
        throw Exception(
          data['status_message'] ?? 'Failed to load person details',
        );
      }
      return data;
    } else {
      throw Exception('Failed to load person details');
    }
  }

  Future<Map<String, dynamic>> getPersonCombinedCredits(
    int personId, {
    String language = 'en-US',
  }) async {
    final response = await _get(
      '$_baseUrl/person/$personId/combined_credits?language=$language',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == false) {
        throw Exception(
          data['status_message'] ?? 'Failed to load person credits',
        );
      }
      return data;
    } else {
      throw Exception('Failed to load person credits');
    }
  }

  // Watch Providers
  Future<List<dynamic>> getAvailableWatchProviders({
    String type = 'movie',
    String language = 'en-US',
    String watchRegion = 'IN', // Default to India for Hotstar visibility
  }) async {
    final response = await _get(
      '$_baseUrl/watch/providers/$type?language=$language&watch_region=$watchRegion',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load watch providers');
    }
  }

  // Discover methods for filtering
  Future<List<dynamic>> discoverMovies({
    String language = 'en-US',
    int page = 1,
    String? withWatchProviders,
    String watchRegion = 'IN',
    String? withGenres,
    String? releaseDateGte,
    String? releaseDateLte,
  }) async {
    String url =
        '$_baseUrl/discover/movie?language=$language&page=$page&sort_by=popularity.desc&watch_region=$watchRegion';

    if (withWatchProviders != null) {
      url += '&with_watch_providers=$withWatchProviders';
    }
    if (withGenres != null) {
      url += '&with_genres=$withGenres';
    }
    if (releaseDateGte != null) {
      url += '&primary_release_date.gte=$releaseDateGte';
    }
    if (releaseDateLte != null) {
      url += '&primary_release_date.lte=$releaseDateLte';
    }

    final response = await _get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to discover movies');
    }
  }

  Future<List<dynamic>> discoverTV({
    String language = 'en-US',
    int page = 1,
    String? withWatchProviders,
    String watchRegion = 'IN',
    String? withGenres,
    String? firstAirDateGte,
    String? firstAirDateLte,
  }) async {
    String url =
        '$_baseUrl/discover/tv?language=$language&page=$page&sort_by=popularity.desc&watch_region=$watchRegion';

    if (withWatchProviders != null) {
      url += '&with_watch_providers=$withWatchProviders';
    }
    if (withGenres != null) {
      url += '&with_genres=$withGenres';
    }
    if (firstAirDateGte != null) {
      url += '&first_air_date.gte=$firstAirDateGte';
    }
    if (firstAirDateLte != null) {
      url += '&first_air_date.lte=$firstAirDateLte';
    }

    final response = await _get(url);
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to discover TV series');
    }
  }
}
