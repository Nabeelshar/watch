import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/lobby/lobby_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? startupError;
  if (AppConfig.configured) {
    try {
      await Supabase.initialize(
        url: AppConfig.url,
        publishableKey: AppConfig.publishableKey,
      );
    } catch (_) {
      startupError =
          'The app could not initialize its connection. Close and reopen it to retry.';
    }
  }
  runApp(AfterglowApp(startupError: startupError));
}

class AfterglowApp extends StatelessWidget {
  const AfterglowApp({super.key, this.startupError});
  final String? startupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Afterglow',
    debugShowCheckedModeBanner: false,
    theme: afterglowTheme(),
    home: !AppConfig.configured || startupError != null
        ? Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.movie_outlined, size: 56),
                      const SizedBox(height: 24),
                      const Text('Afterglow', style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 12),
                      Text(
                        startupError ??
                            'This build needs its Supabase connection. Build with the project configuration file to get started.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const LobbyScreen(),
  );
}
