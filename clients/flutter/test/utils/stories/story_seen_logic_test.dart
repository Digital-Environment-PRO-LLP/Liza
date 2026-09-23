import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_seen_logic.dart';

void main() {
  final ids = [r'$a', r'$b', r'$c'];
  bool none(String _) => false;

  test('indexOfEvent: найден / не найден / null', () {
    expect(indexOfEvent(ids, r'$b'), 1);
    expect(indexOfEvent(ids, r'$zzz'), -1);
    expect(indexOfEvent(ids, null), -1);
  });

  test('segmentSeen: покрыт receipt-позицией', () {
    expect(
      segmentSeen(index: 1, receiptIndex: 1, segmentId: r'$b', isLocallySeen: none),
      isTrue,
    );
    expect(
      segmentSeen(index: 2, receiptIndex: 1, segmentId: r'$c', isLocallySeen: none),
      isFalse,
    );
  });

  test('segmentSeen: локальная отметка перекрывает', () {
    expect(
      segmentSeen(
        index: 2,
        receiptIndex: -1,
        segmentId: r'$c',
        isLocallySeen: (id) => id == r'$c',
      ),
      isTrue,
    );
  });

  test('firstUnseenIndex: старт с первого непокрытого [ledger:RL-stories-first-unseen]', () {
    expect(
      firstUnseenIndex(segmentIds: ids, receiptIndex: 0, isLocallySeen: none),
      1,
    );
  });

  test('firstUnseenIndex: всё просмотрено - 0 [ledger:RL-stories-first-unseen]', () {
    expect(
      firstUnseenIndex(segmentIds: ids, receiptIndex: 2, isLocallySeen: none),
      0,
    );
  });

  test('firstUnseenIndex: ничего не просмотрено - 0', () {
    expect(
      firstUnseenIndex(segmentIds: ids, receiptIndex: -1, isLocallySeen: none),
      0,
    );
  });

  test('hasUnseenPositional', () {
    expect(
      hasUnseenPositional(segmentIds: ids, receiptIndex: 1, isLocallySeen: none),
      isTrue,
    );
    expect(
      hasUnseenPositional(segmentIds: ids, receiptIndex: 2, isLocallySeen: none),
      isFalse,
    );
    // receipt отстаёт, но хвост докрыт локальными отметками
    expect(
      hasUnseenPositional(
        segmentIds: ids,
        receiptIndex: 0,
        isLocallySeen: (id) => id == r'$b' || id == r'$c',
      ),
      isFalse,
    );
  });

  test('пустой список сегментов: firstUnseenIndex 0, hasUnseenPositional false [ledger:RL-stories-first-unseen]', () {
    expect(
      firstUnseenIndex(segmentIds: const [], receiptIndex: 0, isLocallySeen: none),
      0,
    );
    expect(
      hasUnseenPositional(segmentIds: const [], receiptIndex: 0, isLocallySeen: none),
      isFalse,
    );
  });

  test('hasUnseenPositional: receiptIndex за пределами длины списка - всё просмотрено', () {
    expect(
      hasUnseenPositional(segmentIds: ids, receiptIndex: 100, isLocallySeen: none),
      isFalse,
    );
  });

  test('viewsCount: зрители с receipt на сегменте или позже [ledger:RL-stories-view-count]', () {
    expect(viewsCount(segmentIndex: 1, viewerReceiptIndexes: [0, 1, 2, 2]), 3);
    expect(viewsCount(segmentIndex: 0, viewerReceiptIndexes: []), 0);
  });
}
