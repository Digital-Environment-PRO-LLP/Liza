import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(String clientName) async {
  try {
    html.window.navigator.storage?.persist();
    return await MatrixSdkDatabase.init(clientName);
  } on PlatformException catch (e, s) {
    Logs().wtf(
      'Unable to construct database (temporary platform error)!',
      e,
      s,
    );
    rethrow;
  } catch (e, s) {
    Logs().wtf('Unable to construct database!', e, s);
    rethrow;
  }
}
