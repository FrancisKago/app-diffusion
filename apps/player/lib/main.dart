import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      title: 'Player Stub',
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'PLAYER (scaffold)',
            style: TextStyle(color: Colors.white, fontSize: 32),
          ),
        ),
      ),
    ),
  );
}
