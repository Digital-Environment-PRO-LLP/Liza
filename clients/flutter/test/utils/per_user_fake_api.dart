// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix.dart';

/// FakeMatrixApi «с памятью на пользователя»: сервер Matrix отдаёт по
/// `GET /pushers` только pushers ЭТОГО пользователя, а `POST /pushers/set`
/// апсертит по (app_id, pushkey) и — при `append:false` — эмулирует серверный
/// снос pushers ДРУГИХ пользователей с тем же app_id+pushkey на том же
/// хоумсервере (`remove_pushers_by_app_id_and_pushkey_not_user`). Штатный
/// FakeMatrixApi отдаёт статический список и не различает пользователей — для
/// мультиаккаунт-стражей этого мало.
class PerUserFakeMatrixApi extends FakeMatrixApi {
  PerUserFakeMatrixApi({required this.userId, required this.homeserverHost});

  final String userId;
  final String homeserverHost;

  /// Живые pushers этого пользователя (как их вернёт GET /pushers).
  final List<Map<String, dynamic>> pushers = [];

  /// Все POST /pushers/set с kind != null (регистрации) — с флагом append.
  final List<Map<String, dynamic>> posted = [];

  /// Все POST /pushers/set с kind == null (удаления).
  final List<Map<String, dynamic>> deleted = [];

  /// «Соседи» по хоумсерверу — чтобы `append:false` мог снести их pushers.
  final List<PerUserFakeMatrixApi> peers = [];

  @override
  Future<Response> mockIntercept(Request request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/client/v3/login')) {
      return Response(
        jsonEncode({
          'user_id': userId,
          'access_token': 'tok-$userId',
          'device_id': 'DEV${userId.hashCode.abs() % 100000}',
          'home_server': homeserverHost,
        }),
        200,
      );
    }
    if (path.endsWith('/client/v3/pushers') && request.method == 'GET') {
      return Response(jsonEncode({'pushers': pushers}), 200);
    }
    if (path.endsWith('/client/v3/pushers/set') && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final appId = body['app_id'];
      final pushkey = body['pushkey'];
      if (body['kind'] == null) {
        deleted.add(body);
        pushers.removeWhere(
          (p) => p['app_id'] == appId && p['pushkey'] == pushkey,
        );
        return Response('{}', 200);
      }
      posted.add(body);
      final append = body['append'] == true;
      if (!append) {
        for (final peer in peers) {
          if (peer.homeserverHost != homeserverHost) continue;
          peer.pushers.removeWhere(
            (p) => p['app_id'] == appId && p['pushkey'] == pushkey,
          );
        }
      }
      pushers.removeWhere(
        (p) => p['app_id'] == appId && p['pushkey'] == pushkey,
      );
      pushers.add({
        'app_id': appId,
        'pushkey': pushkey,
        'kind': body['kind'],
        'app_display_name': body['app_display_name'],
        'device_display_name': body['device_display_name'],
        'lang': body['lang'],
        'data': body['data'],
      });
      return Response('{}', 200);
    }
    return super.mockIntercept(request);
  }
}
