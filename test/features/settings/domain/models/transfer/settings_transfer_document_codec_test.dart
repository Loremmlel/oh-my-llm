import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';

Map<String, Object?> _documentObject({
  Object? identifier = SettingsTransferDocument.identifier,
  Object? formatVersion = SettingsTransferDocument.formatVersion,
  Object? sections = const <String, Object?>{},
  bool includeIdentifier = true,
  bool includeFormatVersion = true,
  bool includeSections = true,
}) {
  final object = <String, Object?>{};
  if (includeIdentifier) object['identifier'] = identifier;
  if (includeFormatVersion) object['formatVersion'] = formatVersion;
  if (includeSections) object['sections'] = sections;
  return object;
}

void main() {
  test('非空有序 sections map 经 JSON round-trip 后顺序与内容保持不变', () {
    final document = SettingsTransferDocument(
      sections: <String, Object?>{
        'alphaSection': <String, Object?>{
          'enabled': true,
          'items': <Object?>['一', 2],
        },
        'betaSection': <Object?>[
          null,
          <String, Object?>{'name': '二'},
        ],
      },
    );

    final encoded = SettingsTransferDocumentCodec.encodeJson(document);
    final result = SettingsTransferDocumentCodec.decodeJson(encoded);

    expect(result, isA<SettingsTransferDocumentDecodeSuccess>());
    final decoded = (result as SettingsTransferDocumentDecodeSuccess).document;
    expect(decoded, document);
    expect(decoded.sections.keys.toList(), ['alphaSection', 'betaSection']);
    expect(decoded.toJson(), <String, Object?>{
      'identifier': SettingsTransferDocument.identifier,
      'formatVersion': SettingsTransferDocument.formatVersion,
      'sections': <String, Object?>{
        'alphaSection': <String, Object?>{
          'enabled': true,
          'items': <Object?>['一', 2],
        },
        'betaSection': <Object?>[
          null,
          <String, Object?>{'name': '二'},
        ],
      },
    });
  });

  test('空 sections 是结构合法的 v9 document', () {
    final result = SettingsTransferDocumentCodec.decodeObject(
      _documentObject(),
    );

    expect(result, isA<SettingsTransferDocumentDecodeSuccess>());
    final document = (result as SettingsTransferDocumentDecodeSuccess).document;
    expect(document.sections, isEmpty);
    expect(
      SettingsTransferDocumentCodec.encodeJson(document),
      jsonEncode(_documentObject()),
    );
  });

  test('v8 和 v10 返回带原始版本号的 UnsupportedVersion', () {
    for (final version in [8, 10]) {
      final result = SettingsTransferDocumentCodec.decodeObject(
        _documentObject(formatVersion: version),
      );

      expect(
        result,
        isA<SettingsTransferDocumentUnsupportedVersion>(),
        reason: 'version=$version',
      );
      expect(
        (result as SettingsTransferDocumentUnsupportedVersion).version,
        version,
      );
    }
  });

  test('null、空白和非法 JSON 返回 Malformed', () {
    for (final text in <String?>[null, '', '   ', '{']) {
      expect(
        SettingsTransferDocumentCodec.decodeJson(text),
        isA<SettingsTransferDocumentMalformed>(),
        reason: 'text=$text',
      );
    }
  });

  test('错误标识符、缺失或浮点版本号返回 Malformed', () {
    final cases = <Map<String, Object?>>[
      _documentObject(identifier: 'other-app'),
      _documentObject(includeFormatVersion: false),
      _documentObject(formatVersion: 9.0),
    ];

    for (final object in cases) {
      expect(
        SettingsTransferDocumentCodec.decodeObject(object),
        isA<SettingsTransferDocumentMalformed>(),
      );
    }
  });

  test('缺失或非 map sections 以及未知顶层字段返回 Malformed', () {
    final cases = <Map<String, Object?>>[
      _documentObject(includeSections: false),
      _documentObject(sections: <Object?>[]),
      <String, Object?>{..._documentObject(), 'unexpected': true},
    ];

    for (final object in cases) {
      expect(
        SettingsTransferDocumentCodec.decodeObject(object),
        isA<SettingsTransferDocumentMalformed>(),
      );
    }
  });

  test('非法 section key、非字符串嵌套 map key 和非 JSON-safe 值均被拒绝', () {
    for (final key in ['', 'bad key', 'bad/key', '9section']) {
      final result = SettingsTransferDocumentCodec.decodeObject(
        _documentObject(sections: <String, Object?>{key: <Object?>[]}),
      );
      expect(
        result,
        isA<SettingsTransferDocumentMalformed>(),
        reason: 'key=$key',
      );
    }

    final nestedMapWithNonStringKey = <Object?, Object?>{1: 'value'};
    expect(
      SettingsTransferDocumentCodec.decodeObject(
        _documentObject(
          sections: <String, Object?>{
            'validSection': nestedMapWithNonStringKey,
          },
        ),
      ),
      isA<SettingsTransferDocumentMalformed>(),
    );

    for (final value in <Object?>[
      Object(),
      DateTime(2026, 1, 1),
      <Object?>{'not-json-safe'},
      double.nan,
      double.infinity,
    ]) {
      final result = SettingsTransferDocumentCodec.decodeObject(
        _documentObject(sections: <String, Object?>{'validSection': value}),
      );
      expect(
        result,
        isA<SettingsTransferDocumentMalformed>(),
        reason: 'value=${value.runtimeType}',
      );
    }

    expect(
      () => SettingsTransferDocument(
        sections: <String, Object?>{'validSection': Object()},
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('构造后修改源 map 或 list 不会改变 document', () {
    final sourceList = <Object?>[
      '初始',
      <String, Object?>{'nested': true},
    ];
    final sourceNestedMap = <String, Object?>{'value': '初始'};
    final source = <String, Object?>{
      'firstSection': sourceList,
      'secondSection': sourceNestedMap,
    };
    final document = SettingsTransferDocument(sections: source);

    sourceList.add('后来添加');
    (sourceList[1] as Map<String, Object?>)['nested'] = false;
    sourceNestedMap['value'] = '后来修改';
    source['thirdSection'] = true;

    expect(document.sections.keys.toList(), ['firstSection', 'secondSection']);
    final documentList = document.sections['firstSection']! as List<Object?>;
    expect(documentList, [
      '初始',
      <String, Object?>{'nested': true},
    ]);
    expect(document.sections['secondSection'], <String, Object?>{
      'value': '初始',
    });
  });

  test('toJson 返回调用方不能修改的防御性结构', () {
    final document = SettingsTransferDocument(
      sections: <String, Object?>{
        'section': <String, Object?>{
          'items': <Object?>['初始'],
        },
      },
    );
    final json = document.toJson();
    final sections = json['sections']! as Map<String, Object?>;
    final section = sections['section']! as Map<String, Object?>;
    final items = section['items']! as List<Object?>;

    expect(() => json['unexpected'] = true, throwsUnsupportedError);
    expect(
      () => sections['anotherSection'] = <Object?>[],
      throwsUnsupportedError,
    );
    expect(() => section['anotherValue'] = false, throwsUnsupportedError);
    expect(() => items.add('后来添加'), throwsUnsupportedError);
    expect(document.sections.keys, ['section']);
  });
}
