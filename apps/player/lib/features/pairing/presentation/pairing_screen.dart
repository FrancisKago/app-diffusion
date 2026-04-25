import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/providers.dart';
import 'package:player/services/pairing_service.dart';
import 'package:player/services/secure_storage.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  String? _code;
  String? _sessionId;
  Timer? _pollTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final svc = ref.read(pairingServiceProvider);
      final res = await svc.requestCode();
      if (!mounted) return;
      setState(() {
        _code = res.code;
        _sessionId = res.sessionId;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossible de demander un code: $e');
    }
  }

  Future<void> _poll() async {
    if (_sessionId == null) return;
    try {
      final svc = ref.read(pairingServiceProvider);
      final res = await svc.pollStatus(_sessionId!);
      if (res.status == PairingStatus.claimed &&
          res.jwt != null &&
          res.deviceId != null) {
        _pollTimer?.cancel();
        await ref.read(secureStorageProvider).writeCredentials(
              DeviceCredentials(deviceId: res.deviceId!, jwt: res.jwt!),
            );
        if (mounted) ref.invalidate(credentialsProvider);
      } else if (res.status == PairingStatus.expired) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _error = "Code expiré. Redémarrez l'app.";
            _code = null;
          });
        }
      }
    } catch (_) {
      // Silent retry; network blips shouldn't break the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayCode = _code == null
        ? '- - -   - - -'
        : '${_code!.substring(0, 3)}   ${_code!.substring(3)}';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'APPAIRAGE EN COURS',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 24,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 48),
            Text(
              displayCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 140,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Saisissez ce code dans le back office',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
            if (_error != null) ...[
              const SizedBox(height: 32),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
