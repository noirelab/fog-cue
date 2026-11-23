import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'screens/home_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController()..load();
  runApp(FogCueApp(settings: settings));
}

class FogCueApp extends StatelessWidget {
  const FogCueApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: settings,
      child: MaterialApp(
        title: 'FoG Cue',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Palette.light),
        darkTheme: buildTheme(Palette.dark),
        themeMode: ThemeMode.system,
        home: const _Root(),
      ),
    );
  }
}

/// Espera as configurações salvas carregarem antes de mostrar a Home.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return SettingsScope.of(context).loaded ? const HomeScreen() : const Scaffold();
  }
}
