import 'dart:io';

import 'package:fllama/fllama.dart';
import 'package:path_provider/path_provider.dart';

const chatModelFile = 'Qwen3-1.7B-Q4_K_M.gguf';

/// Where the GGUF chat model lives on device.
/// Android: external files dir (`adb push`-friendly).
/// Windows (desktop dev): the project's `models/` folder next to the cwd.
/// Else: app documents dir.
Future<String> modelsDir() async {
  if (Platform.isAndroid) return (await getExternalStorageDirectory())!.path;
  if (Platform.isWindows) {
    return '${Directory.current.path}/models'; // ponytail: dev path; use app dir at ship time
  }
  return (await getApplicationDocumentsDirectory()).path;
}

/// Stream a chat completion from the Qwen3 chat model (fllama).
/// [messages] is the full conversation (system + turns).
/// [onToken] receives the growing (cumulative) response text.
Future<void> chatStream({
  required List<Message> messages,
  required void Function(String partial) onToken,
  required void Function() onDone,
}) async {
  final request = OpenAiRequest(
    modelPath: '${await modelsDir()}/$chatModelFile',
    messages: messages,
    maxTokens: 256, // ponytail: shorter answers = faster on-device; bump if truncated
    temperature: 0.7,
    topP: 0.95,
    numGpuLayers: 0, // ponytail: CPU-only default
    contextSize: 4096,
    logger: (m) => print('[fllama] $m'), // ignore: avoid_print
  );
  await fllamaChat(request, (response, _, done) {
    onToken(response);
    if (done) onDone();
  });
}
