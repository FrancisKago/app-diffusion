import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/services/secure_storage.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({required this.creds, super.key});
  final DeviceCredentials creds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text('Player (sync à venir Task 8)',
            style: TextStyle(color: Colors.white, fontSize: 24)),
      ),
    );
  }
}
