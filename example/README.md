# sigma_flutter example

Lists the sheets on a Nimbus Cloud account, opens one in `SigmaSheet`, and exports it as CSV. It keeps a test key on the device so it runs on its own; a real app keeps the key on its server and asks the server for links.

```bash
flutter run --dart-define=SIGMA_CLOUD=https://nimbusgo.space --dart-define=SIGMA_KEY=sgm_test_…
```

Without the defines, type the cloud and key into the first screen.

`android/gradle.properties` sets `sigmaMavenLocal=true`, which takes sigma-android from `~/.m2` first (a build of the SDK not yet on JitPack); without one there, the build uses JitPack as usual.
