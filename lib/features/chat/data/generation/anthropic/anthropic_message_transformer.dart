import 'package:equatable/equatable.dart';

import '../../../application/ports/chat_generation_client.dart';
import '../../../domain/models/chat_message.dart';

/// Anthropic 消息转换结果。
///
/// [system] 为连续的 leading System 消息内容（单个换行符连接），无 leading
/// System 时为 null；[messages] 中 role 仅剩 user/assistant，且不存在相邻
/// 同角色消息。
class AnthropicTransformedMessages extends Equatable {
  const AnthropicTransformedMessages({this.system, required this.messages});

  final String? system;
  final List<AnthropicTransformedMessage> messages;

  @override
  List<Object?> get props => [system, messages];
}

/// 转换后的一条 Anthropic 消息（role 为协议侧字符串 user/assistant）。
class AnthropicTransformedMessage extends Equatable {
  const AnthropicTransformedMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  @override
  List<Object?> get props => [role, content];
}

/// 把协议中立消息列表转换为 Anthropic Messages 协议形状（纯函数）。
///
/// 确定性规则：
/// 1. 从索引 0 开始消费连续的 System 消息，用单个换行符连接写入顶层
///    `system`；无 leading System 时省略。
/// 2. 从第一条非 System 消息开始，后续出现的 System 一律转为 User。
/// 3. 相邻同角色消息合并，内容用单个换行符连接。
///
/// 只消费 [ChatRequestMessage.content]，历史 reasoning 不参与转换。
AnthropicTransformedMessages transformAnthropicMessages(
  List<ChatRequestMessage> messages,
) {
  var index = 0;
  final leadingSystem = <String>[];
  while (index < messages.length &&
      messages[index].role == ChatMessageRole.system) {
    leadingSystem.add(messages[index].content);
    index++;
  }

  // 其余消息：System 转为 User，相邻同角色用单个换行符合并。
  final roles = <String>[];
  final contents = <String>[];
  for (final message in messages.skip(index)) {
    final role = message.role == ChatMessageRole.system
        ? 'user'
        : message.role.apiValue;
    if (roles.isNotEmpty && roles.last == role) {
      contents[contents.length - 1] = '${contents.last}\n${message.content}';
    } else {
      roles.add(role);
      contents.add(message.content);
    }
  }

  return AnthropicTransformedMessages(
    system: leadingSystem.isEmpty ? null : leadingSystem.join('\n'),
    messages: [
      for (var i = 0; i < roles.length; i++)
        AnthropicTransformedMessage(role: roles[i], content: contents[i]),
    ],
  );
}
