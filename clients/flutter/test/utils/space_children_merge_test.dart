library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/space_children_merge.dart';

void main() {
  group('mergeSpaceChildren', () {
    test('spaceChildren первичны: свои чаты идут первыми по алфавиту', () {
      final result = mergeSpaceChildren(
        spaceChildren: [
          const MergeChild(roomId: '!b:hs', name: 'Bravo', isLocal: true),
          const MergeChild(roomId: '!a:hs', name: 'Alfa', isLocal: true),
        ],
        hierarchy: const [],
      );
      expect(result.map((c) => c.roomId).toList(), ['!a:hs', '!b:hs']);
    });

    test('свои (isLocal) перед чужими, обе группы по алфавиту', () {
      final result = mergeSpaceChildren(
        spaceChildren: [
          const MergeChild(roomId: '!loc:hs', name: 'Zulu', isLocal: true),
        ],
        hierarchy: [
          const MergeChild(roomId: '!rem:hs', name: 'Alpha', isLocal: false),
        ],
      );
      expect(result.map((c) => c.roomId).toList(), ['!loc:hs', '!rem:hs']);
    });

    test('дедуп по room_id: если в обоих — берётся spaceChildren-версия (isLocal)', () {
      final result = mergeSpaceChildren(
        spaceChildren: [
          const MergeChild(roomId: '!x:hs', name: 'FromSync', isLocal: true),
        ],
        hierarchy: [
          const MergeChild(roomId: '!x:hs', name: 'FromHierarchy', isLocal: false),
        ],
      );
      expect(result.length, 1);
      expect(result.single.roomId, '!x:hs');
      expect(result.single.name, 'FromSync');
      expect(result.single.isLocal, true);
    });

    test('hierarchy-only комнаты включаются (чужие публичные)', () {
      final result = mergeSpaceChildren(
        spaceChildren: const [],
        hierarchy: [
          const MergeChild(roomId: '!pub:hs', name: 'Public', isLocal: false),
        ],
      );
      expect(result.map((c) => c.roomId).toList(), ['!pub:hs']);
    });

    test('пустое имя сортируется стабильно (по roomId как запас)', () {
      final result = mergeSpaceChildren(
        spaceChildren: [
          const MergeChild(roomId: '!b:hs', name: null, isLocal: true),
          const MergeChild(roomId: '!a:hs', name: null, isLocal: true),
        ],
        hierarchy: const [],
      );
      expect(result.map((c) => c.roomId).toList(), ['!a:hs', '!b:hs']);
    });
  });
}
