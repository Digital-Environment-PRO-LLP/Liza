/// Лёгкая запись о вложенном чате компании, не зависящая от Matrix-типов.
/// Используется для слияния sync-данных (spaceChildren) и hierarchy.
class MergeChild {
  final String roomId;
  final String? name;

  /// true — юзер состоит (метаданные из локального Room, sync); false — чужая
  /// комната, метаданные из hierarchy.
  final bool isLocal;

  const MergeChild({
    required this.roomId,
    required this.name,
    required this.isLocal,
  });
}

/// Сливает вложенные чаты компании из двух источников.
///
/// [spaceChildren] первичны (из sync, обновляются в реальном времени).
/// [hierarchy] добавляет чужие/неприсоединённые комнаты, которых нет в
/// spaceChildren. Дедуп по roomId: при совпадении берётся запись из
/// spaceChildren. Порядок: свои (isLocal) перед чужими, внутри групп — по
/// имени (case-insensitive), пустое имя — по roomId.
List<MergeChild> mergeSpaceChildren({
  required List<MergeChild> spaceChildren,
  required List<MergeChild> hierarchy,
}) {
  final byId = <String, MergeChild>{};
  // hierarchy кладём первыми, затем spaceChildren перетирают по roomId.
  for (final c in hierarchy) {
    byId[c.roomId] = c;
  }
  for (final c in spaceChildren) {
    byId[c.roomId] = c;
  }

  int sortKey(MergeChild a, MergeChild b) {
    if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
    final an = (a.name ?? '').toLowerCase();
    final bn = (b.name ?? '').toLowerCase();
    if (an.isEmpty && bn.isEmpty) return a.roomId.compareTo(b.roomId);
    final byName = an.compareTo(bn);
    return byName != 0 ? byName : a.roomId.compareTo(b.roomId);
  }

  return byId.values.toList()..sort(sortKey);
}
