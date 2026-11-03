# NeonTunes

NeonTunes is a Flutter Android starter app with a neon-dark interface, Internet Archive audio discovery, downloads to app-private storage, local audio import/playback, and lyrics lookup through LRCLIB.

## Build an APK using GitHub (no Android Studio on your PC)

1. Create a new **public or private** GitHub repository named `neontunes`.
2. Upload the contents of this project to the repository root (the `lib`, `.github`, and `pubspec.yaml` items must be at the root). The workflow generates the Android Gradle project files automatically.
3. Open the repository's **Actions** tab and enable GitHub Actions if prompted.
4. Choose **Build NeonTunes Android APK** and click **Run workflow**.
5. Wait for the workflow to finish successfully.
6. Open the completed workflow run, scroll to **Artifacts**, and download `neontunes-android-apk`.
7. Extract the downloaded ZIP. Install `app-release.apk` on your Android phone.

Every push to `main` also starts a build. To publish a GitHub Release, create and push a version tag such as `v1.0.0`.

## What is included

- Dark neon-purple/blue Flutter UI.
- Search of Internet Archive audio items and discovery of MP3 files.
- Download MP3s into the app's private documents folder.
- Import audio files using Android's file picker.
- Offline playback of downloaded/imported files.
- Lyrics lookup using LRCLIB, including synced lyrics when the provider has timestamps.

## Important limitations

- Search results come from Internet Archive. A file being downloadable does **not** mean it is public domain or licensed for every use. Check the item page and its license before downloading, sharing, or reusing it.
- Lyrics depend on LRCLIB availability and matching. Not every track or language has lyrics; translation is not included in this first version.
- Search currently inspects a limited number of results and MP3 files only. Some archive items may not expose a playable MP3.
- Downloaded files are stored in app-private storage. They are visible in NeonTunes, but not automatically exported to the public Music folder.
- This is an initial working starter, not a polished commercial release. Test on your own device before distributing.

## Local build (optional)

Install Flutter, generate the Android platform files once, then run:

```bash
flutter pub get
flutter run
flutter build apk --release
```

## Privacy

NeonTunes does not require an account. Search requests go to Internet Archive; lyrics lookups go to LRCLIB. Audio downloads are fetched from Internet Archive. Avoid downloading material unless you have permission.
