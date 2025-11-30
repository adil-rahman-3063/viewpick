import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'theme/app_theme.dart';
import 'login.dart';
import 'register.dart';
import 'pages/home_page.dart';
import 'pages/settings.dart';

void handleAuthCallback(Uri uri) async {
  // Get the session from the URL
  if (uri.queryParameters['access_token'] != null) {
    // Set the session in Supabase
    final client = Supabase.instance.client;
    await client.auth.setSession(uri.queryParameters['access_token']!);
    // Navigate to home page
    // Note: You'll need to implement a way to access navigation from here
    // One way is to use a GlobalKey<NavigatorState>
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize deep link handling
  final appLinks = AppLinks();

  // Handle incoming links - both cold and warm starts
  appLinks.allUriLinkStream.listen((uri) {
    print('Got link: $uri');
    if (uri.path == '/auth') {
      handleAuthCallback(uri);
    }
  });

  // Handle Windows protocol activation: args may contain the deep link URI
  String? initialLinkFromArgs;
  if (Platform.isWindows && args.isNotEmpty) {
    for (final a in args) {
      if (a.startsWith('viewpick://')) {
        initialLinkFromArgs = a;
        break;
      }
    }
  }

  // Load local .env file (copy from .env.example and set your keys)
  await dotenv.load(fileName: 'assets/credentials.env').catchError((err) {
    // If loading fails, we'll continue but warn in console.
    // You can still run the app and fill in env vars later.
    // ignore: avoid_print
    print('Could not load .env file: $err');
  });

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  String initialRoute = '/';

  if (supabaseUrl != null && supabaseAnonKey != null) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    // ignore: avoid_print
    print('Supabase initialized');

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      initialRoute = '/home';
    }
  } else {
    // ignore: avoid_print
    print(
      'Supabase not initialized: missing SUPABASE_URL or SUPABASE_ANON_KEY in .env',
    );
  }

  runApp(MyApp(initialLink: initialLinkFromArgs, initialRoute: initialRoute));
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class MyApp extends StatelessWidget {
  final String? initialLink;
  final String initialRoute;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  MyApp({super.key, this.initialLink, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'ViewPick',
          navigatorKey: navigatorKey,
          // Use Material 3 with brown seed color
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          // Dynamic theme mode
          themeMode: currentMode,

          // Start at the login page and provide a named route for home.
          initialRoute: initialRoute,
          routes: {
            '/': (context) => LoginPage(initialLink: initialLink),
            '/login': (context) => LoginPage(initialLink: initialLink),
            '/home': (context) => HomePage(),
            '/register': (context) => const RegisterPage(),
            '/settings': (context) => const SettingsPage(),
          },
        );
      },
    );
  }
}
