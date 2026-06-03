/// 格式化为 YYYY-MM-DD。
String formatDateOnly(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// 格式化为 YYYY-MM-DD HH:mm。
String formatDateTime(DateTime dt) =>
    '${formatDateOnly(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
