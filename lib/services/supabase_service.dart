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

  // Example: fetch a list from 'titles' table
  static Future<PostgrestResponse> fetchTitles({int limit = 20}) {
    return supabase.from('titles').select().limit(limit).execute();
  }

  // Insert a liked movie
  static Future<PostgrestResponse> addLikedMovie(String genre) {
    final userId = supabase.auth.currentUser!.id;
    return supabase.from('liked_movies').insert({
      'user_id': userId,
      'genre': genre,
    }).execute();
  }

  // Get liked genres for the current user
  static Future<List<String>> getLikedGenres() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }
    try {
      final data = await supabase
          .from('liked_movies')
          .select<List<Map<String, dynamic>>>('genre')
          .eq('user_id', userId);

      final genres = data.map((e) => e['genre'] as String).toList();
      final uniqueGenres = <String>{};
      for (final genreString in genres) {
        uniqueGenres.addAll(genreString.split(',').map((g) => g.trim()));
      }
      return uniqueGenres.toList();
    } on PostgrestException catch (e) {
      print('Error fetching liked genres: ${e.message}');
      return [];
    } catch (e) {
      print('An unexpected error occurred while fetching liked genres: $e');
      return [];
    }
  }
}
