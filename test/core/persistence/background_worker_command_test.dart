import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/background_worker_command.dart';

void main() {
  group('WorkerCommand', () {
    test('WriteCommand carries id and payload', () {
      final cmd = WriteCommand(id: 42, payload: [1, 'hello', true]);
      expect(cmd.id, equals(42));
      expect(cmd.payload, equals([1, 'hello', true]));
    });

    test('CloseCommand is instantiable', () {
      expect(CloseCommand(), isA<WorkerCommand>());
    });
  });

  group('WorkerResponse', () {
    test('AckResponse carries commandId', () {
      final ack = AckResponse(commandId: 7);
      expect(ack.commandId, equals(7));
    });

    test('ErrorResponse carries commandId and message', () {
      final err = ErrorResponse(commandId: 3, message: 'write failed');
      expect(err.commandId, equals(3));
      expect(err.message, equals('write failed'));
    });

    test('ExitResponse is instantiable', () {
      expect(ExitResponse(), isA<WorkerResponse>());
    });
  });
}
