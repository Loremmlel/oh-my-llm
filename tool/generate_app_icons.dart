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
  final icon = _readMaster('siyue-icon.png');
  final flower = img.trim(_readMaster('siyue-icon-foreground.png'));

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

img.Image _resize(img.Image image, int size) => img.copyResize(
  image,
  width: image.width >= image.height ? size : null,
  height: image.height > image.width ? size : null,
  interpolation: img.Interpolation.average,
);
