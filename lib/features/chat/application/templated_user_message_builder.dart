import '../../settings/domain/models/template_prompt.dart';
import '../../settings/domain/template_prompt_parser.dart';
import '../domain/models/chat_message.dart';

/// 发送前组装好的用户消息内容及其展示片段。
class TemplatedUserMessage {
  const TemplatedUserMessage({
    required this.content,
    this.userMessageSegments = const [],
  });

  final String content;
  final List<UserMessageSegment> userMessageSegments;
}

/// 将正文与模板提示词渲染为最终要发送的用户消息。
TemplatedUserMessage buildTemplatedUserMessage({
  required String body,
  required TemplatePrompt? templatePrompt,
  Map<String, String> variableValues = const {},
}) {
  final normalizedBody = body.trim();
  if (templatePrompt == null) {
    return TemplatedUserMessage(content: normalizedBody);
  }

  final segments = <UserMessageSegment>[];
  final contentBuffer = StringBuffer();

  void appendSegment(String text, UserMessageSegmentKind kind) {
    if (text.isEmpty) {
      return;
    }
    contentBuffer.write(text);
    if (segments.isNotEmpty && segments.last.kind == kind) {
      final previous = segments.removeLast();
      segments.add(
        UserMessageSegment(text: '${previous.text}$text', kind: kind),
      );
      return;
    }
    segments.add(UserMessageSegment(text: text, kind: kind));
  }

  void appendRenderedTemplateContent() {
    var cursor = 0;
    for (final match in matchTemplatePromptPlaceholders(
      templatePrompt.content,
    )) {
      final start = match.start;
      final end = match.end;
      if (start > cursor) {
        appendSegment(
          templatePrompt.content.substring(cursor, start),
          UserMessageSegmentKind.template,
        );
      }

      final spec = parseVariableSpec(match.group(1)?.trim() ?? '');
      final variableName = spec.name;
      if (variableName == templatePromptBodyVariableName) {
        appendSegment(normalizedBody, UserMessageSegmentKind.body);
      } else {
        appendSegment(
          variableValues[variableName]?.trim() ?? '',
          UserMessageSegmentKind.template,
        );
      }
      cursor = end;
    }

    if (cursor < templatePrompt.content.length) {
      appendSegment(
        templatePrompt.content.substring(cursor),
        UserMessageSegmentKind.template,
      );
    }
  }

  if (!templatePrompt.containsBodyVariable) {
    appendSegment(normalizedBody, UserMessageSegmentKind.body);
    if (normalizedBody.isNotEmpty && templatePrompt.content.trim().isNotEmpty) {
      appendSegment('\n', UserMessageSegmentKind.body);
    }
  }

  appendRenderedTemplateContent();
  return TemplatedUserMessage(
    content: contentBuffer.toString(),
    userMessageSegments: List.unmodifiable(segments),
  );
}
