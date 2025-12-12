import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TMDBService {
  final String _baseUrl = 'https://api.themoviedb.org/3';
  final String _apiKey =
      dotenv.env['TMDB_API_KEY'] ?? 'a92961c9d1ffb10b5688204638171d0d';

  String? _resolvedIp;

  Future<void> _resolveTmdbIp() async {
    if (_resolvedIp != null) return;

    try {
      // Use Google DoH
      final response = await http.get(
        Uri.parse('https://dns.google/resolve?name=api.themoviedb.org&type=A'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final answers = data['Answer'] as List<dynamic>?;

        if (answers != null) {
          final ips = answers
              .where((a) => a['type'] == 1)
              .map((a) => a['data'] as String)
              .toList();

          if (ips.isNotEmpty) {
            _resolvedIp = ips[Random().nextInt(ips.length)];
            // print('Resolved TMDB IP via DoH: $_resolvedIp');
          }
        }
      }
    } catch (e) {
      // print('DoH resolution failed: $e');
    }
  }

  Future<http.Response> _get(String url, {int retries = 3}) async {
    // print('TMDBService: Requesting $url');

    final uri = Uri.parse(url);
    final newUri = uri.replace(
      queryParameters: {...uri.queryParameters, 'api_key': _apiKey},
    );

    int attempt = 0;
    while (attempt < retries) {
      try {
        await _resolveTmdbIp();

        http.Response response;
        if (_resolvedIp != null) {
          // Use manual secure socket connection to fix SNI issues
          response = await _rawSecureRequest(newUri, _resolvedIp!);
        } else {
          // Fallback to standard http
          response = await http
              .get(newUri)
              .timeout(const Duration(seconds: 60));
        }

        if (response.statusCode == 200) {
          return response;
        } else if (response.statusCode == 429) {
          // print('TMDBService: Rate limit hit, waiting...');
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        } else {
          // print('TMDBService: Response status: ${response.statusCode}');
          // print('TMDBService: Request failed for $url');
          if (response.statusCode >= 400 && response.statusCode < 500) {
            return response;
          }
        }
      } catch (e) {
        // print('TMDBService: Error (Attempt ${attempt + 1}): $e');
        // Force re-resolution on error
        _resolvedIp = null;
        if (attempt == retries - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 * (attempt + 1)));
      }
      attempt++;
    }
    throw Exception('Failed to request $url after $retries attempts');
  }

  Future<http.Response> _rawSecureRequest(Uri uri, String ip) async {
    try {
      // 1. Connect to the IP directly
      final socket = await Socket.connect(
        ip,
        443,
        timeout: const Duration(seconds: 10),
      );

      // 2. Upgrade to TLS, passing the HOSTNAME for correct SNI
      final secureSocket = await SecureSocket.secure(
        socket,
        host: 'api.themoviedb.org',
        supportedProtocols: ['http/1.1'],
      );

      // 3. Send HTTP Request
      final path = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
      final request = StringBuffer();
      request.write('GET $path HTTP/1.1\r\n');
      request.write('Host: api.themoviedb.org\r\n');
      request.write('Connection: close\r\n');
      request.write('User-Agent: ViewPick/1.0\r\n');
      request.write('\r\n');

      secureSocket.write(request.toString());
      await secureSocket.flush();

      // 4. Read Response
      final responseBuffer = StringBuffer();
      final completer = Completer<void>();

      final subscription = secureSocket
          .map((event) => utf8.decode(event))
          .listen(
            (data) {
              responseBuffer.write(data);
            },
            onError: (e) {
              // Suppress stream errors since we might be closing
              if (!completer.isCompleted) completer.complete();
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
            cancelOnError: true,
          );

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          // Ensure we don't hang forever
        },
      );

      await subscription.cancel();
      secureSocket.destroy(); // Ensure socket is closed/destroyed

      final rawResponse = responseBuffer.toString();
      if (rawResponse.isEmpty) throw Exception('Empty response from TMDB');

      // 5. Parse Response (Headers vs Body)
      final parts = rawResponse.split('\r\n\r\n');
      if (parts.length < 2) throw Exception('Invalid HTTP response format');

      final headerPart = parts[0];
      final bodyPart = parts
          .sublist(1)
          .join('\r\n\r\n'); // Reconstruct body if it contained double newlines

      final headerLines = headerPart.split('\r\n');
      final statusLine = headerLines[0];
      final statusCode = int.tryParse(statusLine.split(' ')[1]) ?? 0;

      final headers = <String, String>{};
      for (var i = 1; i < headerLines.length; i++) {
        final line = headerLines[i];
        final separator = line.indexOf(':');
        if (separator > 0) {
          headers[line.substring(0, separator).trim().toLowerCase()] = line
              .substring(separator + 1)
              .trim();
        }
      }

      String decodedBody = bodyPart;
      if (headers['transfer-encoding'] == 'chunked') {
        decodedBody = _parseChunkedBody(bodyPart);
      }

      return http.Response(decodedBody, statusCode, headers: headers);
    } catch (e) {
      // print('Raw secure request failed: $e');
      rethrow;
    }
  }

  String _parseChunkedBody(String raw) {
    // Basic chunked parser
    final buffer = StringBuffer();
    int index = 0;
    while (index < raw.length) {
      final nextNewline = raw.indexOf('\r\n', index);
      if (nextNewline == -1) break;

      final sizeStr = raw.substring(index, nextNewline);
      final chunkSize = int.tryParse(sizeStr, radix: 16);

      if (chunkSize == null) break;
      if (chunkSize == 0) break; // End of stream

      final start = nextNewline + 2;
      final end = start + chunkSize;
      if (end > raw.length) break;

      buffer.write(raw.substring(start, end));
      index = end + 2; // Skip trailing \r\n of the chunk
    }
    return buffer.toString();
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

  Future<Map<String, dynamic>> getCollectionDetails(
    int collectionId, {
    String language = 'en-US',
  }) async {
    final response = await _get(
      '$_baseUrl/collection/$collectionId?language=$language',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data;
    } else {
      throw Exception('Failed to load collection details');
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
