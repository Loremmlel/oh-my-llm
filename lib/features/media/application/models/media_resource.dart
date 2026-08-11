/// 已解析的媒体资源：本地文件 URI 或远程 HTTP(S) URI。
library;

import 'package:equatable/equatable.dart';

sealed class MediaResource extends Equatable {
  const MediaResource();
  Uri get uri;
}

final class LocalMediaResource extends MediaResource {
  LocalMediaResource(this.uri) {
    if (!uri.isAbsolute || uri.scheme != 'file') {
      throw ArgumentError.value(uri, 'uri', '必须是绝对 file URI');
    }
  }
  @override
  final Uri uri;
  @override
  List<Object?> get props => [uri];
}

final class NetworkMediaResource extends MediaResource {
  NetworkMediaResource(this.uri, {Map<String, String> headers = const {}})
    : headers = Map.unmodifiable(headers) {
    if (!uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError.value(uri, 'uri', '必须是绝对 HTTP(S) URI');
    }
  }
  @override
  final Uri uri;
  final Map<String, String> headers;
  @override
  List<Object?> get props => [uri, headers];
}
