import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// On-device RAG index using BM25 lexical retrieval — pure Dart, no embedding
/// model or native lib. ponytail: for a small (<100 page) corpus BM25 over an
/// in-memory list is plenty; add semantic embeddings only if recall falls short.
class Rag {
  final List<String> _chunks = [];
  final List<List<String>> _tokens = []; // parallel to _chunks
  final Map<String, int> _df = {}; // document frequency per term
  double _avgdl = 0;

  int get count => _chunks.length;

  Future<File> get _storeFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/rag_store.json');
  }

  Future<void> load() async {
    final f = await _storeFile;
    if (!await f.exists()) return;
    final data = (jsonDecode(await f.readAsString()) as List).cast<String>();
    _chunks
      ..clear()
      ..addAll(data);
    _reindex();
  }

  Future<void> _save() async {
    final f = await _storeFile;
    await f.writeAsString(jsonEncode(_chunks));
  }

  /// Replace the corpus in memory and reindex (no disk I/O). For tests and
  /// programmatic loading.
  void indexChunks(List<String> chunks) {
    _chunks
      ..clear()
      ..addAll(chunks);
    _reindex();
  }

  /// Ingest a .txt/.md/.pdf file: extract text, chunk, persist, reindex.
  Future<void> ingest(File file,
      {void Function(int done, int total)? onProgress}) async {
    final pieces = chunkText(await _extractText(file));
    for (var i = 0; i < pieces.length; i++) {
      _chunks.add(pieces[i]);
      onProgress?.call(i + 1, pieces.length);
    }
    _reindex();
    await _save();
  }

  void _reindex() {
    _tokens
      ..clear()
      ..addAll(_chunks.map(tokenize));
    _df.clear();
    for (final toks in _tokens) {
      for (final t in toks.toSet()) {
        _df[t] = (_df[t] ?? 0) + 1;
      }
    }
    _avgdl = _tokens.isEmpty
        ? 0
        : _tokens.map((t) => t.length).reduce((a, b) => a + b) / _tokens.length;
  }

  /// Top-[k] chunks by BM25 score for [query] (only positive scores).
  List<String> retrieve(String query, {int k = 4}) {
    if (_chunks.isEmpty) return [];
    final q = tokenize(query);
    final scored = List.generate(_chunks.length, (i) => (i, _bm25(q, i)))
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return scored
        .where((e) => e.$2 > 0)
        .take(k)
        .map((e) => _chunks[e.$1])
        .toList();
  }

  double _bm25(List<String> queryTokens, int docIndex,
      {double k1 = 1.5, double b = 0.75}) {
    final doc = _tokens[docIndex];
    final n = _chunks.length;
    final tf = <String, int>{};
    for (final t in doc) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    var score = 0.0;
    for (final t in queryTokens.toSet()) {
      final f = tf[t] ?? 0;
      if (f == 0) continue;
      final df = _df[t] ?? 0;
      final idf = log(1 + (n - df + 0.5) / (df + 0.5));
      final denom = f + k1 * (1 - b + b * doc.length / (_avgdl == 0 ? 1 : _avgdl));
      score += idf * (f * (k1 + 1)) / denom;
    }
    return score;
  }

  static Future<String> _extractText(File file) async {
    if (file.path.toLowerCase().endsWith('.pdf')) {
      final doc = PdfDocument(inputBytes: await file.readAsBytes());
      final text = PdfTextExtractor(doc).extractText();
      doc.dispose();
      return text;
    }
    return file.readAsString();
  }
}

/// Split into lowercased word tokens. `unicode: true` + \p{L} keeps Mongolian
/// Cyrillic (incluttering өү) and Latin alike.
List<String> tokenize(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((t) => t.isNotEmpty)
    .toList();

/// Fixed-size character chunks with overlap.
/// ponytail: char-based, not token-aware; make token-aware if retrieval degrades.
List<String> chunkText(String text, {int size = 800, int overlap = 100}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return [];
  final out = <String>[];
  for (var i = 0; i < clean.length; i += size - overlap) {
    out.add(clean.substring(i, min(i + size, clean.length)));
    if (i + size >= clean.length) break;
  }
  return out;
}
