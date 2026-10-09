// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

// Web only: saves the bytes as a file download in the browser.
void downloadBytes(List<int> bytes, String fileName) {
  // Pick the file type from the extension: .json for backups, .xlsx for reports.
  final mime = fileName.toLowerCase().endsWith('.json')
      ? 'application/json'
      : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  final blob = html.Blob([Uint8List.fromList(bytes)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}
