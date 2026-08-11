import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/utils/path_utils.dart';

import '../helpers/media_test_helpers.dart';

void main() {
  group('encodeMediaPath', () {
    test('矩阵：根/英文/中文/混合/多段/空格/已编码输入', () {
      for (final (:name, :input, :expected) in const [
        (name: '根路径返回空字符串', input: '/', expected: ''),
        (name: '简单英文路径', input: '/video/test.mp4', expected: 'video/test.mp4'),
        (
          name: '中文路径每段编码',
          input: '/妹妹/视频.mp4',
          expected: '%E5%A6%B9%E5%A6%B9/%E8%A7%86%E9%A2%91.mp4',
        ),
        (
          name: '混合中英文路径',
          input: '/sister/视频/test.mp4',
          expected: 'sister/%E8%A7%86%E9%A2%91/test.mp4',
        ),
        (name: '多段路径保留分隔符', input: '/a/b/c', expected: 'a/b/c'),
        (
          name: '含空格的路径段被编码',
          input: '/my videos/test.mp4',
          expected: 'my%20videos/test.mp4',
        ),
        // % 被 Uri.encodeComponent 编码为 %25，所以 %20 变成 %2520
        // 这是预期行为：输入应该是未编码的原始路径
        (
          name: '已编码输入被转义',
          input: '/test%20file.mp4',
          expected: 'test%2520file.mp4',
        ),
      ]) {
        expect(encodeMediaPath(input), expected, reason: 'case: $name');
      }
    });
  });

  group('normalizeMediaRoutePath', () {
    test('非法输入矩阵：null/空/空白/缺斜杠/根/./..', () {
      for (final (:name, :input) in const [
        (name: 'null', input: null),
        (name: '空字符串', input: ''),
        (name: '仅空白', input: '   '),
        (name: '不以 / 开头', input: 'photo.jpg'),
        (name: '根路径', input: '/'),
        (name: '仅分隔符', input: '///'),
        (name: '含 . 段', input: '/./b.jpg'),
        (name: '含 .. 段', input: '/a/../b.jpg'),
        (name: '仅 .. 段', input: '/..'),
      ]) {
        expect(normalizeMediaRoutePath(input), isNull, reason: 'case: $name');
      }
    });

    test('合法路径矩阵：中文/空格、.. 子串、重复分隔符、尾分隔符', () {
      for (final (:name, :input, :expected) in const [
        (name: '中文与空格', input: '/相册/我的 猫.jpg', expected: '/相册/我的 猫.jpg'),
        (name: '.. 文件名子串', input: '/a/photo..jpg', expected: '/a/photo..jpg'),
        (name: '重复分隔符', input: '/a/b//c.jpg', expected: '/a/b/c.jpg'),
        (name: '末尾分隔符', input: '/a/b.jpg/', expected: '/a/b.jpg'),
      ]) {
        expect(normalizeMediaRoutePath(input), expected, reason: 'case: $name');
      }
    });
  });

  group('buildMediaResourceUrl', () {
    test('矩阵：image 中文端点与 video 英文端点', () {
      for (final (:name, :type, :input, :expected) in const [
        (
          name: 'image + 中文路径只编码一次',
          type: 'image',
          input: '/相册/我的 猫.jpg',
          expected:
              'http://192.168.1.5:8080/api/media/image/'
              '%E7%9B%B8%E5%86%8C/%E6%88%91%E7%9A%84%20%E7%8C%AB.jpg',
        ),
        (
          name: 'video + 英文路径',
          type: 'video',
          input: '/video/demo.mp4',
          expected: 'http://192.168.1.5:8080/api/media/video/video/demo.mp4',
        ),
      ]) {
        expect(
          buildMediaResourceUrl(testServer, type, input),
          expected,
          reason: 'case: $name',
        );
      }
    });
  });
}
