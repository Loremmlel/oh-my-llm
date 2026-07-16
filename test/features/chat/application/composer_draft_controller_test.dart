import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';

void main() {
  late ProviderContainer container;
  late ComposerDraftController controller;

  setUp(() {
    container = ProviderContainer();
    controller = container.read(composerDraftProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('正文草稿按会话隔离', () {
    test('setBody / readBody 按会话隔离', () {
      controller.setBody('conv-a', '草稿 A');
      controller.setBody('conv-b', '草稿 B');

      expect(controller.readBody('conv-a'), '草稿 A');
      expect(controller.readBody('conv-b'), '草稿 B');
      expect(controller.readBody('conv-missing'), isNull);
    });

    test('clearBody 只清除目标会话', () {
      controller.setBody('conv-a', '草稿 A');
      controller.setBody('conv-b', '草稿 B');

      controller.clearBody('conv-a');

      expect(controller.readBody('conv-a'), isNull);
      expect(controller.readBody('conv-b'), '草稿 B');
    });
  });

  group('模板变量草稿按模板隔离', () {
    test('setTemplateVariable / readTemplateVariable 按 templateId+变量名隔离', () {
      controller.setTemplateVariable('tpl-1', 'name', '小柚');
      controller.setTemplateVariable('tpl-2', 'name', '主人');

      expect(controller.readTemplateVariable('tpl-1', 'name'), '小柚');
      expect(controller.readTemplateVariable('tpl-2', 'name'), '主人');
      expect(controller.readTemplateVariable('tpl-1', 'missing'), isNull);
    });
  });
}
