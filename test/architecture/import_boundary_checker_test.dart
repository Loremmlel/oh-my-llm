import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/architecture/import_boundary_checker.dart';

ImportBoundaryChecker _checker([ArchitecturePolicy? policy]) =>
    ImportBoundaryChecker(policy: policy ?? const ArchitecturePolicy());

ArchitecturePolicy get _settingsAllowance => ArchitecturePolicy(
  legacyApplicationDataEdges: {
    ImportEdge(
      sourcePath:
          'lib/features/settings/application/preferences/chat_defaults_controller.dart',
      targetPath: 'lib/features/settings/data/chat_defaults_repository.dart',
    ): '存量债务',
  },
);

void main() {
  group('合法输入', () {
    test('同 feature 分层引用零违规', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart':
            "import '../application/sessions/chat_sessions_controller.dart';\n"
            "import '../../domain/models/chat_conversation.dart';",
        'lib/features/chat/application/sessions/chat_sessions_controller.dart':
            "import '../../domain/models/chat_conversation.dart';",
        'lib/features/chat/data/persistence/sqlite_chat_conversation_repository.dart':
            "import '../../application/ports/chat_conversation_repository.dart';",
      });
      expect(violations, isEmpty);
    });

    test('app composition 组合 port 与 data concrete 零违规', () {
      final violations = _checker().checkSources({
        'lib/app/composition/cross_feature_bindings.dart': """
          import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
          import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart';
        """,
      });
      expect(violations, isEmpty);
    });

    test('domain 只依赖 dart 与纯值库零违规', () {
      final violations = _checker().checkSources({
        'lib/features/chat/domain/models/chat_message.dart':
            "import 'package:equatable/equatable.dart';\nimport 'dart:async';",
      });
      expect(violations, isEmpty);
    });

    test('精确 allowlist 边放行', () {
      final violations = ImportBoundaryChecker(policy: _settingsAllowance)
          .checkSources({
            'lib/features/settings/application/preferences/chat_defaults_controller.dart':
                "import '../../data/chat_defaults_repository.dart';",
          });
      expect(violations, isEmpty);
    });
  });

  group('非法输入', () {
    test('presentation 直达 data（package URI）', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart':
            "import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';",
      });
      expect(violations.single.ruleId, 'PRESENTATION_TO_DATA');
    });

    test('presentation 直达 data（相对 URI 解析一致）', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/screens/chat_screen.dart':
            "import '../../data/persistence/sqlite_chat_conversation_repository.dart';",
      });
      final v = violations.single;
      expect(v.ruleId, 'PRESENTATION_TO_DATA');
      expect(
        v.resolvedTarget,
        'lib/features/chat/data/persistence/sqlite_chat_conversation_repository.dart',
      );
    });

    test('presentation 直达 core persistence', () {
      final violations = _checker().checkSources({
        'lib/features/history/presentation/history_screen.dart':
            "import 'package:oh_my_llm/core/persistence/app_database.dart';",
      });
      expect(violations.single.ruleId, 'PRESENTATION_TO_CORE_PERSISTENCE');
    });

    test('core 依赖 feature', () {
      final violations = _checker().checkSources({
        'lib/core/widgets/example_widget.dart':
            "import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';",
      });
      expect(violations.single.ruleId, 'CORE_TO_FEATURE');
    });

    test('domain 依赖框架包', () {
      for (final pkg in [
        'flutter',
        'flutter_riverpod',
        'riverpod',
        'riverpod_annotation',
        'sqlite3',
      ]) {
        final violations = _checker().checkSources({
          'lib/features/chat/domain/models/chat_message.dart':
              "import 'package:$pkg/whatever.dart';",
        });
        expect(
          violations.single.ruleId,
          'DOMAIN_FRAMEWORK_DEPENDENCY',
          reason: 'package:$pkg 应被禁止',
        );
      }
    });

    test('application 直达 data（非 allowlist）', () {
      final violations = _checker().checkSources({
        'lib/features/chat/application/sessions/chat_sessions_controller.dart':
            "import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';",
      });
      expect(violations.single.ruleId, 'APPLICATION_TO_DATA');
    });

    test('allowlist 不放行同一 source 的其他 target', () {
      final violations = ImportBoundaryChecker(policy: _settingsAllowance)
          .checkSources({
            'lib/features/settings/application/preferences/chat_defaults_controller.dart':
                "import '../../data/other_repository.dart';",
          });
      expect(violations.single.ruleId, 'APPLICATION_TO_DATA');
    });

    test('export 不能绕过边界', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart':
            "export 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart' show ChatConversation;",
      });
      expect(violations.single.ruleId, 'PRESENTATION_TO_DATA');
    });
  });

  group('allowlist 生命周期', () {
    test('stale allowlist 条目报 STALE_ALLOWANCE', () {
      final violations = ImportBoundaryChecker(
        policy: _settingsAllowance,
      ).checkSources({}, verifyAllowlistUsage: true);
      expect(violations.single.ruleId, 'STALE_ALLOWANCE');
    });
  });

  group('扫描细节', () {
    test('注释中的伪 import 忽略；conditional 每个分支都检查', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart': """
          // import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
          import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart'
              if (dart.library.io) 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_client.dart';
        """,
      });
      expect(violations, hasLength(2));
      expect(
        violations.every((v) => v.ruleId == 'PRESENTATION_TO_DATA'),
        isTrue,
      );
    });

    test('输出排序与输入顺序无关', () {
      final sourcesA = {
        'lib/features/b/presentation/b_screen.dart':
            "import 'package:oh_my_llm/features/b/data/b_repository.dart';",
        'lib/features/a/presentation/a_screen.dart':
            "import '../data/a_repository.dart';",
      };
      final sourcesB = Map<String, String>.of(sourcesA);
      final keys = sourcesB.keys.toList().reversed.toList();
      final sourcesBReordered = <String, String>{
        for (final key in keys) key: sourcesB[key]!,
      };
      final violationsA = _checker().checkSources(sourcesA);
      final violationsB = _checker().checkSources(sourcesBReordered);
      (String, int, String, String?) keyOf(ArchitectureViolation v) =>
          (v.sourcePath, v.line, v.ruleId, v.resolvedTarget);
      expect(violationsA.map(keyOf).toList(), violationsB.map(keyOf).toList());
      final sources = violationsA.map((v) => v.sourcePath).toList();
      expect(sources, List<String>.of(sources)..sort());
    });

    test('当前仓库零违规且 7 条例外均被消费', () {
      final checker = ImportBoundaryChecker(policy: architecturePolicy);
      final violations = checker.checkDirectory(
        Directory('lib'),
        verifyAllowlistUsage: true,
      );
      expect(violations, isEmpty);
    });
  });
}
