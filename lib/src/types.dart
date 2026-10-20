import 'dart:typed_data';

/// The file format a Sigma sheet is kept in; every save rewrites it in this format.
enum SigmaFormat {
  xlsx,
  csv;

  static SigmaFormat? parse(Object? v) => SigmaFormat.values.where((f) => f.name == v).firstOrNull;
}

/// What a signed link lets the person holding it do.
enum SigmaLinkMode {
  edit,
  view;

  static SigmaLinkMode parse(Object? v) => v == 'view' ? view : edit;
}

/// Where the sheet's latest edits are.
enum SigmaSaveState {
  saved,
  unsaved,
  saving,
  failed;

  static SigmaSaveState parse(Object? v) => SigmaSaveState.values.where((s) => s.name == v).firstOrNull ?? saved;
}

/// The sheet that is open, as Sigma described it.
class SigmaDocument {
  const SigmaDocument({
    required this.id,
    required this.title,
    required this.filename,
    required this.format,
    required this.mode,
    required this.test,
  });

  final int id;
  final String title;
  final String filename;
  final SigmaFormat format;
  final SigmaLinkMode mode;

  /// Opened with a test-mode API key (capped, and deleted after a week).
  final bool test;

  static SigmaDocument fromMap(Map<Object?, Object?> m) => SigmaDocument(
        id: (m['id'] as num?)?.toInt() ?? 0,
        title: m['title'] as String? ?? '',
        filename: m['filename'] as String? ?? '',
        format: SigmaFormat.parse(m['format']) ?? SigmaFormat.xlsx,
        mode: SigmaLinkMode.parse(m['mode']),
        test: m['test'] == true,
      );

  @override
  String toString() => 'SigmaDocument($id, $title, ${mode.name}${test ? ', test' : ''})';
}

/// A sheet exported from the editor.
class SigmaFile {
  const SigmaFile({required this.bytes, required this.filename, required this.format, required this.mimeType});

  final Uint8List bytes;
  final String filename;
  final SigmaFormat format;
  final String mimeType;

  static SigmaFile fromMap(Map<Object?, Object?> m) => SigmaFile(
        bytes: m['bytes'] as Uint8List? ?? Uint8List(0),
        filename: m['filename'] as String? ?? '',
        format: SigmaFormat.parse(m['format']) ?? SigmaFormat.xlsx,
        mimeType: m['mimeType'] as String? ?? 'application/octet-stream',
      );
}

/// What went wrong, as a code to switch on.
enum SigmaErrorCode {
  /// The API key is missing, wrong or revoked (401).
  unauthorized,

  /// This month's allowance of sheet opens is used up, or a test key's cap (402).
  quotaExceeded,

  /// The document does not exist (404).
  notFound,

  /// The link has expired, or the editing session it started has ended (410).
  linkExpired,

  /// The link is not valid or was revoked (403).
  linkInvalid,

  /// Your `link` function threw, or returned something that is not a URL.
  linkFailed,

  /// Sigma's spreadsheet engine refused or failed.
  engine,

  /// The sheet is not open yet.
  notReady,

  /// The editor refused (a view-only link asked to save, …).
  editor,

  /// Any other answer from the server.
  server,

  /// The request did not reach the server.
  network,

  /// This platform has no native Sigma editor (only Android and iOS do).
  unsupportedPlatform;

  static const _wire = {
    'unauthorized': unauthorized,
    'quota_exceeded': quotaExceeded,
    'not_found': notFound,
    'link_expired': linkExpired,
    'link_invalid': linkInvalid,
    'link_failed': linkFailed,
    'engine': engine,
    'not_ready': notReady,
    'editor': editor,
    'server': server,
    'network': network,
    'unsupported_platform': unsupportedPlatform,
  };

  /// The code as the native side sends it ("quota_exceeded").
  static SigmaErrorCode parse(Object? v) => _wire[v] ?? server;
}

/// Everything that can go wrong, with the message Nimbus Cloud or Sigma gave.
class SigmaError implements Exception {
  const SigmaError(this.code, this.message, {this.status});

  final SigmaErrorCode code;
  final String message;

  /// The HTTP status, for `server` errors.
  final int? status;

  static SigmaError fromMap(Map<Object?, Object?> m) => SigmaError(
        SigmaErrorCode.parse(m['code']),
        m['message'] as String? ?? '',
        status: (m['status'] as num?)?.toInt(),
      );

  @override
  String toString() => 'SigmaError(${code.name}${status != null ? ' $status' : ''}): $message';
}
