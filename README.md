# Nimbus Sigma for Flutter

Sigma's native spreadsheet editor in your Flutter app, backed by [Sigma](https://nimbusgo.space/cloud/docs/sigma) on Nimbus Cloud. Upload a spreadsheet from your server, open it in the app, and people edit it with formulas, formatting, charts, several sheets and Vani AI. Every change saves back as they type, and your server downloads the edited `.xlsx` or CSV whenever it likes.

This plugin is a thin layer over the native SDKs, so the editor is the native one on each platform, shown as a platform view: [NimbusSigma](https://github.com/CodeSyncr/sigma-ios) on iOS and [sigma-android](https://github.com/CodeSyncr/sigma-android) on Android. There is no web view. The formulas are Sigma's own engine, which a session downloads from Sigma for a sheet opened through the API; it is not in this plugin, so the editor works only with a Nimbus Cloud account and a Sigma API key.

**Requirements:** Flutter 3.27 or later, iOS 16, Android 8.0 (API 26). On platforms other than Android and iOS the widget shows a note.

## Install

```bash
flutter pub add sigma
```

### iOS

With CocoaPods (Flutter's default), the native SDK comes from its git tag. Until `NimbusSigma` is on the CocoaPods trunk, add it to `ios/Podfile` inside the `Runner` target, and raise the platform to iOS 16:

```ruby
platform :ios, '16.0'

target 'Runner' do
  use_frameworks!

  pod 'NimbusSigma', :git => 'https://github.com/CodeSyncr/sigma-ios.git', :tag => '2.1.1'
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  # …
end
```

Set the Runner target's minimum deployment to iOS 16 in Xcode too, then `cd ios && pod install`. With Flutter's Swift Package Manager support on (`flutter config --enable-swift-package-manager`), the Podfile line is not needed: the plugin's package depends on NimbusSigma itself.

### Android

Set `minSdk = 26` in `android/app/build.gradle.kts`. The native SDK is on [JitPack](https://jitpack.io/#CodeSyncr/sigma-android); the plugin adds that repository itself, but if your build refuses project repositories (`RepositoriesMode.FAIL_ON_PROJECT_REPOS`), add it in `android/settings.gradle.kts`:

```kotlin
dependencyResolutionManagement { repositories { maven("https://jitpack.io") } }
```

To pin another release of the native SDK, set `sigmaAndroidVersion=1.0.2` in `android/gradle.properties`.

## How it fits together

```
your server ──(sgm_ key)──▶ Nimbus Cloud     upload sheets, mint signed links, download edits
     │
     └──(signed link)──▶ your app ──▶ SigmaSheet     edits save straight back
```

**Billing.** Sigma's API counts each time a sheet is opened in an editor (in your app or embedded on the web), not uploads; your plan includes an allowance each month. Test keys (`sgm_test_`) are for building: their opens are capped and their sheets are deleted after a week, and the editor shows "Test mode".

**Keep the `sgm_` key on your server.** A key in an app can be read by anyone who has the app, and it can read and delete every document on your account. The app only ever needs a link, which expires (fifteen minutes by default; one minute to seven days). Once a link opens a sheet, the editing session lasts eight hours.

On your server (any language; here, the REST API):

```bash
# Upload, or create a blank sheet with {"title": "Budget", "blank": "xlsx"}
curl -X POST "https://nimbusgo.space/api/v1/sigma/documents?mode=edit" \
  -H "Authorization: Bearer $SIGMA_KEY" -F file=@budget.xlsx

# A fresh link for the app
curl -X POST "https://nimbusgo.space/api/v1/sigma/documents/42/link?mode=edit" \
  -H "Authorization: Bearer $SIGMA_KEY"

# The edited file, later
curl "https://nimbusgo.space/api/v1/sigma/documents/42/content" \
  -H "Authorization: Bearer $SIGMA_KEY" -o budget.xlsx
```

## Use

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sigma/sigma.dart';

class SheetScreen extends StatefulWidget {
  const SheetScreen({super.key, required this.sheetId});
  final int sheetId;

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  final sheet = SigmaSheetController();

  // Asked when the sheet opens, and again whenever a link expires.
  Future<String> _link() async {
    final res = await http.post(Uri.parse('https://your.server/sheets/${widget.sheetId}/link'));
    return jsonDecode(res.body)['url'] as String;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: [IconButton(icon: const Icon(Icons.save), onPressed: sheet.save)]),
        body: SigmaSheet(
          link: _link,
          controller: sheet,
          onReady: (doc) => debugPrint('opened ${doc.title}${doc.test ? ' (test key)' : ''}'),
          onError: (e) => debugPrint('${e.code.name}: ${e.message}'),
          onSaveStateChange: (state, error) => debugPrint(state.name),
        ),
      );
}
```

Your `link` function returns the URL your server got from `POST /documents/:id/link`. If it throws, the editor shows the error with a Try again button, and `onError` reports `SigmaErrorCode.linkFailed` with your exception's message.

### SigmaSheet

| | |
|---|---|
| `link` | `Future<String> Function()`: a fresh signed link from your server. Required. |
| `controller` | A `SigmaSheetController`, to drive the sheet from your own controls. |
| `onReady(document)` | The sheet opened: a `SigmaDocument` with `id`, `title`, `filename`, `format`, `mode` and `test`. |
| `onError(error)` | It could not open or reopen. `error.code` is one of the codes below. |
| `onSaveStateChange(state, error)` | `saved`, `unsaved`, `saving` or `failed` (with the `SigmaError`). |
| `onTitleChange(title)` | The sheet was renamed. |
| `onSaved(at)` | A save landed. |
| `showHeader`, `showBack`, `showLogo` | The header and its parts; all `true` by default. |
| `onBack` | What the header's back arrow does; `Navigator.maybePop` when it is not set. |

### The header

Above the formula bar: a back arrow, Sigma's mark, the sheet's title with where its edits are, and sharing; tapping the title renames the sheet. `showHeader: false` removes it (your screen has its own app bar), `showBack` and `showLogo` hide their parts, and `onBack` decides what the arrow does: without it, the arrow pops the route the sheet is on. The editor's menus are its own, the same on Android and iOS whatever your app's theme.

### Who gets Vani

Vani needs a paid Nimbus Cloud plan, and you decide which of your users get it: your server mints the link with `?ai=off` for someone who has not paid you for AI, and their editor has no Vani. The choice is signed into the link, so the app cannot turn it back on.

### SigmaSheetController

```dart
await sheet.save();                               // save now, without waiting
final file = await sheet.export(SigmaFormat.csv); // SigmaFile: bytes, filename, format, mimeType
await sheet.undo();
await sheet.redo();
await sheet.reload();                             // open again from a fresh link
await sheet.rename('Q4 budget');
```

Calls before the sheet has opened throw a `SigmaError` with `SigmaErrorCode.notReady`.

### Errors

`SigmaError` has a `code`: `unauthorized`, `quotaExceeded` (the month's allowance of opens, or a test key's cap, is used up), `notFound`, `linkExpired`, `linkInvalid`, `linkFailed` (your `link` function threw), `engine`, `notReady`, `editor` (for example saving through a view-only link), `server` (with `status`), `network` or `unsupportedPlatform`.

### What people get

The same editor as the native SDKs: a grid with frozen panes, selection handles, pinch zoom, in-cell and formula-bar editing with function suggestions, drag to fill, and column and row resizing; a format bar (bold, italic, underline, strikethrough, colours, alignment, number formats, borders, text size) with a ⋮ More menu; find and replace; sort that keeps a header row; conditional formatting; notes; charts bound to their cells; Vani AI when your account is on a paid plan and the link allows it; sharing as Excel or CSV.

## Example

[`example`](example) is a small app: list your sheets, open one, edit it, export it. Like the native demos, it keeps a test key on the device so it runs on its own; a real app asks its server for links.

```bash
cd example
flutter run --dart-define=SIGMA_CLOUD=https://nimbusgo.space --dart-define=SIGMA_KEY=sgm_test_…
```

## License

Proprietary. The SDK may be used only with Nimbus Cloud's Sigma API under your Nimbus Cloud account; see [LICENSE](LICENSE).
