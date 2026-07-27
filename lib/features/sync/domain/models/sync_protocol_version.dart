import 'package:equatable/equatable.dart';

/// Sync v2 的明确版本契约。
///
/// v1 曾允许匿名、二次 JSON 的设置读取，不能安全迁移，因此永远不会被接受。
final class SyncProtocolVersionPolicy {
  const SyncProtocolVersionPolicy._();

  static const int current = 2;
  static const int minimumSupported = 2;
  static const int maximumSupported = 2;

  static SyncProtocolCompatibility check(int? version) {
    if (version == null || version < minimumSupported) {
      return const SyncProtocolCompatibility.unsupported(
        direction: SyncProtocolVersionDirection.tooOld,
      );
    }
    if (version > maximumSupported) {
      return const SyncProtocolCompatibility.unsupported(
        direction: SyncProtocolVersionDirection.tooNew,
      );
    }
    return const SyncProtocolCompatibility.supported();
  }
}

enum SyncProtocolVersionDirection { tooOld, tooNew }

/// Discovery 和 HTTP 可共同使用的无秘密兼容性结果。
final class SyncProtocolCompatibility extends Equatable {
  const SyncProtocolCompatibility.supported()
    : isSupported = true,
      direction = null;

  const SyncProtocolCompatibility.unsupported({required this.direction})
    : isSupported = false;

  final bool isSupported;
  final SyncProtocolVersionDirection? direction;

  @override
  List<Object?> get props => [isSupported, direction];
}

/// 服务端在 UDP 中公开的协议区间；不包含任何信任或授权信息。
final class SyncProtocolRange extends Equatable {
  const SyncProtocolRange({required this.minimum, required this.maximum})
    : assert(minimum > 0),
      assert(maximum >= minimum);

  final int minimum;
  final int maximum;

  bool overlaps(SyncProtocolRange other) =>
      minimum <= other.maximum && other.minimum <= maximum;

  static const local = SyncProtocolRange(
    minimum: SyncProtocolVersionPolicy.minimumSupported,
    maximum: SyncProtocolVersionPolicy.maximumSupported,
  );

  @override
  List<Object?> get props => [minimum, maximum];
}
