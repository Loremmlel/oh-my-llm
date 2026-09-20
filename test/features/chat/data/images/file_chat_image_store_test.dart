import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oh_my_llm/features/chat/data/images/file_chat_image_store.dart';

void main() {
  late Directory directory;
  late FileChatImageStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-images-test-');
    store = FileChatImageStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('图片落盘后可重新打开并按内容复用且规范化尺寸', () async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2100, height: 2)),
    );
    final first = await store.importImage(bytes, name: '测试.png');
    final second = await store.importImage(bytes, name: '再次选择.png');
    expect(first.id, second.id);
    expect(first.width, 2048);
    final reopened = FileChatImageStore(directory);
    final stored = await reopened.read(first.id);
    expect(img.decodeImage(stored)!.width, first.width);
    expect(stored.length, first.byteLength);
    expect(await directory.list().length, 1);
  });

  test('格式伪装、目录穿越、丢失与损坏图片均显式失败', () async {
    await expectLater(
      store.importImage(Uint8List.fromList([1, 2, 3]), name: '伪装.png'),
      throwsFormatException,
    );
    await expectLater(store.read('../secret'), throwsFormatException);
    await expectLater(store.read('0' * 64), throwsFormatException);
    final image = await store.importImage(
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
      name: '图片.png',
    );
    await File('${directory.path}/${image.id}').writeAsBytes([1, 2, 3]);
    await expectLater(store.read(image.id), throwsFormatException);
    final repaired = await store.importImage(
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
      name: '重新添加.png',
    );
    expect(repaired.id, image.id);
    expect(await store.read(image.id), isNotEmpty);
  });
}
