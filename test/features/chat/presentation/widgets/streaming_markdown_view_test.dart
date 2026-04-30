import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/streaming_markdown_view.dart';

void main() {
  group('normalizeLatexLikeTextForDisplay', () {
    test('常见箭头命令会降级为可读符号', () {
      final output = normalizeLatexLikeTextForDisplay(
        r'方向：$\LeftArrow$、$\RightArrow$、$\LeftRightArrow$',
      );

      expect(output, '方向：←、→、↔');
    });

    test('未知命令保持原样，避免误改', () {
      final output = normalizeLatexLikeTextForDisplay(r'未知：$\UnknownSymbol$');

      expect(output, r'未知：$\UnknownSymbol$');
    });

    test('非 TeX 文本不受影响', () {
      final output = normalizeLatexLikeTextForDisplay('普通文本 123');
      expect(output, '普通文本 123');
    });
  });
}
