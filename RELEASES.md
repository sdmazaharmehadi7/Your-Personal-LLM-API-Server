# Sovereign AI — Official Production Release Manifest

Version: **1.0.0+1**  
Commit / Engine: Flutter 3.47.7 (Dart 3.13.5)  
Inference Engine: Local `llamadart` (GGUF llama.cpp) + Local Neural Embedding (`all-MiniLM-L6-v2-Q4_K_M.gguf`, 384-d)

---

## 1. Release Artifacts Summary

| Target Platform | Package Name | Size | Architecture | Verified SHA-256 Checksum |
| :--- | :--- | :---: | :---: | :--- |
| **macOS** | `SovereignAI-1.0.0-macos.zip` | 30.1 MB *(82.2 MB uncompressed .app)* | Universal (arm64 / x86_64) | `05032e5259636633d46f506e791577bf755cdd59227e4fccb2cc72d6a7a2b7ee` |
| **Android** | `app-release.apk` | 128.7 MB | `arm64-v8a` | `988714a11b86599c5a6ebaf7aa21fa4117569de0e5f8897b67d8e0a13ed0aa35` |
| **iOS** *(Binary Compiled)* | `SovereignAI-1.0.0-ios-unsigned.ipa` | 13.0 MB *(35.2 MB Runner.app)* | `arm64` (iOS 16.4+) | `1277335437a34957d323a70ce83840893efa6408cc3758072e22749153988ac1` |
| **Windows Desktop** | `SovereignAI-1.0.0-windows-x64.zip` | Build on Windows runner | `x86_64` | *Automated via GitHub Actions* |
| **Linux Desktop** | `SovereignAI-1.0.0-linux-x64.tar.gz` | Build on Linux runner | `x86_64` | *Automated via GitHub Actions* |

---

## 2. Installation & Running Instructions

### macOS
1. Extract `SovereignAI-1.0.0-macos.zip`.
2. Drag `sovereign_ai.app` into your `/Applications` directory.
3. Open `sovereign_ai.app`.
4. Navigate to the **Model Manager** tab to download any catalog model (e.g., `SmolLM2 135M` for rapid testing, or `Qwen 2.5 0.5B / 1.5B`).
5. Download the **23 MB `all-MiniLM-L6-v2`** model to enable on-device Neural RAG.

### Android
1. Transfer `app-release.apk` to your Android device (Android 7.0+ / arm64-v8a).
2. Install the APK via your file manager.
3. Open the app, grant storage permissions when prompted for document ingestion.
4. Download or import your preferred GGUF models directly within the app.

### iOS
1. **Xcode Direct Signing**:
   - Open `/Users/sayyadmazaharmehadi/Developer/sovereign_ai/ios/Runner.xcworkspace` in Xcode.
   - Select the `Runner` project > **Signing & Capabilities**.
   - Under **Team**, select your Apple Developer account.
   - Connect your iPhone (iOS 16.4+) or select **Any iOS Device (arm64)**.
   - Select **Product > Archive**, or deploy directly via **Run**.
2. **Sideloading / Ad-hoc Signing**:
   - The compiled package `build/ios/ipa/SovereignAI-1.0.0-ios-unsigned.ipa` contains the native `llama.framework`, `llamadart-llama-cpp-flutter.framework`, and Flutter assets.
   - Sign using your personal free or paid certificate using AltStore, Sideloadly, or `fastlane sigh / codesign`.

### Windows Desktop (via CI/CD)
1. Runs automatically via `.github/workflows/release-windows.yml` on push/tag.
2. Download the artifact `SovereignAI-1.0.0-windows-x64.zip`.
3. Unzip all files into a directory (e.g. `C:\Apps\SovereignAI`).
4. Run `sovereign_ai.exe`.

### Linux Desktop (via CI/CD)
1. Runs automatically via `.github/workflows/release-linux.yml` on push/tag.
2. Extract the archive:
   ```bash
   tar -xzf SovereignAI-1.0.0-linux-x64.tar.gz
   cd SovereignAI-1.0.0-linux-x64
   ./sovereign_ai
   ```

---

## 3. GitHub Actions Automated Workflows

The following workflows are committed under `.github/workflows/`:
1. [release-windows.yml](file:///Users/sayyadmazaharmehadi/Developer/sovereign_ai/.github/workflows/release-windows.yml): Builds on `windows-latest` with MSVC C++ toolchain, validates dependencies, packages `.zip`, computes SHA-256, and uploads artifact.
2. [release-linux.yml](file:///Users/sayyadmazaharmehadi/Developer/sovereign_ai/.github/workflows/release-linux.yml): Builds on `ubuntu-latest` with GTK3/Clang/Ninja, packages `.tar.gz`, computes SHA-256, and uploads artifact.
3. [release-ios.yml](file:///Users/sayyadmazaharmehadi/Developer/sovereign_ai/.github/workflows/release-ios.yml): Builds on `macos-14`, signs with repository secrets (if configured), or packages unsigned IPA.
