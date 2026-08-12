import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/utils/path_utils.dart';

void main() {
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
}
