# Implementation Plan: Secure API Key Authentication and Management (Prompt 5)

## 1. Domain & Cryptographic Foundations
- **Entropy & Secret Generation:**
  - Generate 32 bytes (256 bits) of cryptographically secure random bytes via `Random.secure()`.
  - Format secret as `sk-sov-` followed by 64 lowercase hexadecimal characters (total 71 chars).
  - Store key prefix (e.g., `sk-sov-1a2b...`) for identification; **never** store or log the plaintext secret.
- **Hashing & Constant-Time Comparison:**
  - Generate a 16-byte random salt per key.
  - Compute `Hmac(sha256, saltBytes).convert(utf8.encode(secret))`.
  - Implement constant-time string comparison (`fixedTimeEquals`) via XOR accumulator to prevent timing side-channel attacks.
- **Model Definition (`lib/models/api_key.dart`):**
  - `ApiKeyPermission`: `chatCompletions`, `modelsList`.
  - `ApiKeyMetadata`: id, name, keyPrefix, createdAt, expiresAt, isRevoked, permissions, rateLimitRpm, maxConcurrentRequests, allowedModels, totalRequests, lastUsedAt, saltHex, hashHex.
  - `GeneratedApiKeyResult`: holds `metadata` and the ephemeral `plaintextSecret` (accessible only during creation).

## 2. Storage & Service Layer (`lib/services/api_server/api_key_service.dart`)
- **Storage Abstraction (`IApiKeyStorage`):**
  - `FileApiKeyStorage`: Reads/writes encrypted/sandboxed `api_keys.json` in macOS Application Support (`~/Library/Containers/.../Data/Library/Application Support/sovereign_ai/`).
  - `InMemoryApiKeyStorage`: Isolated mock for unit testing.
  - Atomic write pattern with temporary file and rename to prevent corruption.
- **Authentication & Policy Enforcement:**
  - `authenticate(String? authHeader, {required ApiKeyPermission requiredPermission, String? requestedModel})`:
    - Validates Bearer token format.
    - Constant-time hash check across non-revoked, unexpired keys.
    - Validates required permission -> HTTP 403 on failure.
    - Validates model restrictions -> HTTP 403 on failure.
    - Enforces rate limits (sliding 60-second window) -> HTTP 429 with `Retry-After`.
    - Enforces concurrent request limits -> HTTP 429.
  - Safe slot acquisition & release on completion, cancellation, and client disconnect.
  - Immediate revocation: setting `isRevoked: true` persists and takes effect instantly.

## 3. HTTP Server Integration (`LocalApiServer`)
- Update `LocalApiServer` to take `ApiKeyService`.
- Keep loopback `127.0.0.1` binding and manual start/stop.
- `/health`: Public on localhost (readiness check, no sensitive paths or secrets).
- `/v1/models`: Authenticated with `ApiKeyPermission.modelsList`.
- `/v1/chat/completions`: Authenticated with `ApiKeyPermission.chatCompletions` and model allowlist check BEFORE reading large payload or invoking `IInferenceCoordinator`.
- Return OpenAI-compatible 401, 403, and 429 error envelopes.
- No Authorization headers or secrets logged.

## 4. Settings UI (`lib/ui/settings/widgets/api_keys_card.dart`)
- Integrated into `SettingsScreen` directly below `ApiServerCard`.
- Key creation dialog: Name, optional expiry, permissions, RPM limit.
- One-time secret display dialog: Copy button, clear security warning that secret cannot be viewed again.
- Key list view: Name, prefix, status badge, created date, expiry, request count, Revoke and Delete buttons.

## 5. Verification & Tests
- Comprehensive test suite covering all 18 requirements:
  - Key entropy, one-time secret display, hash-only storage, Bearer parsing.
  - 401 for invalid/expired/revoked/missing keys.
  - 403 for permission mismatch and model restrictions.
  - 429 for rate limit (with `Retry-After`) and concurrency limits.
  - Immediate revocation, persistence across restarts, and disconnect cleanup.
- Full `flutter analyze` and `flutter test` verification.
