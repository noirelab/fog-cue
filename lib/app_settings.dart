import 'package:flutter/widgets.dart';

import 'config/experiment.dart';
import 'services/database.dart';

/// Configurações experimentais carregadas do banco e compartilhadas pelo app.
class SettingsController extends ChangeNotifier {
  ExperimentSettings _settings = defaultSettings;
  bool _loaded = false;

  ExperimentSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      _settings = await AppDatabase.instance.loadSettings();
    } catch (error) {
      debugPrint('Falha ao carregar configurações, usando padrões: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(ExperimentSettings next) async {
    await AppDatabase.instance.saveSettings(next);
    _settings = next;
    notifyListeners();
  }
}

class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({super.key, required SettingsController controller, required super.child})
      : super(notifier: controller);

  static SettingsController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
