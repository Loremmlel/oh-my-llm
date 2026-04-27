import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('AppDatabase must be overridden at bootstrap.');
});
