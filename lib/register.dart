import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    _submitAsync();
  }

  bool _loading = false;

  Future<void> _submitAsync() async {
    if (!_formKey.currentState!.validate()) return;
  final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _loading = true);
    try {
      // For emulator testing, use the Supabase hosted URL
      final redirectUrl = Platform.isAndroid && !kReleaseMode
          ? 'https://viewpick.app/auth'  // Use your Supabase project URL
          : 'viewpick://auth';
          
      await supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: redirectUrl,
      );

      if (!mounted) return;
      
      // Show confirmation dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Registration Successful'),
            content: Text('Please check ${email} to confirm your email address.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to login page
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration error: $err')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ageController,
                    decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your age';
                      final n = int.tryParse(v);
                      if (n == null || n <= 0) return 'Enter a valid age';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your email';
                      if (!RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(v)) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter a password';
                      if (v.length < 6) return 'Password should be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmController,
                    decoration: InputDecoration(
                      labelText: 'Re-enter Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Confirm your password';
                      if (v != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Register'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
