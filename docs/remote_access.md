# Secure Remote Access Guide: Sovereign AI Personal LLM API Server

This document outlines how to securely access your Mac-hosted GGUF large language model from external networks and third-party developer machines using an encrypted Cloudflare HTTPS Quick Tunnel and API-key authentication.

---

## 1. Architecture Overview

```
External Developer (curl / Python / Node / OpenAI SDK)
                  │
                  ▼  (TLS Encrypted HTTPS)
  https://<random-id>.trycloudflare.com
                  │
                  ▼  (Cloudflare Edge & Outbound Tunnel Process)
      Mac Host running `cloudflared`
                  │
                  ▼  (Internal Loopback Forwarding)
         http://127.0.0.1:8080
                  │
         ┌────────┴────────┐
         ▼                 ▼
   Auth Middleware    Inference Coordinator
   (HMAC-SHA256,      (Single-flight FIFO Queue)
   Rate & Concurrency)     │
                           ▼
                     Loaded GGUF Model
```

### Security Invariants
1. **Loopback-Only Binding**: The Flutter HTTP server listens strictly on `127.0.0.1`. It never binds to `0.0.0.0` or any public interface.
2. **Encrypted Egress**: `cloudflared` initiates an outbound HTTPS/QUIC tunnel to Cloudflare edge nodes. No incoming router ports or NAT punch-through rules are required.
3. **Strict Authentication**: All remote endpoints (`/v1/chat/completions`, `/v1/models`) require valid HTTP `Authorization: Bearer <API_KEY>` headers. Authentication occurs before dispatch to the inference queue.
4. **Single Inference Coordinator**: Remote requests share the identical coordinator and memory pool as local UI chat. Models are never duplicated in RAM.
5. **Least-Privilege Health Checks**: The unauthenticated `/health` endpoint exposes minimal status (`{"status":"ok","model_loaded":true}`) without machine metadata, paths, or secrets.

---

## 2. Prerequisites & Installation

Sovereign AI uses the official Cloudflare Quick Tunnel provider (`cloudflared`).

### Installing `cloudflared` on macOS
Using Homebrew (recommended):
```bash
brew install cloudflared
```

Verify installation and version:
```bash
cloudflared --version
# Output: cloudflared version 2024.x.x (or newer)
```

The application detects `cloudflared` from standard system PATHs (`/opt/homebrew/bin/cloudflared`, `/usr/local/bin/cloudflared`, etc.).

---

## 3. Configuration & Lifecycle Management

### Step 1: Start the Local API Server
1. Launch **Sovereign AI** on macOS.
2. Ensure a GGUF model is loaded in memory (e.g., via the Model Management screen).
3. Navigate to **Settings** -> **Local API Server**.
4. Configure your desired local port (default: `8080`).
5. Toggle **Start Server**. The status indicator will turn green and display `http://127.0.0.1:8080`.

### Step 2: Create an API Key
1. In **Settings**, locate the **API Keys** card.
2. Click **Create Key**.
3. Provide a recognizable name (e.g. `remote-dev-laptop`).
4. Select desired permissions (e.g., `chat_completions`, `models_list`), rate limits (RPM), and concurrency limit.
5. **Copy the generated key immediately** (`sk-sov-...`). The full key secret is displayed only once and stored on disk as a salted HMAC-SHA256 hash with POSIX `0600` permissions.

### Step 3: Enable Secure Remote Access
1. Under **External Connections** in the API Server card, toggle **Enable Remote Access (HTTPS Tunnel)**.
2. The application launches `cloudflared tunnel --url http://127.0.0.1:<port> --no-autoupdate` as an isolated subprocess.
3. Once connected, the active HTTPS URL (e.g., `https://example-words-here.trycloudflare.com`) is displayed with a **Copy URL** button.

### Step 4: Emergency Stop / Disabling Access
- To immediately terminate remote access, toggle off **Enable Remote Access**. Sovereign AI terminates the `cloudflared` child process and clears the public URL from the UI.
- Stopping the local API server also automatically stops the active tunnel.
- Quitting the application cleanly terminates the tunnel process so no orphan background processes are left running.

---

## 4. Connecting from External Clients

OpenAI compatibility is focused on `/v1/chat/completions` and `/v1/models`. Set your environment variables first:

```bash
export SOVEREIGN_BASE_URL="https://your-tunnel-name.trycloudflare.com/v1"
export SOVEREIGN_API_KEY="sk-sov-your-generated-key-here"
```

### A. Testing with cURL

#### List Loaded Models:
```bash
curl -X GET "${SOVEREIGN_BASE_URL}/models" \
  -H "Authorization: Bearer ${SOVEREIGN_API_KEY}"
```

#### Non-Streaming Chat Completion:
```bash
curl -X POST "${SOVEREIGN_BASE_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SOVEREIGN_API_KEY}" \
  -d '{
    "model": "local",
    "messages": [
      {"role": "system", "content": "You are a concise engineering assistant."},
      {"role": "user", "content": "Explain symmetric vs asymmetric encryption in 2 sentences."}
    ],
    "temperature": 0.7,
    "max_tokens": 150
  }'
```

#### Streaming Chat Completion (Server-Sent Events):
```bash
curl -N -X POST "${SOVEREIGN_BASE_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SOVEREIGN_API_KEY}" \
  -d '{
    "model": "local",
    "messages": [
      {"role": "user", "content": "Count from 1 to 5 slowly."}
    ],
    "stream": true
  }'
```

---

### B. Python Client (OpenAI SDK v1.x)

```python
import os
from openai import OpenAI

# Initialize client using tunnel URL and API key from environment
client = OpenAI(
    base_url=os.environ.get("SOVEREIGN_BASE_URL"),
    api_key=os.environ.get("SOVEREIGN_API_KEY"),
)

# 1. Verify model access
models = client.models.list()
print("Available model:", models.data[0].id)

# 2. Streaming completion
stream = client.chat.completions.create(
    model="local",
    messages=[
        {"role": "system", "content": "You are an AI running locally on Apple Silicon."},
        {"role": "user", "content": "What are three advantages of self-hosting LLMs?"},
    ],
    temperature=0.7,
    stream=True,
)

for chunk in stream:
    if chunk.choices[0].delta.content is not None:
        print(chunk.choices[0].delta.content, end="", flush=True)
print()
```

---

### C. Node.js Client (OpenAI SDK)

```typescript
import OpenAI from "openai";

const openai = new OpenAI({
  baseURL: process.env.SOVEREIGN_BASE_URL,
  apiKey: process.env.SOVEREIGN_API_KEY,
});

async function main() {
  const completion = await openai.chat.completions.create({
    model: "local",
    messages: [
      { role: "system", content: "You are a helpful software engineer." },
      { role: "user", content: "Write a quick bash one-liner to check open ports on macOS." },
    ],
    max_tokens: 100,
  });

  console.log(completion.choices[0].message.content);
}

main().catch(console.error);
```

---

## 5. Limitations & Caveats

1. **Host Availability**: The Mac running Sovereign AI must stay awake, connected to power, connected to the internet, and keep the application active. Sleep mode will disrupt connections.
2. **Ephemeral Quick Tunnel URLs**: Cloudflare Quick Tunnels (`trycloudflare.com`) are temporary. Stopping and restarting the tunnel issues a new randomly generated subdomain. Do not hardcode these URLs into production automation.
3. **Free Tier Throughput**: Quick Tunnels are subject to Cloudflare's public edge fair-use policies and may terminate if idle or running continuously for long periods.
4. **Endpoint Scope**: Sovereign AI implements OpenAI-compatible `/v1/chat/completions` and `/v1/models`. Endpoints such as `/v1/embeddings`, `/v1/fine-tunes`, and audio/vision APIs are not implemented.
5. **Single-Token Serialization**: Inference is queued through `IInferenceCoordinator`. Multiple concurrent requests are safely sequenced in a FIFO queue; rate limits and max-concurrency headers prevent queue flooding.

---

## 6. Troubleshooting

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| **`cloudflared not found`** | Executable missing from system PATH. | Run `brew install cloudflared` or download official binary from Cloudflare releases. Restart Sovereign AI. |
| **Tunnel fails to start** | Local API server is stopped. | Toggle **Start Server** before turning on Remote Access. |
| **HTTP 401 `invalid_api_key`** | Key prefix or secret is wrong. | Check `Authorization: Bearer <key>` header; ensure the key was copied completely upon creation. |
| **HTTP 401 `revoked_api_key`** | Key was revoked in Settings. | Re-issue a new key from the local Sovereign AI Settings screen. |
| **HTTP 429 `rate_limit_exceeded`** | Requests per minute limit exceeded. | Adjust RPM quota on the key in the API Keys settings. |
| **HTTP 503 `no_model_loaded`** | No GGUF model is loaded in memory. | Open Sovereign AI and load a supported `.gguf` model. |
| **Connection Timed Out** | Mac entered sleep or lost internet. | Disable macOS sleep in System Settings under Energy Saver / Battery when hosting remote sessions. |
