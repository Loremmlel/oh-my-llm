import 'dart:math';

final Random _random = Random.secure();

String generateEntityId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final suffix = _random.nextInt(1 << 32).toRadixString(16);
  return '$timestamp-$suffix';
}
