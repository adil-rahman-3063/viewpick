import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TMDBService {
  final String _apiKey = dotenv.env['TMDB_API_KEY'] ?? '';
  final String _baseUrl = 'https://api.themoviedb.org/3';

  Future<List<dynamic>> getPopularMovies() async {
    if (_apiKey.isEmpty) {
      throw Exception('TMDB_API_KEY is not set in your .env file');
    }
    final response = await http.get(Uri.parse('$_baseUrl/movie/popular?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load popular movies');
    }
  }

  Future<List<dynamic>> getMoviesByGenre(int genreId) async {
    if (_apiKey.isEmpty) {
      throw Exception('TMDB_API_KEY is not set in your .env file');
    }
    final response = await http.get(Uri.parse('$_baseUrl/discover/movie?api_key=$_apiKey&with_genres=$genreId'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Failed to load movies by genre');
    }
  }

  Future<Map<int, String>> getGenreList() async {
    if (_apiKey.isEmpty) {
      throw Exception('TMDB_API_KEY is not set in your .env file');
    }
    final response = await http.get(Uri.parse('$_baseUrl/genre/movie/list?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final genres = json.decode(response.body)['genres'] as List<dynamic>;
      return {for (var genre in genres) genre['id']: genre['name']};
    } else {
      throw Exception('Failed to load genre list');
    }
  }
}
