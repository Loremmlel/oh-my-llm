import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/data/vendor_payload_adapters.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

typedef _ResolveCase = ({String host, String label, TypeMatcher matcher});

void main() {
  // ── ThinkingTogglePayloadAdapter ──────────────────────────────────

  group('ThinkingTogglePayloadAdapter', () {
    const adapter = ThinkingTogglePayloadAdapter([
      'api.deepseek.com',
      'ark.cn-beijing.volces.com',
    ]);

    group('matches', () {
      test('配置的主机返回 true（大小写不敏感）', () {
        expect(adapter.matches('api.deepseek.com'), isTrue);
        expect(adapter.matches('API.DEEPSEEK.COM'), isTrue);
        expect(adapter.matches('Ark.CN-Beijing.Volces.COM'), isTrue);
      });

      test('未知主机或空字符串返回 false', () {
        expect(adapter.matches('api.openai.com'), isFalse);
        expect(adapter.matches(''), isFalse);
      });
    });

    group('buildPatch', () {
      test('effort 非 null → thinkingConfig type 为 "enabled"', () {
        final patch = adapter.buildPatch(ReasoningEffort.high);

        expect(patch.thinkingConfig, isNotNull);
        expect(patch.thinkingConfig!['type'], 'enabled');
        expect(patch.extraBody, isNull);
        expect(patch.skipStandardReasoningEffort, isFalse);
      });

      test('effort 为 null → thinkingConfig type 为 "disabled"', () {
        final patch = adapter.buildPatch(null);

        expect(patch.thinkingConfig, isNotNull);
        expect(patch.thinkingConfig!['type'], 'disabled');
        expect(patch.extraBody, isNull);
        expect(patch.skipStandardReasoningEffort, isFalse);
      });
    });
  });

  // ── GoogleOpenAiCompatibleAdapter ─────────────────────────────────

  group('GoogleOpenAiCompatibleAdapter', () {
    const adapter = GoogleOpenAiCompatibleAdapter();

    group('matches', () {
      test('generativelanguage.googleapis.com 返回 true（大小写不敏感）', () {
        expect(
          adapter.matches('generativelanguage.googleapis.com'),
          isTrue,
        );
        expect(
          adapter.matches('GENERATIVELANGUAGE.GOOGLEAPIS.COM'),
          isTrue,
        );
      });

      test('相似但不完全相同的主机返回 false', () {
        expect(adapter.matches('googleapis.com'), isFalse);
        expect(
          adapter.matches('generativelanguage.googleapis.co.jp'),
          isFalse,
        );
        expect(adapter.matches(''), isFalse);
      });
    });

    group('buildPatch', () {
      test('effort 非 null → skipStandardReasoningEffort=true + extraBody 含 google.thinking_config', () {
        final patch = adapter.buildPatch(ReasoningEffort.high);

        expect(patch.skipStandardReasoningEffort, isTrue);
        expect(patch.thinkingConfig, isNull);
        expect(patch.extraBody, isNotNull);
        expect(
          patch.extraBody!['google'],
          {'thinking_config': {'include_thoughts': true}},
        );
      });

      test('effort 为 null → 空 patch', () {
        final patch = adapter.buildPatch(null);

        expect(patch.skipStandardReasoningEffort, isFalse);
        expect(patch.thinkingConfig, isNull);
        expect(patch.extraBody, isNull);
      });
    });
  });

  // ── DefaultPayloadAdapter ─────────────────────────────────────────

  group('DefaultPayloadAdapter', () {
    const adapter = DefaultPayloadAdapter();

    group('matches', () {
      test('对任意主机返回 true（包括空字符串）', () {
        expect(adapter.matches('api.openai.com'), isTrue);
        expect(adapter.matches('unknown.host.local'), isTrue);
        expect(adapter.matches(''), isTrue);
      });
    });

    group('buildPatch', () {
      test('始终返回空 patch，不受 effort 影响', () {
        final withEffort = adapter.buildPatch(ReasoningEffort.low);
        final withoutEffort = adapter.buildPatch(null);

        expect(withEffort.thinkingConfig, isNull);
        expect(withEffort.extraBody, isNull);
        expect(withEffort.skipStandardReasoningEffort, isFalse);

        expect(withoutEffort.thinkingConfig, isNull);
        expect(withoutEffort.extraBody, isNull);
        expect(withoutEffort.skipStandardReasoningEffort, isFalse);
      });
    });
  });

  // ── VendorPayloadAdapterRegistry ──────────────────────────────────

  group('VendorPayloadAdapterRegistry', () {
    group('resolve', () {
      final resolveCases = <_ResolveCase>[
        (host: 'api.deepseek.com', label: 'DeepSeek 主机', matcher: isA<ThinkingTogglePayloadAdapter>()),
        (host: 'ark.cn-beijing.volces.com', label: 'Ark 主机', matcher: isA<ThinkingTogglePayloadAdapter>()),
        (host: 'generativelanguage.googleapis.com', label: 'Gemini 主机', matcher: isA<GoogleOpenAiCompatibleAdapter>()),
        (host: 'api.openai.com', label: '未知主机', matcher: isA<DefaultPayloadAdapter>()),
        (host: '', label: '空字符串', matcher: isA<DefaultPayloadAdapter>()),
      ];
      for (final entry in resolveCases) {
        test('${entry.label} → 正确解析', () {
          expect(
            VendorPayloadAdapterRegistry.standard.resolve(entry.host),
            entry.matcher,
          );
        });
      }

      // ── 自定义注册表 ─────────────────────────────────
    });

    group('自定义注册表', () {
      test('仅含 DefaultPayloadAdapter 的注册表始终返回它', () {
        const registry = VendorPayloadAdapterRegistry([
          DefaultPayloadAdapter(),
        ]);

        expect(
          registry.resolve('api.deepseek.com'),
          isA<DefaultPayloadAdapter>(),
        );
        expect(
          registry.resolve('generativelanguage.googleapis.com'),
          isA<DefaultPayloadAdapter>(),
        );
        expect(
          registry.resolve('any.host'),
          isA<DefaultPayloadAdapter>(),
        );
        expect(
          registry.resolve(''),
          isA<DefaultPayloadAdapter>(),
        );
      });
    });
  });
}
