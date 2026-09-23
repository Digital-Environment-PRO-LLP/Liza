import 'package:matrix/matrix.dart';

const channelStoriesOfKey = 'com.liza.channel.stories_of';

/// channel_id из маркера stories-комнаты канала, или null (личная история).
String? channelIdOf(Map<String, dynamic> creationContent) {
  final marker = creationContent[channelStoriesOfKey];
  if (marker is Map) {
    final id = marker['channel_id'];
    return id is String ? id : null;
  }
  return null;
}

extension ChannelStoriesRoom on Room {
  /// channel_id, если эта сторис-комната принадлежит каналу (не пользователю).
  String? get channelIdOfStoriesRoom {
    final content = getState(EventTypes.RoomCreate)?.content;
    return content == null ? null : channelIdOf(content);
  }
}
