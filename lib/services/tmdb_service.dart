import 'dart:convert';
import 'package:http/http.dart' as http;

class TMDBService {
  final String _baseUrl = 'https://tmdb-proxy-sz5v.onrender.com';

  Future<List<dynamic>> getPopularMovies() async {
    final response = await http.get(Uri.parse('$_baseUrl/movies/popular'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load popular movies');
    }
  }

  Future<List<dynamic>> getMoviesByGenre(int genreId, {String language = 'en-US'}) async {
    final response = await http.get(Uri.parse('$_baseUrl/discover/movie?with_genres=$genreId&language=$language'));
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

  // TV Series methods
  Future<List<dynamic>> getPopularTV() async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/popular'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load popular TV series');
    }
  }

  Future<List<dynamic>> getTVByGenre(int genreId, {String language = 'en-US'}) async {
    final response = await http.get(Uri.parse('$_baseUrl/discover/tv?with_genres=$genreId&language=$language'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load TV series by genre');
    }
  }

  Future<Map<int, String>> getTVGenreList() async {
    final response = await http.get(Uri.parse('$_baseUrl/genre/tv/list'));
    if (response.statusCode == 200) {
      final genres = json.decode(response.body)['genres'] as List<dynamic>;
      return {for (var genre in genres) genre['id']: genre['name']};
    } else {
      throw Exception('Failed to load TV genre list');
    }
  }

  // Trending and newly released methods
  Future<List<dynamic>> getTrendingMovies() async {
    final response = await http.get(Uri.parse('$_baseUrl/trending/movie'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load trending movies');
    }
  }

  Future<List<dynamic>> getTrendingTV() async {
    final response = await http.get(Uri.parse('$_baseUrl/trending/tv'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load trending TV');
    }
  }

  Future<List<dynamic>> getNowPlayingMovies() async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/now-playing'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load now playing movies');
    }
  }

  Future<List<dynamic>> getOnTheAirTV() async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/on-the-air'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load on-air TV');
    }
  }
}
