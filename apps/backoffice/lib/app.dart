import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class BackofficeApp extends StatelessWidget {
  const BackofficeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Diffusion — Back Office',
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(child: Text('App Diffusion — Back Office (Phase 1)')),
      ),
    );
  }
}
