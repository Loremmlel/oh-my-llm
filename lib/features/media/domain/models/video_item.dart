/// 递归扫描返回的轻量级视频条目。
class VideoItem {
  final String name;
  final String relativePath;

  const VideoItem({required this.name, required this.relativePath});

  Map<String, dynamic> toJson() => {
        'name': name,
        'relativePath': relativePath,
      };

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      name: json['name'] as String,
      relativePath: json['relativePath'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoItem &&
          name == other.name &&
          relativePath == other.relativePath;

  @override
  int get hashCode => Object.hash(name, relativePath);
}
