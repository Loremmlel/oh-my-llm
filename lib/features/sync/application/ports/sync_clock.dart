import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class SyncClock {
  DateTime now();
}

final class SystemSyncClock implements SyncClock {
  const SystemSyncClock();

  @override
  DateTime now() => DateTime.now();
}

final syncClockProvider = Provider<SyncClock>((ref) => const SystemSyncClock());
