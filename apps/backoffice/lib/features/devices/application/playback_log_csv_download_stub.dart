/// Fallback used on non-web platforms (incl. Flutter test VM). No-op.
void downloadCsv(String csv, String filename) {
  // Intentionally empty — download is only meaningful on Flutter Web.
}
