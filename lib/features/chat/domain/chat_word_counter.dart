/// 聊天场景使用的字数统计工具。
///
/// 规则与聊天气泡保持一致：
/// - 一个 CJK 汉字 = 1 字
/// - 一个连续英文字母序列 = 1 字
/// - 标点、空格、数字、其他字符不计
class StreamingChatWordCounter {
  int _count = 0;
  int _processedLength = 0;
  bool _inEnglishWord = false;

  int get count => _count;

  void update(String fullText) {
    if (fullText.length < _processedLength) {
      reset();
    }
    for (var i = _processedLength; i < fullText.length; i += 1) {
      final c = fullText[i];
      if (isCjkCharacter(c)) {
        _count += 1;
        _inEnglishWord = false;
      } else if (isEnglishLetter(c)) {
        if (!_inEnglishWord) {
          _count += 1;
          _inEnglishWord = true;
        }
      } else {
        _inEnglishWord = false;
      }
    }
    _processedLength = fullText.length;
  }

  void reset() {
    _count = 0;
    _processedLength = 0;
    _inEnglishWord = false;
  }
}

int countChatWords(String text) {
  final counter = StreamingChatWordCounter();
  counter.update(text);
  return counter.count;
}

bool isCjkCharacter(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x4e00 && code <= 0x9fff) ||
      (code >= 0x3400 && code <= 0x4dbf) ||
      (code >= 0xf900 && code <= 0xfaff);
}

bool isEnglishLetter(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
}
