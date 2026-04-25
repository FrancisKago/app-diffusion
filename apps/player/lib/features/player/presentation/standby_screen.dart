import 'package:flutter/material.dart';

class StandbyScreen extends StatelessWidget {
  const StandbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tv_outlined, color: Colors.white24, size: 96),
            SizedBox(height: 24),
            Text(
              'EN ATTENTE DE CONTENU',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 28,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
