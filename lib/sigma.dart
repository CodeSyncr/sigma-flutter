/// Sigma's native spreadsheet editor in Flutter apps, through the Sigma iOS
/// and Android SDKs. The editor runs Sigma's engine, which Sigma serves only
/// to a session opened with a signed link; your server mints links with its
/// `sgm_` key, and the app asks your server for them.
library;

export 'src/sheet.dart' show SigmaSheet, SigmaSheetController, SigmaLinkProvider;
export 'src/types.dart';
