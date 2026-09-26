import 'dart:js_interop';

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

/// Освобождает `blob:` URL записи: вкладка живёт сутками, и без этого каждое
/// голосовое держало бы свои байты в памяти до перезагрузки.
void revokeObjectUrl(String url) {
  if (url.startsWith('blob:')) _revokeObjectURL(url);
}
