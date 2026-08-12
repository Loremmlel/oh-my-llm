import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_video_controller_factory.dart';

void main() {
  test('local uses file data source and remote preserves headers', () {
    final local = createMediaVideoController(
      LocalMediaResource(Uri.file(r'D:\Media\demo.mp4', windows: true)),
    );
    expect(local.dataSourceType.name, 'file');
    expect(local.dataSource, contains('demo.mp4'));

    final remote = createMediaVideoController(NetworkMediaResource(
      Uri.parse('http://peer/api/media/video/demo.mp4'),
      headers: const {'X-Peer': 'token'},
    ));
    expect(remote.dataSourceType.name, 'network');
    expect(remote.httpHeaders, {'X-Peer': 'token'});
  });
}
