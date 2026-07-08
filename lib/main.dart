import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fllama/fllama.dart';
import 'package:flutter/material.dart';

import 'llm.dart';
import 'rag.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Local RAG Chat',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const ChatPage(),
      );
}

class Msg {
  final bool fromUser;
  String text;
  Msg(this.fromUser, this.text);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _messages = <Msg>[];
  Rag? _rag;
  String _status = 'Загварыг ачаалж байна…';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final rag = Rag();
      await rag.load();
      setState(() {
        _rag = rag;
        _busy = false;
        _status = '${rag.count} chunk ачаалсан. Файл нэмээд асуугаарай.';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Ачаалж чадсангүй: $e';
      });
    }
  }

  Future<void> _addFile() async {
    const group = XTypeGroup(label: 'docs', extensions: ['pdf', 'txt', 'md']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || _rag == null) return;
    setState(() => _busy = true);
    try {
      await _rag!.ingest(
        File(file.path),
        onProgress: (d, t) => setState(() => _status = 'Индекслэж байна $d/$t…'),
      );
      setState(() => _status = '${_rag!.count} chunk бэлэн.');
    } catch (e) {
      setState(() => _status = 'Файл уншиж чадсангүй: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _rag == null || _busy) return;
    _input.clear();
    final answer = Msg(false, '');
    setState(() {
      _messages.add(Msg(true, q));
      _messages.add(answer);
      _busy = true;
      _status = 'Хайж байна…';
    });

    final hits = _rag!.retrieve(q);
    final context = hits.join('\n---\n');
    setState(() => _status = 'Хариулж байна…');

    await chatStream(
      messages: [
        Message(Role.system,
            'Чи туслах бот. ЗӨВХӨН доорх мэдээлэлд тулгуурлан монголоор хариул. '
            'Мэдээлэлд байхгүй бол "Мэдээлэлд алга" гэж хэл. /no_think'),
        Message(Role.user, 'Мэдээлэл:\n$context\n\nАсуулт: $q'),
      ],
      onToken: (partial) => setState(() => answer.text = partial),
      onDone: () => setState(() {
        _busy = false;
        _status = '${_rag!.count} chunk.';
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local RAG Chat'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _addFile,
            icon: const Icon(Icons.attach_file),
            tooltip: 'Файл нэмэх',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_status, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return Align(
                  alignment:
                      m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m.fromUser
                          ? Colors.indigo.shade100
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(m.text.isEmpty ? '…' : m.text),
                  ),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Асуултаа бичнэ үү…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
