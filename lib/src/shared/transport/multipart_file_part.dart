import 'dart:typed_data';

/// One binary part in a multipart form request.
final class MultipartFilePart {
  MultipartFilePart({
    required this.field,
    required this.fileName,
    required Uint8List bytes,
    this.contentType = 'application/octet-stream',
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (field.trim().isEmpty || field.contains('"')) {
      throw ArgumentError('Invalid multipart field name');
    }
    if (fileName.trim().isEmpty ||
        fileName.contains('\r') ||
        fileName.contains('\n')) {
      throw ArgumentError('Invalid multipart fileName');
    }
    if (contentType.trim().isEmpty ||
        contentType.contains('\r') ||
        contentType.contains('\n')) {
      throw ArgumentError('Invalid multipart contentType');
    }
  }

  final String field;
  final String fileName;
  final Uint8List bytes;
  final String contentType;
}
