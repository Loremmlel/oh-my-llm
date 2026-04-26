import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/persistence/shared_preferences_provider.dart';

Future<void> bootstrap({SharedPreferences? sharedPreferences}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences =
      sharedPreferences ?? await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const OhMyLlmApp(),
    ),
  );
}
