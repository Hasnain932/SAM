// Works on both JS and WASM Flutter web builds (browser tab and installed PWA).
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

String _mimeFor(String fileName) => fileName.toLowerCase().endsWith('.json')
    ? 'application/json'
    : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

// Web only: saves the bytes as a file download in the browser.
void downloadBytes(List<int> bytes, String fileName) {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [data.toJS].toJS,
    web.BlobPropertyBag(type: _mimeFor(fileName)),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

// Opens the phone's share sheet (WhatsApp, Gmail, Drive...) with the file.
// Returns true if the share sheet was shown (even if the user closed it),
// false if this browser/device cannot share files.
Future<bool> _shareBytes(List<int> bytes, String fileName, String? text) async {
  try {
    final file = web.File(
      [Uint8List.fromList(bytes).toJS].toJS,
      fileName,
      web.FilePropertyBag(type: _mimeFor(fileName)),
    );
    final data = web.ShareData(
      files: [file].toJS,
      title: fileName,
      text: text ?? fileName,
    );
    if (!web.window.navigator.canShare(data)) return false;
    await web.window.navigator.share(data).toDart;
    return true;
  } catch (e) {
    // User closed the share sheet -> nothing more to do.
    if (e.toString().contains('AbortError')) return true;
    return false;
  }
}

// Share sheet first (like the Android app); if the browser cannot share
// files (or the tap permission expired), fall back to a normal download.
Future<void> saveOrShareBytes(List<int> bytes, String fileName,
    {String? text}) async {
  final shared = await _shareBytes(bytes, fileName, text);
  if (!shared) downloadBytes(bytes, fileName);
}

// Returns 'shared' | 'unsupported' | 'expired' ('expired' = the browser needs
// a fresh tap before it allows the share sheet).
Future<String> shareBytesNow(List<int> bytes, String fileName,
    {String? text}) async {
  try {
    final file = web.File(
      [Uint8List.fromList(bytes).toJS].toJS,
      fileName,
      web.FilePropertyBag(type: _mimeFor(fileName)),
    );
    final data = web.ShareData(
      files: [file].toJS,
      title: fileName,
      text: text ?? fileName,
    );
    if (!web.window.navigator.canShare(data)) return 'unsupported';
    await web.window.navigator.share(data).toDart;
    return 'shared';
  } catch (e) {
    final s = e.toString();
    if (s.contains('AbortError')) return 'shared';
    if (s.contains('NotAllowedError')) return 'expired';
    return 'unsupported';
  }
}

// Tells index.html whether the user is busy (marking attendance / reviewing an
// import) so an app update never reloads the page at that moment.
@JS('samSetBusy')
external void _samSetBusy(JSBoolean busy);

void setAppBusy(bool busy) {
  try {
    _samSetBusy(busy.toJS);
  } catch (_) {}
}
