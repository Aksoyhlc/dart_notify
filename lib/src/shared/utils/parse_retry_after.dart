import 'dart:io';

/// Reads HTTP Retry-After as delta seconds or an absolute HTTP date.
Duration? parseRetryAfter(String? header) {
  if (header == null) return null;
  final seconds = int.tryParse(header.trim());
  if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
  try {
    final date = HttpDate.parse(header);
    final difference = date.difference(DateTime.now().toUtc());
    return difference.isNegative ? Duration.zero : difference;
  } on FormatException {
    return null;
  }
}
