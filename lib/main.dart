import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'theme/app_theme.dart';
import 'login.dart';
import 'register.dart';
import 'pages/home_page.dart';
import 'pages/settings.dart';
import 'pages/forgot_password.dart';
import 'pages/password_change.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... imports

  // Load environment
  await dotenv.load(fileName: 'assets/credentials.env').catchError((err) {
    print('Could not load .env file: $err');
  });

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl != null && supabaseAnonKey != null) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: true,
    );
    print('Supabase initialized (Debug Mode)');
  } else {
    print('Supabase not initialized: missing keys');
  }

  // Listen for password recovery event (Standard Supabase)
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    print('MAIN: AuthEvent: $event');
    if (event == AuthChangeEvent.passwordRecovery) {
      print('MAIN: Password Recovery Event Detected! Navigating...');
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/password_change',
        (route) => false,
      );
    }
  });

  runApp(const MyApp());
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'ViewPick',
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const AuthHandler(),
            '/login': (context) => const LoginPage(),
            '/home': (context) => HomePage(),
            '/register': (context) => const RegisterPage(),
            '/forgot_password': (context) => const ForgotPasswordPage(),
            '/password_change': (context) => const PasswordChangePage(),
            '/settings': (context) => const SettingsPage(),
          },
        );
      },
    );
  }
}

class AuthHandler extends StatefulWidget {
  const AuthHandler({super.key});

  @override
  State<AuthHandler> createState() => _AuthHandlerState();
}

class _AuthHandlerState extends State<AuthHandler> {
  late AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Listen to all links
    _appLinks.allUriLinkStream.listen((uri) {
      _processDeepLink(uri);
    });
  }

  Future<void> _processDeepLink(Uri uri) async {
    print('AuthHandler: Deep link received: $uri');

    if (uri.fragment.contains('type=recovery') ||
        uri.queryParameters['type'] == 'recovery' ||
        uri.host == 'reset-password') {
      print('AuthHandler: Recovery link detected!');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset Link Detected! Processing...')),
      );

      final fragment = uri.fragment;
      final params = Uri.splitQueryString(fragment);
      final accessToken = params['access_token'];
      final refreshToken = params['refresh_token'];

      if (accessToken != null && refreshToken != null) {
        print('AuthHandler: Setting session...');
        try {
          await Supabase.instance.client.auth.setSession(refreshToken);
          print('AuthHandler: Session set. Navigating...');
          if (mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/password_change', (route) => false);
          }
        } catch (e) {
          print('AuthHandler: Error: $e');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Session Error: $e')));
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final session = snapshot.data?.session;
          if (session != null) {
            return HomePage();
          }
        }
        return const LoginPage();
      },
    );
  }
}
