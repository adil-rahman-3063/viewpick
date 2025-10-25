import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _doLogin() {
    // For now this is a stub: accept any input and navigate to home.
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    // Apply the desired Google Font to this subtree via a Theme.
    // The GoogleFonts helper function for `bitcountGridSingle` may not exist in
    // the package; create a TextTheme that applies the font where needed.
    final base = Theme.of(context).textTheme;
    final textTheme = TextTheme(
      headlineLarge: GoogleFonts.getFont(
        'Bitcount Grid Single',
        textStyle: base.headlineLarge,
      ),
      headlineMedium: GoogleFonts.getFont(
        'Bitcount Grid Single',
        textStyle: base.headlineMedium,
      ),
      headlineSmall: GoogleFonts.getFont(
        'Bitcount Grid Single',
        textStyle: base.headlineSmall,
      ),
      bodyLarge: base.bodyLarge,
      bodyMedium: base.bodyMedium,
      bodySmall: base.bodySmall,
    );

    return Theme(
      data: Theme.of(context).copyWith(textTheme: textTheme),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.1), // Top spacing
              Text(
                'VIEWPICK',
                // Use the theme's headline style so the font applies consistently
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.1), // Spacing after logo
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _doLogin,
                child: const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
              child: const Text('Skip and go to Home'),
            ),
          ],
        ), // end Column
      ), // end Padding
    ), // end Scaffold (child of Theme)
  ); // end Theme
  }
}
