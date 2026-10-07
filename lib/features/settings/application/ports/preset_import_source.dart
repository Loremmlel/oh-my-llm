import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef SelectedPresetFile = ({String name, String text});

final presetImportSourceProvider =
    Provider<Future<SelectedPresetFile?> Function()>((ref) {
      throw UnimplementedError('预设文件选择必须由应用装配');
    });
