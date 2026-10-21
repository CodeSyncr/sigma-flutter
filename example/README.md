# sigma_flutter example

Lists the sheets on a Nimbus Cloud account, opens one in `SigmaSheet`, whose header has the back arrow and sharing. It keeps a test key on the device so it runs on its own; a real app keeps the key on its server and asks the server for links.

```bash
flutter run --dart-define=SIGMA_CLOUD=https://nimbusgo.space --dart-define=SIGMA_KEY=sgm_test_…
```

Without the defines, type the cloud and key into the first screen.

To build against a sigma-android published to `~/.m2` (working on the SDK itself), uncomment `sigmaMavenLocal=true` in `android/gradle.properties`.
