import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/data/media_mime_types.dart';

void main() {
  group('extensionFromFileName', () {
    for (final entry in {'photo.jpg': 'jpg', 'video.mp4': 'mp4'}.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(extensionFromFileName(entry.key), entry.value);
      });
    }

    test('大小写不敏感', () {
      expect(extensionFromFileName('photo.JPG'), 'jpg');
      expect(extensionFromFileName('video.MP4'), 'mp4');
    });

    test('无扩展名返回空字符串', () {
      expect(extensionFromFileName('README'), '');
      expect(extensionFromFileName('Makefile'), '');
    });

    // tar.gz 取 gz，符合 lastIndexOf('.') 语义
    test('多点文件名取最后一个点后部分', () {
      expect(extensionFromFileName('archive.tar.gz'), 'gz');
    });

    // 以点开头的文件，lastIndexOf('.') = 0，substring(1) 得到 'gitignore'
    test('以点开头取点后部分为扩展名', () {
      expect(extensionFromFileName('.gitignore'), 'gitignore');
    });
  });

  group('isImageFile', () {
    for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'gif']) {
      test('$ext 是图片', () {
        expect(isImageFile('photo.$ext'), isTrue);
      });
    }

    test('视频不是图片', () {
      expect(isImageFile('video.mp4'), isFalse);
    });

    test('无扩展名不是图片', () {
      expect(isImageFile('README'), isFalse);
    });
  });

  group('isVideoFile', () {
    for (final ext in ['mp4', 'mkv', 'mov', 'avi', 'webm']) {
      test('$ext 是视频', () {
        expect(isVideoFile('video.$ext'), isTrue);
      });
    }

    test('图片不是视频', () {
      expect(isVideoFile('photo.jpg'), isFalse);
    });

    test('无扩展名不是视频', () {
      expect(isVideoFile('README'), isFalse);
    });
  });

  group('mimeTypeFromExtension', () {
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
      test('${entry.key} → ${entry.value}', () {
        expect(mimeTypeFromExtension(entry.key), entry.value);
      });
    }
  });
}
