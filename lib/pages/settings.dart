import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../widget/toast.dart';
import '../widget/nav_bar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();

  List<String> _selectedLanguages = [];
  bool _isLoading = false;

  final List<String> _languages = [
    'English',
    'Hindi',
    'Tamil',
    'Telugu',
    'Malayalam',
    'Kannada',
    'Mandarin',
    'Japanese',
    'Korean',
    'French',
    'Spanish',
    'Portuguese',
    'Italian',
    'German',
    'Russian',
    'Persian',
    'Turkish',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final user = SupabaseService.currentUser();
    if (user != null) {
      _emailController.text = user.email ?? '';
      final metadata = user.userMetadata;
      if (metadata != null) {
        _nameController.text = metadata['name'] ?? '';
        _ageController.text = metadata['age']?.toString() ?? '';

        final langs = metadata['languages'];
        if (langs is List) {
          _selectedLanguages = List<String>.from(langs);
          _languageController.text = _selectedLanguages.join(', ');
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  void _showLanguageSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Select Languages',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: _languages.map((language) {
                                final isSelected = _selectedLanguages.contains(
                                  language,
                                );
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedLanguages.remove(language);
                                      } else {
                                        _selectedLanguages.add(language);
                                      }
                                      _languageController.text =
                                          _selectedLanguages.join(', ');
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.8)
                                          : Theme.of(context)
                                                .colorScheme
                                                .secondary
                                                .withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                      ),
                                    ),
                                    child: Text(
                                      language,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSecondary,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await SupabaseService.updateUserMetadata({
        'name': _nameController.text.trim(),
        'age': _ageController.text.trim(),
        'languages': _selectedLanguages,
      });
      if (mounted) {
        Toast.show(context, 'Profile updated successfully');
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, 'Error updating profile: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showChangePasswordDialog() {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                  obscureText: obscurePassword,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 chars' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                  obscureText: obscureConfirm,
                  validator: (v) =>
                      v != passwordController.text ? 'Mismatch' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    await SupabaseService.updatePassword(
                      passwordController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      Toast.show(context, 'Password updated successfully');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Toast.show(context, 'Error: $e', isError: true);
                    }
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                readOnly: true,
                enabled: false,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _languageController,
                decoration: InputDecoration(
                  labelText: 'Preferred Languages',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.language),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showLanguageSelector(context),
                  ),
                ),
                readOnly: true,
                onTap: () => _showLanguageSelector(context),
              ),
              const SizedBox(height: 32),

              OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Change Password'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: FrostedNavBar(
        selectedIndex: 4, // Keep Profile selected
        onItemSelected: (index) {
          if (index == 4) {
            Navigator.pop(context); // Go back to profile
          } else {
            FrostedNavBar.handleNavigation(context, index);
          }
        },
      ),
    );
  }
}
