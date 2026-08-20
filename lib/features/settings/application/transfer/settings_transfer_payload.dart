Map<String, dynamic> decodeTransferObject(Object? payload, String label) {
  if (payload is! Map) {
    throw FormatException('$label 传输值必须是对象');
  }
  try {
    return Map<String, dynamic>.from(payload);
  } on Object {
    throw FormatException('$label 传输值必须是字符串键对象');
  }
}

List<Map<String, dynamic>> decodeTransferObjectList(
  Object? payload,
  String label,
) {
  if (payload is! List) {
    throw FormatException('$label 传输值必须是列表');
  }
  return payload
      .map((item) {
        if (item is! Map) {
          throw FormatException('$label 列表元素必须是对象');
        }
        try {
          return Map<String, dynamic>.from(item);
        } on Object {
          throw FormatException('$label 列表元素必须是字符串键对象');
        }
      })
      .toList(growable: false);
}
