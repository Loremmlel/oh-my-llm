import 'dart:math';

import '../domain/models/video_item.dart';

/// 按最近抽中的目录降权；只在抽取新视频时推进冷却，回看历史不影响权重。
class DirectoryWeightedShuffle {
  DirectoryWeightedShuffle(this.rootPath, {Random? random})
    : _random = random ?? Random();

  final String rootPath;
  final Random _random;
  final Map<String, double> _penalties = {};

  /// 从尚未播放的 [startIndex] 及其后续项中抽取，调用方负责将它移到播放位置。
  int pickIndex(List<VideoItem> videos, {int startIndex = 0}) {
    final weights = <double>[];
    var total = 0.0;
    for (var i = startIndex; i < videos.length; i++) {
      var penalty = 0.0;
      for (final directory in _ancestors(videos[i].relativePath)) {
        penalty = max(penalty, _penalties[directory] ?? 0);
      }
      // 取最强惩罚而不逐层相乘，避免深目录被重复压低概率。
      final weight = 1 - penalty;
      weights.add(weight);
      total += weight;
    }

    var ticket = _random.nextDouble() * total;
    var selected = videos.length - 1;
    for (var i = 0; i < weights.length; i++) {
      ticket -= weights[i];
      if (ticket < 0) {
        selected = startIndex + i;
        break;
      }
    }

    // 每次新抽取让旧惩罚减少 20%，约三次减半；微小惩罚直接清除。
    _penalties.updateAll((_, penalty) => penalty * 0.8);
    _penalties.removeWhere((_, penalty) => penalty < 0.01);
    var penalty = 0.8;
    for (final directory in _ancestors(videos[selected].relativePath)) {
      _penalties[directory] = max(_penalties[directory] ?? 0, penalty);
      penalty *= 0.5;
    }
    return selected;
  }

  Iterable<String> _ancestors(String path) sync* {
    var end = path.lastIndexOf('/');
    while (end > 0) {
      final directory = path.substring(0, end);
      // 抽取范围的根目录为所有候选共享，不参与降权。
      if (directory == rootPath) break;
      yield directory;
      end = directory.lastIndexOf('/');
    }
  }
}
