import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigma_flutter/sigma_flutter.dart';
import 'package:sigma_flutter/src/sheet.dart' show handleSheetCall;

void main() {
  group('types', () {
    test('reads a document as the native side sends it', () {
      final d = SigmaDocument.fromMap({'id': 7, 'title': 'Budget', 'filename': 'Budget.xlsx', 'format': 'xlsx', 'mode': 'view', 'test': true});
      expect(d.id, 7);
      expect(d.title, 'Budget');
      expect(d.format, SigmaFormat.xlsx);
      expect(d.mode, SigmaLinkMode.view);
      expect(d.test, isTrue);
    });

    test('reads error codes, and an unknown one as server', () {
      expect(SigmaError.fromMap({'code': 'quota_exceeded', 'message': 'used up'}).code, SigmaErrorCode.quotaExceeded);
      expect(SigmaError.fromMap({'code': 'link_failed', 'message': 'x'}).code, SigmaErrorCode.linkFailed);
      final e = SigmaError.fromMap({'code': 'server', 'message': 'boom', 'status': 503});
      expect(e.status, 503);
      expect(SigmaErrorCode.parse('something new'), SigmaErrorCode.server);
    });

    test('reads an exported file', () {
      final f = SigmaFile.fromMap({'bytes': Uint8List.fromList([1, 2, 3]), 'filename': 'a.csv', 'format': 'csv', 'mimeType': 'text/csv'});
      expect(f.bytes, [1, 2, 3]);
      expect(f.format, SigmaFormat.csv);
    });

    test('save states', () {
      expect(SigmaSaveState.parse('saving'), SigmaSaveState.saving);
      expect(SigmaSaveState.parse(null), SigmaSaveState.saved);
    });
  });

  group('calls from the native view', () {
    SigmaSheet sheet({
      required SigmaLinkProvider link,
      ValueChanged<SigmaDocument>? onReady,
      ValueChanged<SigmaError>? onError,
      void Function(SigmaSaveState, SigmaError?)? onSaveStateChange,
      ValueChanged<String>? onTitleChange,
      ValueChanged<DateTime>? onSaved,
    }) =>
        SigmaSheet(link: link, onReady: onReady, onError: onError, onSaveStateChange: onSaveStateChange, onTitleChange: onTitleChange, onSaved: onSaved);

    test('a link request is answered by the link function', () async {
      final w = sheet(link: () async => 'https://nimbusgo.space/v/sigma/7?sig=abc');
      expect(await handleSheetCall(const MethodCall('link'), w), 'https://nimbusgo.space/v/sigma/7?sig=abc');
    });

    test('a link function that throws fails the request as link_failed', () async {
      final w = sheet(link: () async => throw Exception('server down'));
      await expectLater(handleSheetCall(const MethodCall('link'), w),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'link_failed').having((e) => e.message, 'message', 'server down')));
    });

    test('something that is not a link fails as link_failed', () async {
      final w = sheet(link: () async => 'not a link');
      await expectLater(handleSheetCall(const MethodCall('link'), w), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'link_failed')));
    });

    test('ready and failed phases reach onReady and onError', () async {
      SigmaDocument? ready;
      SigmaError? failed;
      final w = sheet(link: () async => '', onReady: (d) => ready = d, onError: (e) => failed = e);
      await handleSheetCall(const MethodCall('phase', {'phase': 'loading'}), w);
      expect(ready, isNull);
      await handleSheetCall(const MethodCall('phase', {'phase': 'ready', 'document': {'id': 3, 'title': 'T', 'filename': 'T.xlsx', 'format': 'xlsx', 'mode': 'edit', 'test': false}}), w);
      expect(ready?.id, 3);
      await handleSheetCall(const MethodCall('phase', {'phase': 'failed', 'error': {'code': 'link_expired', 'message': 'expired'}}), w);
      expect(failed?.code, SigmaErrorCode.linkExpired);
    });

    test('save state, title and saves reach their callbacks', () async {
      final states = <SigmaSaveState>[];
      SigmaError? saveError;
      String? title;
      DateTime? saved;
      final w = sheet(
        link: () async => '',
        onSaveStateChange: (s, e) { states.add(s); saveError = e; },
        onTitleChange: (t) => title = t,
        onSaved: (at) => saved = at,
      );
      await handleSheetCall(const MethodCall('saveState', {'state': 'saving'}), w);
      await handleSheetCall(const MethodCall('saveState', {'state': 'failed', 'error': {'code': 'network', 'message': 'offline'}}), w);
      await handleSheetCall(const MethodCall('title', {'title': 'Q3 plan'}), w);
      await handleSheetCall(const MethodCall('saved', {'at': 1760000000000}), w);
      expect(states, [SigmaSaveState.saving, SigmaSaveState.failed]);
      expect(saveError?.code, SigmaErrorCode.network);
      expect(title, 'Q3 plan');
      expect(saved, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    });
  });

  test('a controller with no sheet says so', () async {
    await expectLater(SigmaSheetController().save(), throwsA(isA<SigmaError>().having((e) => e.code, 'code', SigmaErrorCode.notReady)));
  });
}
