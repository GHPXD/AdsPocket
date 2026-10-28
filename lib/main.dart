import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/theme.dart';
import 'data/local_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startApp();
}

Future<void> startApp() async {
  try {
    final repository = await LocalRepository.open();
    final controller = AppController(
      repository,
      await SharedPreferences.getInstance(),
    );
    await controller.initialize();
    runApp(AdsPocketApp(controller: controller));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage_rounded, size: 48),
                    const SizedBox(height: 20),
                    const Text(
                      'Não foi possível abrir os dados locais.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Verifique o espaço disponível no aparelho e tente novamente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: startApp,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
