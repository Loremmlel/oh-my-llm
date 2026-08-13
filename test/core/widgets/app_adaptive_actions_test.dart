import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/app_adaptive_actions.dart';

void main() {
  test('719 走紧凑分支，720 等号和 721 走宽侧', () {
    const actions = AppAdaptiveActions(
      compactActions: [Text('紧凑动作')],
      wideActions: [Text('宽侧动作')],
    );
    expect(actions.resolve(719).single, isA<Text>());
    expect((actions.resolve(719).single as Text).data, '紧凑动作');
    expect((actions.resolve(720).single as Text).data, '宽侧动作');
    expect((actions.resolve(721).single as Text).data, '宽侧动作');
  });
}
