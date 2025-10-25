import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'login.dart';

Future<void> main() async {
	WidgetsFlutterBinding.ensureInitialized();


	// Load local .env file (copy from .env.example and set your keys)
	await dotenv.load(fileName: 'assets/credentials.env').catchError((err) {
		// If loading fails, we'll continue but warn in console.
		// You can still run the app and fill in env vars later.
		// ignore: avoid_print
		print('Could not load .env file: $err');
	});

	final supabaseUrl = dotenv.env['SUPABASE_URL'];
	final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

	if (supabaseUrl != null && supabaseAnonKey != null) {
		await Supabase.initialize(
			url: supabaseUrl,
			anonKey: supabaseAnonKey,
		);
		// ignore: avoid_print
		print('Supabase initialized');
	} else {
		// ignore: avoid_print
		print('Supabase not initialized: missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
	}

	runApp(const MyApp());
}

class MyApp extends StatelessWidget {
	const MyApp({super.key});

	@override
	Widget build(BuildContext context) {
		return MaterialApp(
			title: 'ViewPick',
			// Use Material 3 with brown seed color
			theme: AppTheme.lightTheme,
			darkTheme: AppTheme.darkTheme,
			// Default to dark mode
			themeMode: ThemeMode.dark,
			
			// Start at the login page and provide a named route for home.
			initialRoute: '/',
			routes: {
				'/': (context) => const LoginPage(),
				'/home': (context) => const Scaffold(body: Center(child: Text('Home placeholder'))),
			},
		);
	}
}