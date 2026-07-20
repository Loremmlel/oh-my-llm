import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/model_list_url.dart';

void main() {
  group('deriveModelsUrl', () {
    test('replaces /chat/completions suffix with /models', () {
      expect(
        deriveModelsUrl('https://api.deepseek.com/v1/chat/completions'),
        'https://api.deepseek.com/v1/models',
      );
      expect(
        deriveModelsUrl('https://api.openai.com/v1/chat/completions'),
        'https://api.openai.com/v1/models',
      );
    });

    test('handles trailing slash after /chat/completions', () {
      expect(
        deriveModelsUrl('https://api.example.com/v1/chat/completions/'),
        'https://api.example.com/v1/models',
      );
    });

    test('appends /models when path does not end with /chat/completions', () {
      expect(
        deriveModelsUrl('https://some.api.com/v1'),
        'https://some.api.com/v1/models',
      );
      expect(
        deriveModelsUrl('https://some.api.com/v1/'),
        'https://some.api.com/v1/models',
      );
    });

    test('appends /models to bare base URL', () {
      expect(
        deriveModelsUrl('https://some.api.com'),
        'https://some.api.com/models',
      );
    });

    test('throws FormatException for invalid URL', () {
      expect(
        () => deriveModelsUrl('not a url'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws ArgumentError for empty string', () {
      expect(
        () => deriveModelsUrl(''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
