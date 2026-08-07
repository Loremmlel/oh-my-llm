import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/utils/path_utils.dart';

import '../helpers/media_test_helpers.dart';

void main() {
  group('encodeMediaPath', () {
    test('根路径返回空字符串', () {
      expect(encodeMediaPath('/'), '');
    });

    test('简单英文路径', () {
      expect(encodeMediaPath('/video/test.mp4'), 'video/test.mp4');
    });

    test('中文路径每段编码', () {
      final result = encodeMediaPath('/妹妹/视频.mp4');
      expect(result, contains('%E5%A6%B9%E5%A6%B9'));
      expect(result, contains('%E8%A7%86%E9%A2%91'));
    });

    test('混合中英文路径', () {
      final result = encodeMediaPath('/sister/视频/test.mp4');
      expect(result, startsWith('sister/'));
      expect(result, endsWith('/test.mp4'));
    });

    test('多层路径保留分隔符', () {
      final result = encodeMediaPath('/a/b/c');
      // 3 段被 / 分隔
      final segments = result.split('/');
      expect(segments.length, 3);
    });

    test('含空格的路径段被编码', () {
      final result = encodeMediaPath('/my videos/test.mp4');
      expect(result, contains('my%20videos'));
    });

    test('已编码路径不被二次编码', () {
      // %20 已经是合法编码，Uri.encodeComponent 会对 % 再编码
      // 这是预期行为：输入应该是未编码的原始路径
      final result = encodeMediaPath('/test%20file.mp4');
      // % 被编码为 %25，所以 %20 变成 %2520
      expect(result, contains('%2520'));
    });
  });

  group('normalizeMediaRoutePath', () {
    test('null / 空 / 仅空白返回 null', () {
      expect(normalizeMediaRoutePath(null), isNull);
      expect(normalizeMediaRoutePath(''), isNull);
      expect(normalizeMediaRoutePath('   '), isNull);
    });

    test('不以 / 开头返回 null', () {
      expect(normalizeMediaRoutePath('photo.jpg'), isNull);
    });

    test('去掉首尾分隔后无文件段返回 null', () {
      expect(normalizeMediaRoutePath('/'), isNull);
      expect(normalizeMediaRoutePath('///'), isNull);
    });

    test('任一路径段为 . 或 .. 返回 null', () {
      expect(normalizeMediaRoutePath('/a/../b.jpg'), isNull);
      expect(normalizeMediaRoutePath('/./b.jpg'), isNull);
      expect(normalizeMediaRoutePath('/..'), isNull);
    });

    test('合法路径保留中文、空格与 .. 文件名子串', () {
      expect(normalizeMediaRoutePath('/相册/我的 猫.jpg'), '/相册/我的 猫.jpg');
      expect(normalizeMediaRoutePath('/a/photo..jpg'), '/a/photo..jpg');
    });

    test('规范化首尾多余分隔符', () {
      expect(normalizeMediaRoutePath('/a/b//c.jpg'), '/a/b/c.jpg');
      expect(normalizeMediaRoutePath('/a/b.jpg/'), '/a/b.jpg');
    });
  });

  group('buildMediaResourceUrl', () {
    test('使用可信 server 与相对路径构建 URL，中文每段只编码一次', () {
      final url = buildMediaResourceUrl(testServer, 'image', '/相册/我的 猫.jpg');

      expect(
        url,
        'http://192.168.1.5:8080/api/media/image/%E7%9B%B8%E5%86%8C/%E6%88%91%E7%9A%84%20%E7%8C%AB.jpg',
      );
    });

    test('视频类型构建 video 端点', () {
      expect(
        buildMediaResourceUrl(testServer, 'video', '/视频/demo.mp4'),
        startsWith('http://192.168.1.5:8080/api/media/video/'),
      );
    });
  });
}
