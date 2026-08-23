import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/server_config_provider.dart';
import '../../core/errors/api_exception.dart';
import '../providers/session_provider.dart';

const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kOnPrimary = Color(0xFF173800);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kError = Color(0xFFFFB4AB);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      if (mounted) context.go('/home');
    } catch (err) {
      final message = err is ApiException
          ? err.message
          : err is TimeoutException
              ? 'Login timed out. Check your connection and retry.'
              : err is SocketException
                  ? 'Network error. Check your connection and retry.'
                  : 'Login failed. Check credentials.';
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const SizedBox(height: 8),
              Text('Sign in to sync your boards and games.',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: kOnSurfaceVariant)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kSurfaceContLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EMAIL',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kOnSurfaceVariant,
                              letterSpacing: 2)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.inter(color: kOnSurface),
                        decoration: _inputDecoration('you@example.com'),
                        validator: (value) =>
                            value == null || !value.contains('@')
                                ? 'Enter a valid email'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      Text('PASSWORD',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kOnSurfaceVariant,
                              letterSpacing: 2)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        style: GoogleFonts.inter(color: kOnSurface),
                        decoration: _inputDecoration('••••••••'),
                        validator: (value) => value == null || value.length < 8
                            ? 'Minimum 8 characters'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style:
                                GoogleFonts.inter(fontSize: 12, color: kError)),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: kOnPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(_submitting ? 'SIGNING IN...' : 'SIGN IN',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('New here?',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: kOnSurfaceVariant)),
                          TextButton(
                            onPressed: () => context.go('/register'),
                            child: Text('Create account',
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kPrimary)),
                          ),
                        ],
                      ),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => context.go('/local'),
                          icon: const Icon(Icons.bluetooth, size: 16),
                          label: const Text('PLAY LOCALLY WITHOUT INTERNET'),
                        ),
                      ),
                      const _ServerConfigButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: kOnSurfaceVariant),
      filled: true,
      fillColor: kSurfaceContHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

/// "Configure server" affordance: shows the active backend URL and opens a
/// dialog to change it at runtime (BUG-12).
class _ServerConfigButton extends ConsumerWidget {
  const _ServerConfigButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUrl = ref.watch(serverConfigProvider);
    final label = currentUrl.length > 40
        ? '${currentUrl.substring(0, 37)}...'
        : currentUrl;
    return Center(
      child: TextButton(
        onPressed: () => _showConfigDialog(context, ref, currentUrl),
        style: TextButton.styleFrom(
          foregroundColor: kOnSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        child: Text(
          '⚙ Server: $label',
          style: GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant),
        ),
      ),
    );
  }

  Future<void> _showConfigDialog(
      BuildContext context, WidgetRef ref, String currentUrl) async {
    final controller = TextEditingController(text: currentUrl);
    String? error;
    await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: kSurfaceContLow,
          title: const Text('Configure server'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: GoogleFonts.inter(color: kOnSurface),
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.42:8000',
                  hintStyle:
                      GoogleFonts.inter(color: kOnSurfaceVariant, fontSize: 13),
                  filled: true,
                  fillColor: kSurfaceContHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: GoogleFonts.inter(fontSize: 12, color: kError)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final value = controller.text.trim();
                try {
                  await ref.read(serverConfigProvider.notifier).update(value);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(value);
                  }
                } on ArgumentError catch (e) {
                  setDialogState(() => error = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}
