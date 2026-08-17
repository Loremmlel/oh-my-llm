import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';
import '../../domain/models/chat_message.dart';

/// 发送前组装好的用户消息内容及其展示片段。
class TemplatedUserMessage {
  const TemplatedUserMessage({
    required this.content,
    this.userMessageSegments = const [],
  });

  final String content;
  final List<UserMessageSegment> userMessageSegments;
}

/// 模板渲染的构建结果：成功携带消息与有效值快照，失败携带编译诊断或值错误。
sealed class TemplatedUserMessageBuildResult {
  const TemplatedUserMessageBuildResult();
}

final class TemplatedUserMessageBuildSuccess
    extends TemplatedUserMessageBuildResult {
  const TemplatedUserMessageBuildSuccess({
    required this.message,
    required this.effectiveVariableValues,
  });

  final TemplatedUserMessage message;
  final Map<String, String> effectiveVariableValues;
}

final class TemplatedUserMessageBuildFailure
    extends TemplatedUserMessageBuildResult {
  const TemplatedUserMessageBuildFailure({
    this.diagnostics = const [],
    this.valueErrors = const [],
  });

  final List<TemplatePromptDiagnostic> diagnostics;
  final List<TemplatePromptValueError> valueErrors;
}

/// 将正文与模板提示词渲染为最终要发送的用户消息。
///
/// 编译结果由调用方经 [compilation] 传入，本函数只做求值与片段适配，绝不
/// 解析模板源码。模板不存在时返回裁剪后的正文；模板存在但编译缺失或无效时
/// 直接失败返回，不在 builder 内部重新编译。
TemplatedUserMessageBuildResult buildTemplatedUserMessage({
  required String body,
  required TemplatePrompt? templatePrompt,
  TemplatePromptCompilation? compilation,
  Map<String, String> variableValues = const {},
}) {
  final normalizedBody = body.trim();
  if (templatePrompt == null) {
    return TemplatedUserMessageBuildSuccess(
      message: TemplatedUserMessage(content: normalizedBody),
      effectiveVariableValues: const {},
    );
  }

  final program = compilation?.program;
  if (compilation == null || !compilation.isValid || program == null) {
    return TemplatedUserMessageBuildFailure(
      diagnostics: compilation?.diagnostics ?? const [],
    );
  }

  final evaluation = evaluateTemplatePrompt(
    program: program,
    body: normalizedBody,
    variableValues: variableValues,
  );
  if (!evaluation.isValid) {
    return TemplatedUserMessageBuildFailure(
      valueErrors: evaluation.valueErrors,
    );
  }

  final segments = <UserMessageSegment>[];
  for (final chunk in evaluation.chunks) {
    final kind = switch (chunk.kind) {
      TemplatePromptOutputChunkKind.template => UserMessageSegmentKind.template,
      TemplatePromptOutputChunkKind.body => UserMessageSegmentKind.body,
    };
    if (chunk.text.isEmpty) {
      continue;
    }
    if (segments.isNotEmpty && segments.last.kind == kind) {
      final previous = segments.removeLast();
      segments.add(
        UserMessageSegment(text: '${previous.text}${chunk.text}', kind: kind),
      );
    } else {
      segments.add(UserMessageSegment(text: chunk.text, kind: kind));
    }
  }

  return TemplatedUserMessageBuildSuccess(
    message: TemplatedUserMessage(
      content: evaluation.content,
      userMessageSegments: List.unmodifiable(segments),
    ),
    effectiveVariableValues: Map<String, String>.unmodifiable(
      evaluation.effectiveValues,
    ),
  );
}
