import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';

void main() {
  test('source values compare by immutable local root or remote base URI', () {
    expect(
      const LocalMediaLibrarySource(r'D:\Media'),
      const LocalMediaLibrarySource(r'D:\Media'),
    );
    expect(
      RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')),
      RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')),
    );
  });

  test('resource rejects the wrong URI scheme', () {
    expect(
      () => LocalMediaResource(Uri.parse('http://localhost/a.jpg')),
      throwsArgumentError,
    );
    expect(
      () => NetworkMediaResource(Uri.file(r'D:\Media\a.jpg')),
      throwsArgumentError,
    );
  });

  test('network headers are copied and cannot be mutated', () {
    final headers = {'Authorization': 'peer'};
    final resource = NetworkMediaResource(
      Uri.parse('http://192.168.1.5:8080/api/media/image/a.jpg'),
      headers: headers,
    );
    headers['Authorization'] = 'changed';
    expect(resource.headers['Authorization'], 'peer');
    expect(() => resource.headers['x'] = 'y', throwsUnsupportedError);
  });

  test('thumbnail request equality covers every cache invalidator', () {
    const base = MediaThumbnailRequest(
      relativePath: '/a.jpg',
      sizeBytes: 10,
      lastModified: 20,
      hasThumbnail: true,
    );
    expect(
      base,
      const MediaThumbnailRequest(
        relativePath: '/a.jpg',
        sizeBytes: 10,
        lastModified: 20,
        hasThumbnail: true,
      ),
    );
    expect(
      base,
      isNot(
        const MediaThumbnailRequest(
          relativePath: '/a.jpg',
          sizeBytes: 11,
          lastModified: 20,
          hasThumbnail: true,
        ),
      ),
    );
  });
}
