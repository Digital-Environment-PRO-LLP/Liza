/// Чистая логика позиционной семантики "просмотрено" для сторисов.
/// Позиция = мой m.read receipt в отсортированном списке активных сегментов;
/// локальные отметки (StoriesSeenStore) дополняют её для мгновенного UI.
library;

int indexOfEvent(List<String> segmentIds, String? eventId) =>
    eventId == null ? -1 : segmentIds.indexOf(eventId);

bool segmentSeen({
  required int index,
  required int receiptIndex,
  required String segmentId,
  required bool Function(String) isLocallySeen,
}) =>
    index <= receiptIndex || isLocallySeen(segmentId);

int firstUnseenIndex({
  required List<String> segmentIds,
  required int receiptIndex,
  required bool Function(String) isLocallySeen,
}) {
  for (var i = 0; i < segmentIds.length; i++) {
    final seen = segmentSeen(
      index: i,
      receiptIndex: receiptIndex,
      segmentId: segmentIds[i],
      isLocallySeen: isLocallySeen,
    );
    if (!seen) return i;
  }
  return 0;
}

bool hasUnseenPositional({
  required List<String> segmentIds,
  required int receiptIndex,
  required bool Function(String) isLocallySeen,
}) {
  for (var i = 0; i < segmentIds.length; i++) {
    final seen = segmentSeen(
      index: i,
      receiptIndex: receiptIndex,
      segmentId: segmentIds[i],
      isLocallySeen: isLocallySeen,
    );
    if (!seen) return true;
  }
  return false;
}

int viewsCount({
  required int segmentIndex,
  required Iterable<int> viewerReceiptIndexes,
}) =>
    viewerReceiptIndexes.where((i) => i >= segmentIndex).length;
