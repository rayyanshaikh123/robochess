import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../providers/device_provider.dart';
import '../providers/session_provider.dart';

const kBackground = Color(0xFF151311);
const kSurfaceContLow = Color(0xFF1D1B19);
const kSurfaceContHighest = Color(0xFF373431);
const kPrimary = Color(0xFF8ADB52);
const kOnPrimary = Color(0xFF173800);
const kOnSurface = Color(0xFFE7E2DD);
const kOnSurfaceVariant = Color(0xFFC0CAB4);
const kError = Color(0xFFFFB4AB);

class BoardLinkScreen extends ConsumerStatefulWidget {
  const BoardLinkScreen({super.key});

  @override
  ConsumerState<BoardLinkScreen> createState() => _BoardLinkScreenState();
}

class _BoardLinkScreenState extends ConsumerState<BoardLinkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(deviceRepositoryProvider)
          .link(pairingCode: _codeCtrl.text.trim());
      await ref.read(deviceListProvider.notifier).load();
      if (mounted) context.pop();
    } catch (err) {
      setState(() => _error = 'Pairing failed. Check the code and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openScanInput() async {
    final controller = TextEditingController(text: _codeCtrl.text.trim());
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBackground,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scan Result',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: kOnSurface)),
              const SizedBox(height: 8),
              Text('Paste the scanned pairing code here.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: kOnSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(color: kOnSurface),
                decoration: _inputDecoration('123456'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: kOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('USE CODE',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2)),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (code != null && code.isNotEmpty) {
      setState(() => _codeCtrl.text = code);
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _codeCtrl.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Link Board',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.w700, color: kOnSurface)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter pairing code',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: kOnSurface)),
            const SizedBox(height: 8),
            Text('Your board displays a 6-digit code. Enter it to link.',
                style:
                    GoogleFonts.inter(fontSize: 12, color: kOnSurfaceVariant)),
            const SizedBox(height: 6),
            Text('Local test board code: 000000',
                style:
                    GoogleFonts.inter(fontSize: 11, color: kOnSurfaceVariant)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : () => context.push('/connect/ble'),
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('SCAN AND SET UP OVER BLUETOOTH'),
              ),
            ),
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
                    Text('PAIRING CODE',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kOnSurfaceVariant,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.inter(color: kOnSurface),
                      decoration: _inputDecoration('123456'),
                      validator: (value) =>
                          value == null || value.trim().length < 4
                              ? 'Enter a valid code'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _openScanInput,
                            icon: const Icon(Icons.qr_code_scanner, size: 16),
                            label: Text('SCAN QR',
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _pasteCode,
                            icon: const Icon(Icons.content_paste, size: 16),
                            label: Text('PASTE',
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                          ),
                        ),
                      ],
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
                        child: Text(_submitting ? 'LINKING...' : 'LINK BOARD',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
