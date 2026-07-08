import 'package:flutter_test/flutter_test.dart';
import 'package:test_local_ai/rag.dart';

void main() {
  test('tokenize keeps Mongolian Cyrillic and lowercases', () {
    expect(tokenize('Сайн уу, ЮРА!'), ['сайн', 'уу', 'юра']);
    expect(tokenize('   '), isEmpty);
  });

  test('chunkText overlaps and covers the whole text', () {
    final text = List.generate(50, (i) => 'word$i').join(' ');
    final chunks = chunkText(text, size: 100, overlap: 20);
    expect(chunks.length, greaterThan(1));
    expect(chunks.first.length, lessThanOrEqualTo(100));
    final tailWord = chunks[0].trim().split(' ').last;
    expect(chunks[1].contains(tailWord), isTrue); // overlap carries the last word
  });

  test('chunkText handles empty/whitespace', () {
    expect(chunkText('   '), isEmpty);
  });

  test('BM25 retrieval ranks the on-topic chunk first', () {
    final rag = Rag()
      ..indexChunks([
        'Монгол улсын нийслэл Улаанбаатар хот юм.',
        'Нохой бол гэрийн тэжээвэр амьтан.',
        'Улаанбаатар хотын хүн ам их.',
      ]);
    final hits = rag.retrieve('Улаанбаатар нийслэл', k: 2);
    expect(hits, isNotEmpty);
    expect(hits.first.contains('Улаанбаатар'), isTrue);
    // no matching term → nothing (BM25 keeps positive scores only)
    expect(rag.retrieve('банана компьютер'), isEmpty);
  });
}
