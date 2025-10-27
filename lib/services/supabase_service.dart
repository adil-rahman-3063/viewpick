import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient supabase = Supabase.instance.client;

class SupabaseService {
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

  // Get user's language preference from metadata
  static String getUserLanguage() {
    final user = supabase.auth.currentUser;
    if (user == null) return 'en-US';
    
    final metadata = user.userMetadata;
    return metadata?['language'] as String? ?? 'en-US';
  }

  // Example: fetch a list from 'titles' table
  static Future<PostgrestResponse> fetchTitles({int limit = 20}) {
    return supabase.from('titles').select().limit(limit).execute();
  }

  // Insert liked genres - saves each genre individually to avoid duplicates
  static Future<void> addLikedGenres(String genreString) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Split genres by comma
      final genres = genreString.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty);
      
      for (final genre in genres) {
        // Check if this genre already exists for this user
        final existing = await supabase
            .from('liked_movies')
            .select('genre')
            .eq('user_id', userId)
            .eq('genre', genre)
            .execute();
        
        // Only insert if it doesn't exist
        if (existing.data.isEmpty) {
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

  // Get liked genres for the current user
  static Future<List<String>> getLikedGenres() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }
    try {
      final result = await supabase
          .from('liked_movies')
          .select('genre')
          .eq('user_id', userId)
          .execute();

      final data = result.data as List<Map<String, dynamic>>;
      // Each row now has a single genre, just extract them
      return data.map((e) => e['genre'] as String).toSet().toList();
    } on PostgrestException catch (e) {
      print('Error fetching liked genres: ${e.message}');
      return [];
    } catch (e) {
      print('An unexpected error occurred while fetching liked genres: $e');
      return [];
    }
  }

  // Check if user has any liked movies
  static Future<bool> hasLikedMovies() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    
    try {
      final result = await supabase
          .from('liked_movies')
          .select('genre')
          .eq('user_id', userId)
          .limit(1)
          .execute();
      
      return (result.data as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Watchlist methods
  static Future<void> addToWatchlist(Map<String, dynamic> item, bool isMovie) async {
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
      await supabase.from('watchlist').delete().eq('user_id', userId).eq('item_id', itemId);
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
          .limit(1)
          .execute();

      return (result.data as List).isNotEmpty;
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
          .order('created_at', ascending: false)
          .execute();

      return (result.data as List).map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error fetching watchlist: $e');
      return [];
    }
  }

  // Watched methods
  static Future<void> addToWatched(Map<String, dynamic> item, bool isMovie, {int? rating}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('watched').insert({
        'user_id': userId,
        'item_id': item['id'],
        'item_type': isMovie ? 'movie' : 'tv',
        'title': item['title'] ?? item['name'],
        'poster_path': item['poster_path'],
        'release_date': item['release_date'] ?? item['first_air_date'],
        'overview': item['overview'],
        'rating': rating,
        'watched_date': DateTime.now().toIso8601String().split('T')[0],
      });
    } catch (e) {
      print('Error adding to watched: $e');
    }
  }

  static Future<void> removeFromWatched(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('watched').delete().eq('user_id', userId).eq('item_id', itemId);
    } catch (e) {
      print('Error removing from watched: $e');
    }
  }

  static Future<bool> isWatched(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final result = await supabase
          .from('watched')
          .select('item_id')
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .limit(1)
          .execute();

      return (result.data as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getWatched() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final result = await supabase
          .from('watched')
          .select()
          .eq('user_id', userId)
          .order('watched_date', ascending: false)
          .execute();

      return (result.data as List).map((item) => item as Map<String, dynamic>).toList();
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

  // NOTE: Language preference support can be added later by:
  // 1. Adding a user_preferences table or extending auth.users metadata
  // 2. Storing language preference and using it in TMDB queries
  // Currently, all movies are filtered by language=en-US via the proxy server
}
