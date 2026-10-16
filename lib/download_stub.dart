// Used on Android / iOS / desktop builds. The web versions of these
// functions live in download_web.dart.
void downloadBytes(List<int> bytes, String fileName) {
  throw UnsupportedError('downloadBytes is only available on web');
}

Future<void> saveOrShareBytes(List<int> bytes, String fileName,
    {String? text}) async {
  throw UnsupportedError('saveOrShareBytes is only available on web');
}

Future<String> shareBytesNow(List<int> bytes, String fileName,
    {String? text}) async {
  throw UnsupportedError('shareBytesNow is only available on web');
}

void setAppBusy(bool busy) {}
