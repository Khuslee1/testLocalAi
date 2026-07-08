// Runs on the real device engine (native works here, unlike `flutter test`):
//   flutter test integration_test/chat_test.dart -d windows
// Verifies fllama loads Qwen3 and generates a non-empty answer.
import 'dart:async';

import 'package:fllama/fllama.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:test_local_ai/llm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Qwen3 chat model generates a response', (tester) async {
    final done = Completer<String>();
    var last = '';
    await chatStream(
      messages: [Message(Role.user, 'Reply with exactly one word: hello')],
      onToken: (partial) => last = partial,
      onDone: () {
        if (!done.isCompleted) done.complete(last);
      },
    );
    final answer = await done.future.timeout(const Duration(minutes: 5));
    // ignore: avoid_print
    print('CHAT RESPONSE: "$answer"');
    expect(answer.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
