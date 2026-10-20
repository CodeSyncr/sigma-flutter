import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

/// Asked for a signed link to the sheet. Call your server, which mints it
/// with its `sgm_` key; never put the key in the app.
typedef SigmaLinkProvider = Future<String> Function();

const _viewType = 'sigma_flutter/sheet';

/// Sigma's native spreadsheet editor: a header with a back arrow, Sigma's mark,
/// the title and sharing; the formula bar, format bar, grid, charts, find and
/// replace, notes, Vani AI and sheet tabs, saving as people edit. On Android
/// and iOS only; elsewhere it shows a note and reports
/// [SigmaErrorCode.unsupportedPlatform].
class SigmaSheet extends StatefulWidget {
  const SigmaSheet({
    super.key,
    required this.link,
    this.controller,
    this.onReady,
    this.onError,
    this.onSaveStateChange,
    this.onTitleChange,
    this.onSaved,
    this.showHeader = true,
    this.showBack = true,
    this.showLogo = true,
    this.onBack,
  });

  /// Asked for a signed link when the sheet opens, and again whenever one
  /// expires. Call your server, which mints it with its `sgm_` key.
  final SigmaLinkProvider link;

  /// Saves, exports, undoes and reloads the sheet from your own controls.
  final SigmaSheetController? controller;

  /// The sheet opened.
  final ValueChanged<SigmaDocument>? onReady;

  /// The sheet could not open (or reopen). The editor shows the error with a Try again button.
  final ValueChanged<SigmaError>? onError;

  final void Function(SigmaSaveState state, SigmaError? error)? onSaveStateChange;

  /// The sheet was renamed.
  final ValueChanged<String>? onTitleChange;

  /// A save landed.
  final ValueChanged<DateTime>? onSaved;

  /// Show the editor's header. Turn it off when your screen has its own app bar.
  final bool showHeader;

  /// Show the header's back arrow.
  final bool showBack;

  /// Show Sigma's mark beside the title.
  final bool showLogo;

  /// What the back arrow does. Without it, the arrow pops the route the
  /// sheet is on ([Navigator.maybePop]).
  final VoidCallback? onBack;

  Map<String, Object?> get _creationParams => {'header': showHeader, 'back': showBack, 'logo': showLogo};

  @override
  State<SigmaSheet> createState() => _SigmaSheetState();
}

class _SigmaSheetState extends State<SigmaSheet> {
  MethodChannel? _channel;
  bool _reportedUnsupported = false;

  static bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(SigmaSheet old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  /// The native view exists: listen to it, then let it start (so its first link request has an answerer).
  void _created(int id) {
    final channel = MethodChannel('sigma_flutter/sheet_$id');
    _channel = channel;
    channel.setMethodCallHandler(_handle);
    unawaited(channel.invokeMethod<void>('start'));
  }

  Future<Object?> _handle(MethodCall call) => handleSheetCall(call, widget, pop: () {
        if (mounted) Navigator.maybePop(context);
      });

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    final channel = _channel;
    if (channel == null) throw const SigmaError(SigmaErrorCode.notReady, 'The sheet is still opening.');
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      final status = (e.details is Map) ? ((e.details as Map)['status'] as num?)?.toInt() : null;
      throw SigmaError(SigmaErrorCode.parse(e.code), e.message ?? '', status: status);
    }
  }

  // The editor handles every touch itself: scrolling, selecting, dragging the fill handle.
  static final _gestures = <Factory<OneSequenceGestureRecognizer>>{Factory(() => EagerGestureRecognizer())};

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      if (!_reportedUnsupported) {
        _reportedUnsupported = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError?.call(
              const SigmaError(SigmaErrorCode.unsupportedPlatform, 'The Sigma editor runs on Android and iOS.'),
            ));
      }
      return const Center(child: Text('The Sigma editor runs on Android and iOS.', textAlign: TextAlign.center));
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: _viewType,
        onPlatformViewCreated: _created,
        gestureRecognizers: _gestures,
        creationParams: widget._creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    // Hybrid composition: the editor's own text fields, keyboard and dialogs behave as in a native app.
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: _gestures,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          creationParams: widget._creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_created)
          ..create();
        return controller;
      },
    );
  }
}

/// What a [SigmaSheet] does with a call from its native view: answer a link
/// request with the widget's `link` function, or pass news to its callbacks.
/// [pop] is the back arrow's default, when the widget has no `onBack`.
@visibleForTesting
Future<Object?> handleSheetCall(MethodCall call, SigmaSheet widget, {VoidCallback? pop}) async {
  final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
  switch (call.method) {
    case 'link':
      try {
        final url = await widget.link();
        if (Uri.tryParse(url)?.hasScheme != true) throw const FormatException('That is not a link.');
        return url;
      } catch (e) {
        throw PlatformException(code: 'link_failed', message: _linkFailure(e));
      }
    case 'phase':
      if (args['phase'] == 'ready' && args['document'] is Map) {
        widget.onReady?.call(SigmaDocument.fromMap(args['document'] as Map<Object?, Object?>));
      } else if (args['phase'] == 'failed' && args['error'] is Map) {
        widget.onError?.call(SigmaError.fromMap(args['error'] as Map<Object?, Object?>));
      }
    case 'saveState':
      final error = args['error'] is Map ? SigmaError.fromMap(args['error'] as Map<Object?, Object?>) : null;
      widget.onSaveStateChange?.call(SigmaSaveState.parse(args['state']), error);
    case 'title':
      widget.onTitleChange?.call(args['title'] as String? ?? '');
    case 'saved':
      widget.onSaved?.call(DateTime.fromMillisecondsSinceEpoch((args['at'] as num? ?? 0).toInt()));
    case 'back':
      (widget.onBack ?? pop)?.call();
  }
  return null;
}

/// What the editor shows when the `link` function failed: its message, without
/// the "Exception: " that `Exception('…').toString()` puts in front.
String _linkFailure(Object e) {
  if (e is FormatException) return e.message;
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
}

/// Drives a [SigmaSheet] from your own controls. Calls before the sheet has
/// opened throw [SigmaError] with [SigmaErrorCode.notReady].
class SigmaSheetController {
  _SigmaSheetState? _state;

  void _attach(_SigmaSheetState s) => _state = s;
  void _detach(_SigmaSheetState s) {
    if (_state == s) _state = null;
  }

  _SigmaSheetState get _sheet =>
      _state ?? (throw const SigmaError(SigmaErrorCode.notReady, 'No SigmaSheet uses this controller.'));

  /// Saves now, without waiting for the pause after typing.
  Future<void> save() async => _sheet._call<void>('save');

  /// The sheet as a file, in the format it is kept in or another.
  Future<SigmaFile> export([SigmaFormat? format]) async {
    final m = await _sheet._call<Map<Object?, Object?>>('export', {'format': format?.name});
    return SigmaFile.fromMap(m ?? const {});
  }

  Future<void> undo() async => _sheet._call<void>('undo');
  Future<void> redo() async => _sheet._call<void>('redo');

  /// Opens the sheet again from a fresh link.
  Future<void> reload() async => _sheet._call<void>('reload');

  Future<void> rename(String title) async => _sheet._call<void>('rename', {'title': title});
}
