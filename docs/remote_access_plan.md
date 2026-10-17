# Implementation Plan: Secure Remote Access (Prompt 6)

## 1. Objectives & Trust Boundaries
- **Objective:** Enable authorized external developers on other networks to access the local GGUF model API through an encrypted public HTTPS tunnel.
- **Loopback Enforcement:** `LocalApiServer` remains bound **strictly to 127.0.0.1**. It will never bind to `0.0.0.0` or open public router ports.
- **Provider Choice:** Cloudflare Quick Tunnels (`cloudflared`) as the primary zero-cost, zero-account, temporary HTTPS tunnel solution, complemented by an extensible provider abstraction (`IRemoteAccessProvider`).
- **Authentication:** All requests over the public tunnel must present valid `Authorization: Bearer <API_KEY>` credentials. API key validation, rate limits, concurrency controls, and model restrictions are preserved identically.
- **Local Control:** Remote access is disabled by default. It can only be started explicitly from the local Settings UI while the local API server is running, and stops automatically when the local server or app shuts down.

## 2. Component Design

### 2.1 Provider Abstraction (`lib/services/remote_access/remote_access_provider.dart`)
- `RemoteAccessStatus`: `disabled`, `starting`, `connected`, `stopping`, `error`.
- `IRemoteAccessProvider`:
  - `String get name`
  - `Future<bool> checkPrerequisites()`
  - `Future<String> startTunnel({required int localPort, required String localHost})`
  - `Future<void> stopTunnel()`
  - `String? get publicHttpsUrl`
  - `RemoteAccessStatus get status`
  - `String? get errorMessage`
- `CloudflareQuickTunnelProvider`:
  - Locates `cloudflared` binary on macOS (`/opt/homebrew/bin/cloudflared`, `/usr/local/bin/cloudflared`, or `$PATH`).
  - Executes `cloudflared tunnel --url http://127.0.0.1:<localPort> --no-autoupdate`.
  - Captures the generated `https://*.trycloudflare.com` URL from stderr.
  - Monitors child process exit and safely terminates on stop or disposal.
  - Never silently downloads or runs unverified binaries; provides clear setup guidance if not found.
- `MockRemoteAccessProvider`:
  - Controllable provider for automated unit testing without network or external binary dependencies.

### 2.2 Remote Access Manager (`lib/services/remote_access/remote_access_manager.dart`)
- `ChangeNotifier` coordinating the tunnel with `LocalApiServer`.
- Enforces dependencies:
  - Cannot start remote access if `LocalApiServer.isRunning` is false.
  - Automatically stops tunnel if `LocalApiServer` is stopped.
  - Idempotent start and stop methods.
  - Clears public URL immediately upon stop or error.
  - Listens to server lifecycle to ensure synchronized teardown.

### 2.3 Settings UI (`lib/ui/settings/widgets/remote_access_card.dart`)
- Added to `SettingsScreen` under the server and API keys sections.
- Visual status badges and controls:
  - Start / Stop Remote Access buttons.
  - Display and copy button for the public HTTPS URL (only shown while active).
  - Clear prerequisites / installation check status (`cloudflared` found vs instructions to run `brew install cloudflared`).
  - Security warning: Remote inference consumes local hardware resources (CPU, GPU, battery).

## 3. Automated Test Suite (`test/remote_access_test.dart`)
- Covers all 18 requirements:
  - Disabled by default.
  - Fails safely if local server is stopped.
  - No duplicate servers or duplicate tunnel processes.
  - Idempotent start/stop.
  - Sudden process termination handling.
  - Stopping local server stops tunnel.
  - Model and chat state unaffected.
  - API key authentication, rate limits, and model allowlists enforced on remote traffic.
  - Bound to 127.0.0.1 exclusively.

## 4. Documentation & Verification
- Update `docs/api_server_architecture.md` with remote access architecture, curl, Python OpenAI SDK, and Node.js SDK examples.
- Validate `dart format`, `flutter analyze`, and `flutter test`.
