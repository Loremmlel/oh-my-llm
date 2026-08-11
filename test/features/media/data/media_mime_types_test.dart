import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/domain/media_file_classification.dart';

void main() {
  group('extensionFromFileName', () {
    test('扩展名提取矩阵', () {
      for (final (:name, :input, :expected) in const [
        (name: 'jpg 小写', input: 'photo.jpg', expected: 'jpg'),
        (name: 'mp4 小写', input: 'video.mp4', expected: 'mp4'),
        (name: 'JPG 大小写不敏感', input: 'photo.JPG', expected: 'jpg'),
        (name: 'MP4 大小写不敏感', input: 'video.MP4', expected: 'mp4'),
        (name: 'README 无扩展名', input: 'README', expected: ''),
        (name: 'Makefile 无扩展名', input: 'Makefile', expected: ''),
        // tar.gz 取 gz，符合 lastIndexOf('.') 语义
        (name: '多点文件名取最后一段', input: 'archive.tar.gz', expected: 'gz'),
        // 以点开头的文件，lastIndexOf('.') = 0，substring(1) 得到 'gitignore'
        (name: '以点开头取点后部分', input: '.gitignore', expected: 'gitignore'),
      ]) {
        expect(extensionFromFileName(input), expected, reason: 'case: $name');
      }
    });
  });

  group('isImageFile / isVideoFile', () {
    test('全部已知扩展名分类 + 交叉与无扩展名负例', () {
      // 所有已知图片扩展名都是图片
      for (final ext in imageExtensions) {
        expect(isImageFile('photo.$ext'), isTrue, reason: 'image ext: $ext');
      }
      // 所有已知视频扩展名都是视频
      for (final ext in videoExtensions) {
        expect(isVideoFile('video.$ext'), isTrue, reason: 'video ext: $ext');
      }
      // 固定扩展名集合成员：仅循环常量本身时，未来移除某项会悄然缩小循环而测试不失败；
      // containsAll 只守住既有成员，不阻碍未来合法新增
      expect(
        imageExtensions,
        containsAll(['jpg', 'jpeg', 'png', 'webp', 'gif']),
      );
      expect(
        videoExtensions,
        containsAll(['mp4', 'mkv', 'mov', 'avi', 'webm']),
      );
      // 负例：视频不是图片、图片不是视频、无扩展名都不是
      expect(isImageFile('video.mp4'), isFalse);
      expect(isVideoFile('photo.jpg'), isFalse);
      expect(isImageFile('README'), isFalse);
      expect(isVideoFile('README'), isFalse);
    });
  });

  group('mimeTypeFromExtension', () {
    test('MIME 映射矩阵', () {
      const cases = {
        'photo.jpg': 'image/jpeg',
        'photo.jpeg': 'image/jpeg',
        'photo.png': 'image/png',
        'photo.webp': 'image/webp',
        'photo.gif': 'image/gif',
        'video.mp4': 'video/mp4',
        'video.mkv': 'video/x-matroska',
        'video.mov': 'video/quicktime',
        'video.avi': 'video/x-msvideo',
        'video.webm': 'video/webm',
        'doc.txt': 'application/octet-stream',
        'archive.zip': 'application/octet-stream',
      };

      for (final entry in cases.entries) {
        expect(
          mimeTypeFromExtension(entry.key),
          entry.value,
          reason: '${entry.key} → ${entry.value}',
        );
      }
    });
  });
}
