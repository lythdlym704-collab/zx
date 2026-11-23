# Build path and CameraX lint repair

Modern Flutter Android templates can redirect Gradle build outputs to the workspace
root `build/`, so searching `android/app/build` was incorrect. The workflow
uses `flutter build apk --release` and checks
`build/app/outputs/flutter-apk/app-release.apk`.

Before building, it appends a Kotlin DSL or Groovy Gradle configuration that
disables only `lintVitalAnalyzeRelease` in the `camera_android_camerax`
subproject, addressing the previously reported CommentDetector crash.

The workflow has not been run in GitHub Actions in this environment.
