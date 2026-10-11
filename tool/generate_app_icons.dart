import 'dart:io';

import 'package:image/image.dart' as img;

const _branding = 'assets/branding';
const _androidRes = 'android/app/src/main/res';
const _windowsSizes = [
  16,
  20,
  24,
  30,
  32,
  36,
  40,
  48,
  60,
  64,
  72,
  80,
  96,
  128,
  256,
];
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main(List<String> arguments) {
  final check = arguments.contains('--check');
  if (arguments.contains('--from-original')) {
    if (check) {
      throw ArgumentError('--from-original 与 --check 不能同时使用。');
    }
    _cutOutOriginal();
  }
  final icon = _readMaster('siyue-icon.png');
  final foregroundMaster = _readMaster('siyue-icon-foreground.png');
  final original = img.decodePng(
    File('$_branding/siyue-icon-original.png').readAsBytesSync(),
  )!;
  _checkOriginalPixels(original, icon);
  _checkOriginalPixels(original, foregroundMaster);
  final flower = img.trim(foregroundMaster, mode: img.TrimMode.transparent);

  void output(String path, List<int> bytes) {
    final file = File(path);
    if (check) {
      final actual = file.existsSync() ? file.readAsBytesSync() : <int>[];
      if (actual.length != bytes.length ||
          Iterable<int>.generate(bytes.length)
              .any((index) => actual[index] != bytes[index])) {
        stderr.writeln('图标资源需要重新生成：$path');
        exitCode = 1;
      }
    } else {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    }
  }

  output(
    'windows/runner/resources/app_icon.ico',
    img.IcoEncoder().encodeImages([
      for (final size in _windowsSizes) _resize(icon, size),
    ]),
  );

  for (final entry in _densities.entries) {
    final directory = '$_androidRes/mipmap-${entry.key}';
    output(
      '$directory/ic_launcher.png',
      img.encodePng(_resize(icon, (48 * entry.value).round())),
    );

    // 花朵限制在中央 64dp 内，给系统的 66dp 安全区域保留抗锯齿余量。
    final layerSize = (108 * entry.value).round();
    final foreground = img.Image(
      width: layerSize,
      height: layerSize,
      numChannels: 4,
    );
    final scaledFlower = _resize(flower, (64 * entry.value).round());
    img.compositeImage(
      foreground,
      scaledFlower,
      dstX: (layerSize - scaledFlower.width) ~/ 2,
      dstY: (layerSize - scaledFlower.height) ~/ 2,
    );
    output('$directory/ic_launcher_foreground.png', img.encodePng(foreground));
  }

  if (exitCode == 0) {
    stdout.writeln(
      check ? 'Windows / Android 图标资源校验通过。' : 'Windows / Android 图标资源已生成。',
    );
  }
}

void _cutOutOriginal() {
  // 原图的花瓣不在四角，限定区域后白色色键不会误伤奶油色纸面。
  const corners = '(lt(X,W/4)+gte(X,3*W/4))*(lt(Y,H/4)+gte(Y,3*H/4))';
  const colors = "r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'";
  final filters = {
    'siyue-icon.png':
        "format=rgba,colorkey=0xffffff:0.01:0.06,"
        "geq=$colors:a='if($corners,alpha(X,Y),255)':interpolation=nearest,"
        'format=rgba',
    'siyue-icon-foreground.png':
        "format=rgba,colorkey=0x123522:0.12:0.08,"
        "geq=$colors:a='if($corners,0,alpha(X,Y))':interpolation=nearest,"
        'format=rgba',
  };
  for (final entry in filters.entries) {
    final result = Process.runSync('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      '$_branding/siyue-icon-original.png',
      '-vf',
      entry.value,
      '-frames:v',
      '1',
      '-update',
      '1',
      '-pix_fmt',
      'rgba',
      '$_branding/${entry.key}',
    ]);
    if (result.exitCode != 0) {
      throw StateError('FFmpeg 抠图失败：${result.stderr}');
    }
  }
}

void _checkOriginalPixels(img.Image original, img.Image cutout) {
  if (original.width != cutout.width || original.height != cutout.height) {
    throw StateError('透明主图必须保留原图尺寸。');
  }
  for (final pixel in original) {
    final actual = cutout.getPixel(pixel.x, pixel.y);
    if (pixel.r != actual.r || pixel.g != actual.g || pixel.b != actual.b) {
      throw StateError('透明主图改变了原图 RGB：(${pixel.x}, ${pixel.y})。');
    }
  }
}

img.Image _readMaster(String name) {
  final image = img.decodePng(File('$_branding/$name').readAsBytesSync());
  if (image == null ||
      image.width != image.height ||
      image.numChannels != 4 ||
      image.getPixel(0, 0).a != 0 ||
      image.getPixel(image.width - 1, 0).a != 0 ||
      image.getPixel(0, image.height - 1).a != 0 ||
      image.getPixel(image.width - 1, image.height - 1).a != 0 ||
      image.getPixel(image.width ~/ 2, image.height ~/ 2).a == 0) {
    throw StateError('$name 必须是四角透明、中心可见的正方形 RGBA PNG。');
  }
  return image;
}

img.Image _resize(img.Image image, int size) {
  // 预乘后缩放，避免透明像素保留的白色或绿色 RGB 渗入可见边缘。
  final premultiplied = image.convert(format: img.Format.float32);
  for (final pixel in premultiplied) {
    pixel
      ..r *= pixel.a
      ..g *= pixel.a
      ..b *= pixel.a;
  }
  final resized = img.copyResize(
    premultiplied,
    width: image.width >= image.height ? size : null,
    height: image.height > image.width ? size : null,
    interpolation: img.Interpolation.average,
  );
  for (final pixel in resized) {
    if (pixel.a > 0) {
      pixel
        ..r /= pixel.a
        ..g /= pixel.a
        ..b /= pixel.a;
    }
  }
  return resized.convert(format: img.Format.uint8);
}
