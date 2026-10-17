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

// True on Android browsers. Chrome on Android refuses to share .xlsx / .json
// files through the share sheet, so there we simply download the file.
// iPhone / iPad (Safari) can share them, so they keep the share sheet.
bool isAndroidBrowser() {
  try {
    return web.window.navigator.userAgent.toLowerCase().contains('android');
  } catch (_) {
    return false;
  }
}

// Last share error text (shown to the user so we can see why sharing failed).
String lastShareError = '';

// Builds the share payload. Tries file + title + text first, then file only
// (some browsers refuse the combination). Returns null if files cannot be shared.
web.ShareData? _buildShareData(
    List<int> bytes, String fileName, String? text) {
  final file = web.File(
    [Uint8List.fromList(bytes).toJS].toJS,
    fileName,
    web.FilePropertyBag(type: _mimeFor(fileName)),
  );
  final nav = web.window.navigator;
  final withText = web.ShareData(
    files: [file].toJS,
    title: fileName,
    text: text ?? fileName,
  );
  if (nav.canShare(withText)) return withText;
  final filesOnly = web.ShareData(files: [file].toJS);
  if (nav.canShare(filesOnly)) return filesOnly;
  return null;
}

// Returns 'shared' | 'unsupported' | 'expired' ('expired' = the browser needs
// a fresh tap before it allows the share sheet).
// IMPORTANT: call this directly inside the tap handler, before any await.
Future<String> shareBytesNow(List<int> bytes, String fileName,
    {String? text}) async {
  lastShareError = '';
  try {
    final data = _buildShareData(bytes, fileName, text);
    if (data == null) {
      lastShareError = 'This browser cannot share this file type';
      return 'unsupported';
    }
    await web.window.navigator.share(data).toDart;
    return 'shared';
  } catch (e) {
    final msg = e.toString();
    lastShareError = msg;
    if (msg.contains('AbortError')) return 'shared'; // user closed the sheet
    if (msg.contains('NotAllowedError')) return 'expired';
    return 'unsupported';
  }
}

// Share sheet first; if the browser cannot share files (or the tap permission
// expired), fall back to a normal download.
Future<void> saveOrShareBytes(List<int> bytes, String fileName,
    {String? text}) async {
  if (isAndroidBrowser()) {
    downloadBytes(bytes, fileName);
    return;
  }
  final r = await shareBytesNow(bytes, fileName, text: text);
  if (r != 'shared') downloadBytes(bytes, fileName);
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
