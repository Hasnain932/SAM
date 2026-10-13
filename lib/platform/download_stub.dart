
// Used on Android/iOS. Never called there (the app checks kIsWeb first).
void downloadBytes(List<int> bytes, String fileName) {
  throw UnsupportedError('Browser download is only available on web.');
}
