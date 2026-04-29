import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_network_logger.dart';

final appNetworkLoggerProvider = Provider<AppNetworkLogger>((ref) {
  throw UnimplementedError('AppNetworkLogger must be overridden at bootstrap.');
});
