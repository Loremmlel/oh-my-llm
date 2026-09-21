import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../../application/ports/preset_import_source.dart';

Future<SelectedPresetFile?> pickPresetImportFile() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    dialogTitle: '导入 SillyTavern 预设',
  );
  if (files.isEmpty) return null;
  final file = files.single;
  final length = await file.length();
  if (length == null || length > 16 * 1024 * 1024) {
    throw const FormatException('无法读取文件或文件超过 16 MiB');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > 16 * 1024 * 1024) {
    throw const FormatException('文件超过 16 MiB');
  }
  return (name: file.name, text: utf8.decode(bytes));
}
