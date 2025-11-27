import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

final SupabaseClient supabase = Supabase.instance.client;

class SupabaseService {
  // Language name to TMDB code mapping
  static final Map<String, String> _languageCodeMap = {
    'English': 'en-US',
    'Hindi': 'hi-IN',
    'Tamil': 'ta-IN',
    'Telugu': 'te-IN',
    'Malayalam': 'ml-IN',
    'Kannada': 'kn-IN',
    'Mandarin': 'zh-CN',
    'Japanese': 'ja-JP',
    'Korean': 'ko-KR',
    'French': 'fr-FR',
    'Spanish': 'es-ES',
    'Portuguese': 'pt-BR',
    'Italian': 'it-IT',
    'German': 'de-DE',
    'Russian': 'ru-RU',
    'Persian': 'fa-IR',
    'Turkish': 'tr-TR',
  };

  // Getter for supported language codes
  static List<String> get supportedLanguageCodes =>
      _languageCodeMap.values.toList();

  // Sign in with email + password
  static Future<AuthResponse> signIn(String email, String password) async {
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign out
  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // Get current user
  static User? currentUser() => supabase.auth.currentUser;

  // Get user's language preferences from metadata and return TMDB codes
  static List<String> getUserLanguages() {
    final user = supabase.auth.currentUser;
    if (user == null) return ['en-US'];

    final metadata = user.userMetadata;
    final languages = metadata?['languages'] as List?;

    if (languages == null || languages.isEmpty) {
      return ['en-US'];
    }

    // Convert language names to TMDB codes
    return languages
        .map((lang) => _languageCodeMap[lang as String])
        .where((code) => code != null)
        .cast<String>()
        .toList();
  }

  // Get a random language from user preferences (backward compatibility)
  static String getUserLanguage() {
    final languages = getUserLanguages();
    if (languages.isEmpty) return 'en-US';
    return languages[Random().nextInt(languages.length)];
  }

  // Example: fetch a list from 'titles' table
  static Future<PostgrestResponse> fetchTitles({int limit = 20}) async {
    return await supabase.from('titles').select().limit(limit);
  }

  // Insert liked movie genres
  static Future<void> addLikedMovieGenres(String genreString) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Split genres by comma
      final genres = genreString
          .split(',')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty);

      for (final genre in genres) {
        // Check if this genre already exists for this user
        final existing = await supabase
            .from('liked_movies')
            .select('genre')
            .eq('user_id', userId)
            .eq('genre', genre);

        // Only insert if it doesn't exist
        if (existing.isEmpty) {
          await supabase.from('liked_movies').insert({
            'user_id': userId,
            'genre': genre,
          });
        }
      }
    } catch (e) {
      print('Error adding liked genres: $e');
    }
  }

  // Insert liked TV genres
  static Future<void> addLikedTVGenres(String genreString) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final genres = genreString
          .split(',')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty);

      for (final genre in genres) {
        final existing = await supabase
            .from('liked_series')
            .select('genre')
            .eq('user_id', userId)
            .eq('genre', genre);

        if (existing.isEmpty) {
          await supabase.from('liked_series').insert({
            'user_id': userId,
            'genre': genre,
          });
        }
      }
    } catch (e) {
      print('Error adding liked TV genres: $e');
    }
  }

  // Get liked movie genres
  static Future<List<String>> getLikedMovieGenres() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      print('getLikedMovieGenres: userId is null, returning empty list.');
      return [];
    }
    print('getLikedMovieGenres: fetching for userId: $userId');

    try {
      final data = await supabase
          .from('liked_movies')
          .select<List<Map<String, dynamic>>>('genre')
          .eq('user_id', userId);

      print('getLikedMovieGenres: Supabase data: $data');

      if (data.isEmpty) {
        print('getLikedMovieGenres: Data is empty.');
        return [];
      }

      final genres = data.map((e) => e['genre'] as String).toSet().toList();

      print('getLikedMovieGenres: Parsed genres: $genres');
      return genres;
    } catch (e) {
      print('An unexpected error occurred while fetching liked genres: $e');
      return [];
    }
  }

  // Get liked TV genres
  static Future<List<String>> getLikedTVGenres() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final data = await supabase
          .from('liked_series')
          .select<List<Map<String, dynamic>>>('genre')
          .eq('user_id', userId);

      if (data.isEmpty) return [];

      return data.map((e) => e['genre'] as String).toSet().toList();
    } catch (e) {
      print('Error fetching liked TV genres: $e');
      return [];
    }
  }

  // Check if user has any liked content
  static Future<bool> hasLikedContent(bool isMovie) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final table = isMovie ? 'liked_movies' : 'liked_series';

    try {
      final result = await supabase
          .from(table)
          .select('genre')
          .eq('user_id', userId)
          .limit(1);

      return (result as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Watchlist methods
  static Future<void> addToWatchlist(
    Map<String, dynamic> item,
    bool isMovie,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('watchlist').insert({
        'user_id': userId,
        'item_id': item['id'],
        'item_type': isMovie ? 'movie' : 'tv',
        'title': item['title'] ?? item['name'],
        'poster_path': item['poster_path'],
        'release_date': item['release_date'] ?? item['first_air_date'],
        'overview': item['overview'],
      });
    } catch (e) {
      print('Error adding to watchlist: $e');
    }
  }

  static Future<void> removeFromWatchlist(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watchlist')
          .delete()
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      print('Error removing from watchlist: $e');
    }
  }

  static Future<bool> isInWatchlist(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final result = await supabase
          .from('watchlist')
          .select('item_id')
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .limit(1);

      return (result as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getWatchlist() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final result = await supabase
          .from('watchlist')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (result as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error fetching watchlist: $e');
      return [];
    }
  }

  // Watched methods
  static Future<void> addToWatched(
    Map<String, dynamic> item,
    bool isMovie, {
    int? rating,
    int? watchedSeason,
    int? watchedEpisode,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('watched').upsert({
        'user_id': userId,
        'item_id': item['id'],
        'item_type': isMovie ? 'movie' : 'tv',
        'title': item['title'] ?? item['name'],
        'poster_path': item['poster_path'],
        'release_date': item['release_date'] ?? item['first_air_date'],
        'overview': item['overview'],
        'rating': rating,
        'watched_date': DateTime.now().toIso8601String().split('T')[0],
        'watched_season': watchedSeason,
        'watched_episode': watchedEpisode,
      }, onConflict: 'user_id, item_id');
    } catch (e) {
      print('Error adding to watched: $e');
    }
  }

  static Future<void> removeFromWatched(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watched')
          .delete()
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      print('Error removing from watched: $e');
    }
  }

  static Future<Map<String, dynamic>?> getWatchedItem(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final result = await supabase
          .from('watched')
          .select()
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .maybeSingle();

      return result;
    } catch (e) {
      print('Error checking watched status: $e');
      return null;
    }
  }

  static Future<bool> isWatched(int itemId) async {
    final item = await getWatchedItem(itemId);
    return item != null;
  }

  static Future<List<Map<String, dynamic>>> getWatched() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final result = await supabase
          .from('watched')
          .select()
          .eq('user_id', userId)
          .order('watched_date', ascending: false);

      return (result as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error fetching watched: $e');
      return [];
    }
  }

  static Future<void> updateRating(int itemId, int rating) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watched')
          .update({'rating': rating})
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      print('Error updating rating: $e');
    }
  }

  // Update watched progress for TV series
  static Future<void> updateWatchedProgress(
    int itemId,
    int season,
    int episode,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watched')
          .update({
            'watched_season': season,
            'watched_episode': episode,
            'watched_date': DateTime.now().toIso8601String().split('T')[0],
          })
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      print('Error updating watched progress: $e');
    }
  }

  // Helper to mark an entire series as watched
  static Future<void> markSeriesAsWatched(
    Map<String, dynamic> show,
    Map<String, dynamic> details,
  ) async {
    try {
      final seasons = details['seasons'] as List<dynamic>;

      // Find the last season (ignoring season 0 if possible, or just taking max season number)
      int maxSeason = 0;
      int maxEpisode = 0;

      for (var season in seasons) {
        final seasonNum = season['season_number'] as int;
        final episodeCount = season['episode_count'] as int;

        if (seasonNum > 0 && seasonNum >= maxSeason) {
          maxSeason = seasonNum;
          maxEpisode = episodeCount;
        }
      }

      if (maxSeason > 0 && maxEpisode > 0) {
        await addToWatched(
          show,
          false,
          watchedSeason: maxSeason,
          watchedEpisode: maxEpisode,
        );
      }
    } catch (e) {
      print('Error marking series as watched: $e');
      rethrow;
    }
  }

  // NOTE: Language preference support can be added later by:
  // 1. Adding a user_preferences table or extending auth.users metadata
  // 2. Storing language preference and using it in TMDB queries
  // Currently, all movies are filtered by language=en-US via the proxy server
}
