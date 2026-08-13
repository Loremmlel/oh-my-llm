import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/media_image_resource_view.dart';

void main() {
  testWidgets(
    'local resource uses FileImage and network resource uses NetworkImage headers',
    (tester) async {
      // testWidgets 的 fake-async zone 内真实异步 IO 永不完成，临时目录
      // 一律用同步 API 创建；图片解码不依赖文件存在（只断言 ImageProvider）。
      final dir = Directory.systemTemp.createTempSync('omll_image_view_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final file = File('${dir.path}${Platform.pathSeparator}a.jpg')
        ..writeAsBytesSync(pngBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaImageResourceView(
            resource: LocalMediaResource(file.absolute.uri),
            fit: BoxFit.contain,
          ),
        ),
      );
      expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());

      await tester.pumpWidget(
        MaterialApp(
          home: MediaImageResourceView(
            resource: NetworkMediaResource(
              Uri.parse('http://peer/api/media/image/a.jpg'),
              headers: const {'X-Peer': 'token'},
            ),
            fit: BoxFit.contain,
            // 测试环境 mock HTTP 恒返回 400：errorBuilder 吞掉解码错误，
            // 本用例只验证 ImageProvider 的选择与 header 透传。
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
      final provider =
          tester.widget<Image>(find.byType(Image)).image as NetworkImage;
      expect(provider.headers, {'X-Peer': 'token'});
    },
  );
}
