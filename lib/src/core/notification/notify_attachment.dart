import 'dart:typed_data';

/// In-memory attachment for [NotifyMessage], with bytes copied into an
/// immutable buffer.
///
/// [fileName] and [contentType] must be non-empty and free of CR and LF.
/// Providers that support attachments enforce their own count and size limits.
final class NotifyAttachment {
  NotifyAttachment({
    required this.fileName,
    required Uint8List bytes,
    this.contentType = 'application/octet-stream',
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (fileName.trim().isEmpty ||
        fileName.contains('\r') ||
        fileName.contains('\n')) {
      throw ArgumentError('Invalid attachment fileName');
    }
    if (contentType.trim().isEmpty ||
        contentType.contains('\r') ||
        contentType.contains('\n')) {
      throw ArgumentError('Invalid attachment contentType');
    }
  }

  final String fileName;
  final Uint8List bytes;
  final String contentType;
}
