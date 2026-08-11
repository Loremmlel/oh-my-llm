/// 媒体库来源的传输中立抽象：本地目录根或远程 base URI。
library;

import 'package:equatable/equatable.dart';

enum MediaSourceKind { local, remote }

sealed class MediaLibrarySource extends Equatable {
  const MediaLibrarySource();
  MediaSourceKind get kind;
}

final class LocalMediaLibrarySource extends MediaLibrarySource {
  const LocalMediaLibrarySource(this.rootDirectory);
  final String rootDirectory;
  @override
  MediaSourceKind get kind => MediaSourceKind.local;
  @override
  List<Object?> get props => [rootDirectory];
}

final class RemoteMediaLibrarySource extends MediaLibrarySource {
  const RemoteMediaLibrarySource(this.baseUri);
  final Uri baseUri;
  @override
  MediaSourceKind get kind => MediaSourceKind.remote;
  @override
  List<Object?> get props => [baseUri];
}
