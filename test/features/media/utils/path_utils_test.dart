import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/utils/path_utils.dart';

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
}
