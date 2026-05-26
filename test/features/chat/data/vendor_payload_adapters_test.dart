import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/data/vendor_payload_adapters.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  // ── ThinkingTogglePayloadAdapter ──────────────────────────────────

  group('ThinkingTogglePayloadAdapter', () {
    const adapter = ThinkingTogglePayloadAdapter([
      'api.deepseek.com',
      'ark.cn-beijing.volces.com',
    ]);

    group('matches', () {
      test('返回 true — 配置的主机', () {
        expect(adapter.matches('api.deepseek.com'), isTrue);
        expect(adapter.matches('ark.cn-beijing.volces.com'), isTrue);
      });

      test('返回 true — 主机名大小写不敏感', () {
        expect(adapter.matches('API.DEEPSEEK.COM'), isTrue);
        expect(adapter.matches('Ark.CN-Beijing.Volces.COM'), isTrue);
      });

      test('返回 false — 未知主机', () {
        expect(adapter.matches('api.openai.com'), isFalse);
      });

      test('返回 false — 空字符串', () {
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
      test('返回 true — generativelanguage.googleapis.com', () {
        expect(
          adapter.matches('generativelanguage.googleapis.com'),
          isTrue,
        );
      });

      test('大小写不敏感', () {
        expect(
          adapter.matches('GENERATIVELANGUAGE.GOOGLEAPIS.COM'),
          isTrue,
        );
      });

      test('返回 false — 相似但不完全相同的主机', () {
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
      test('DeepSeek 主机 → ThinkingTogglePayloadAdapter', () {
        final result = VendorPayloadAdapterRegistry.standard
            .resolve('api.deepseek.com');

        expect(result, isA<ThinkingTogglePayloadAdapter>());
      });

      test('Ark 主机 → ThinkingTogglePayloadAdapter', () {
        final result = VendorPayloadAdapterRegistry.standard
            .resolve('ark.cn-beijing.volces.com');

        expect(result, isA<ThinkingTogglePayloadAdapter>());
      });

      test('Gemini 主机 → GoogleOpenAiCompatibleAdapter', () {
        final result = VendorPayloadAdapterRegistry.standard
            .resolve('generativelanguage.googleapis.com');

        expect(result, isA<GoogleOpenAiCompatibleAdapter>());
      });

      test('未知主机 → DefaultPayloadAdapter', () {
        final result = VendorPayloadAdapterRegistry.standard
            .resolve('api.openai.com');

        expect(result, isA<DefaultPayloadAdapter>());
      });

      test('空字符串 → DefaultPayloadAdapter（兜底）', () {
        final result =
            VendorPayloadAdapterRegistry.standard.resolve('');

        expect(result, isA<DefaultPayloadAdapter>());
      });
    });

    group('standard 静态实例', () {
      test('包含预期的适配器，顺序正确', () {
        const registry = VendorPayloadAdapterRegistry.standard;

        // DeepSeek 解析为 ThinkingTogglePayloadAdapter
        expect(
          registry.resolve('api.deepseek.com'),
          isA<ThinkingTogglePayloadAdapter>(),
        );

        // Ark 解析为 ThinkingTogglePayloadAdapter
        expect(
          registry.resolve('ark.cn-beijing.volces.com'),
          isA<ThinkingTogglePayloadAdapter>(),
        );

        // Gemini 解析为 GoogleOpenAiCompatibleAdapter
        expect(
          registry.resolve('generativelanguage.googleapis.com'),
          isA<GoogleOpenAiCompatibleAdapter>(),
        );

        // 其他主机兜底为 DefaultPayloadAdapter
        expect(
          registry.resolve('any.other.host'),
          isA<DefaultPayloadAdapter>(),
        );
      });
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
