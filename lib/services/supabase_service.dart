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
}
