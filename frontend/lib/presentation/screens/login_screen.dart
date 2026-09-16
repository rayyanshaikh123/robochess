import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/server_config_provider.dart';
import '../../core/errors/api_exception.dart';
import '../providers/session_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';


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
      final serverReady = await ref
          .read(serverConfigProvider.notifier)
          .discoverIfUnavailable();
      if (!serverReady) {
        throw ApiException(
            'Backend not found on this Wi-Fi network. Check that the server is running and both devices use the same network.');
      }
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
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: AppLogo(size: 72, showBorder: false, showShadow: false),
                ),
              ),
              Text('Welcome back',
                  style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: kOnSurface)),
              const SizedBox(height: 8),
              Text('Sign in to sync your boards and games.',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: kOnSurfaceVariant)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: kSurfaceContLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kOutlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
                              style: GoogleFonts.outfit(
                                  fontSize: 13,
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
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('PLAY LOCALLY WITHOUT INTERNET'),
                          ),
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
      hintStyle: GoogleFonts.inter(color: kOnSurfaceVariant.withOpacity(0.7)),
      filled: true,
      fillColor: kSurfaceContLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kOutlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kOutlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
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
    await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ServerConfigDialog(
        currentUrl: currentUrl,
        onSave: (value) async {
          await ref.read(serverConfigProvider.notifier).update(value);
        },
      ),
    );
  }
}

class _ServerConfigDialog extends StatefulWidget {
  final String currentUrl;
  final Future<void> Function(String) onSave;

  const _ServerConfigDialog({
    required this.currentUrl,
    required this.onSave,
  });

  @override
  State<_ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<_ServerConfigDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurfaceContLow,
      title: const Text('Configure server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            style: GoogleFonts.inter(color: kOnSurface),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.42:8000',
              hintStyle: GoogleFonts.inter(color: kOnSurfaceVariant, fontSize: 13),
              filled: true,
              fillColor: kSurfaceContHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: kError)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final value = _controller.text.trim();
            try {
              await widget.onSave(value);
              if (mounted) {
                Navigator.of(context).pop(value);
              }
            } on ArgumentError catch (e) {
              setState(() => _error = e.message);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
