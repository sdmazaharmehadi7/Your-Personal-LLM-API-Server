# Architecture & Reference: Personal Local LLM API Server

**Document Version:** 1.5  
**Target Project:** `local_ai_flutter_api` (`sovereign_ai`)  
**Status:** Implemented & Verified (Prompt 9 — LAN External Connections & Secure Network Modes)

---

## 1. Overview & Trust Boundaries

The application provides an OpenAI-compatible HTTP server integrated into the Sovereign AI desktop application that can be securely accessed locally, across the local area network (LAN), or remotely across the internet.

### 1.1 Architecture & Connection Modes

```text
[Local Machine] ──────> 127.0.0.1:8080 (Local-only mode)
                             │
[LAN Devices]   ──────> 192.168.x.x:8080 (Allow External Connections / 0.0.0.0)
                             │
[Remote Internet] ────> HTTPS Tunnel (trycloudflare.com)
                             │
                             ▼
                     LocalApiServer
                             │
                             ▼
                   ApiKeyService (Auth)
          (HMAC-SHA256, Constant-Time Verify,
           Rate Limits, Max Concurrency)
                             │
                             ▼
                  IInferenceCoordinator
               (Mutex / FIFO Queue / Metal)
                             │
                             ▼
                  Loaded GGUF Model in RAM
```

### 1.2 Core Trust & Security Rules
- **Mode 1: Local-Only (Default):** `LocalApiServer` listens strictly on loopback `127.0.0.1`. Network connections from other LAN devices are refused by the kernel socket.
- **Mode 2: Local Network (LAN Mode):** When "Allow External Connections" is explicitly enabled, the server binds to `0.0.0.0` and resolves the Mac's real LAN IPv4 address (e.g., `192.168.1.10`). Clients on the same Wi-Fi/Ethernet can connect. **API-key authentication is mandatory; no authentication bypass exists for LAN requests.**
- **Mode 3: Remote Internet Tunnel:** For external access from outside the local network, the Cloudflare Quick Tunnel creates an outbound encrypted tunnel to `127.0.0.1`.
- **Single Runtime:** No duplicate models or secondary inference runtimes are created. Both the UI chat, LAN requests, and remote tunnel requests serialize through the single authoritative [IInferenceCoordinator](file:///Users/sayyadmazaharmehadi/local_llm_server/local_ai_flutter_api/lib/services/inference_coordinator.dart).
- **Mandatory Authentication Across All Modes:** All requests to protected endpoints (`/v1/chat/completions`, `/v1/models`) require valid HTTP `Authorization: Bearer <API_KEY>` headers.
- **Local Administration Only:** Key creation, revocation, and server controls exist solely in the local macOS Flutter UI. There is no remote administration or self-registration endpoint.

---

## 2. Remote Access Provider (`cloudflared`)

### 2.1 Provider Selection & Why
- **Cloudflare Quick Tunnels (`cloudflared`)**:
  - Open-source, maintained by Cloudflare.
  - Zero-account, zero-cost, temporary HTTPS endpoint (`https://<unique-id>.trycloudflare.com`).
  - No domain purchase, credit card, or public router port forwarding needed.
  - Standard macOS installation via Homebrew.

### 2.2 Installation & Prerequisites
Before starting remote access, ensure `cloudflared` is installed on macOS:
```bash
brew install cloudflared
```
The application checks for `cloudflared` in:
- `/opt/homebrew/bin/cloudflared` (Apple Silicon Mac)
- `/usr/local/bin/cloudflared` (Intel Mac)
- System `$PATH`

If the binary is missing, the UI warns the user and provides the exact Homebrew installation command.

---

## 3. Remote Access Lifecycle

1. **Disabled by Default:** Remote access is always disabled when the application launches.
2. **Strict Prerequisite:** The local API server must be running before remote access can be started. If the local server is stopped, starting remote access is prevented.
3. **Synchronized Teardown:**
   - Stopping remote access immediately terminates the tunnel child process and revokes the public HTTPS URL.
   - Stopping the local API server automatically stops remote access.
   - Quitting or disposing the application terminates the tunnel child process.
4. **Model Safety:** Starting or stopping remote access **never** unloads the model weights from memory, clears chat history, or modifies API key records.

---

## 4. Developer Quickstart Guide

### Step 1: Start the Local API Server
In **Settings** -> **Personal LLM API Server (OpenAI-Compatible)**:
- Click **Start API Server**.

### Step 2: Generate an API Key for the Developer
In **Settings** -> **API Keys & Access Control**:
- Click **Create Key**.
- Enter a description (e.g., `Remote Dev - Alice`).
- Choose an expiration duration and click **Generate Key**.
- Copy the secret key (`sk-sov-...`) and securely send it to the developer.

### Step 3: Enable Remote Access
In **Settings** -> **Secure Remote Access (Public HTTPS Tunnel)**:
- Click **Start Remote Access**.
- Wait 2–5 seconds while the encrypted tunnel is established.
- Copy the assigned public HTTPS base URL (e.g., `https://random-words-1234.trycloudflare.com`).

---

## 5. Client Integration Examples

### 5.1 Environment Variable Setup (Client Machine)
```bash
export OPENAI_BASE_URL="https://your-tunnel-id.trycloudflare.com/v1"
export OPENAI_API_KEY="sk-sov-YOUR_ASSIGNED_KEY_HERE"
```

### 5.2 `curl` Request
```bash
curl -X POST "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-0.5b-instruct-q4_k_m.gguf",
    "messages": [
      {"role": "system", "content": "You are a concise local AI assistant."},
      {"role": "user", "content": "What is the capital of Japan?"}
    ],
    "temperature": 0.7,
    "max_tokens": 128,
    "stream": false
  }'
```

### 5.3 Python with Official OpenAI SDK
```python
import os
from openai import OpenAI

# The client communicates with your MacBook over the secure Cloudflare tunnel
client = OpenAI(
    base_url=os.getenv("OPENAI_BASE_URL"),
    api_key=os.getenv("OPENAI_API_KEY"),
)

response = client.chat.completions.create(
    model="qwen2.5-0.5b-instruct-q4_k_m.gguf",
    messages=[
        {"role": "system", "content": "You are a helpful coding assistant."},
        {"role": "user", "content": "Explain async/await in Python in two sentences."},
    ],
    temperature=0.7,
    max_tokens=100,
)

print(response.choices[0].message.content)
```

### 5.4 Node.js with Official OpenAI SDK
```javascript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: process.env.OPENAI_BASE_URL,
  apiKey: process.env.OPENAI_API_KEY,
});

async function main() {
  const completion = await client.chat.completions.create({
    model: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
    messages: [
      { role: "user", content: "Write a 3-line poem about sovereignty." },
    ],
    temperature=0.7,
  });

  console.log(completion.choices[0].message.content);
}

main();
```

### 5.5 Open WebUI / Desktop Client Configuration
In Open WebUI or Continue.dev settings:
- **Base URL:** `https://your-tunnel-id.trycloudflare.com/v1`
- **API Key:** `sk-sov-YOUR_ASSIGNED_KEY_HERE`

---

## 6. Resource, Hardware & Reliability Notice

Because your Mac serves as the inference host:
1. **Sleep & Power:** The Mac must remain awake and connected to the internet. If the Mac sleeps, closes lid, or loses internet connectivity, the tunnel drops.
2. **Hardware Load:** Token generation executes locally on Apple Silicon Metal / CPU. Concurrent remote requests will consume Mac GPU memory, CPU cores, and battery.
3. **Queue Serialization:** Requests are processed sequentially through `IInferenceCoordinator`. If multiple developers query simultaneously, requests are queued up to the configured queue depth (excess requests receive HTTP `429 Too Many Requests`).
4. **Temporary URLs:** Free `trycloudflare.com` URLs are ephemeral; stopping and restarting remote access generates a new HTTPS endpoint.

---

## 7. Immediate Rollback & Emergency Stop

To instantly sever all external public access:
1. Navigate to **Settings** -> **Local API Server**.
2. Toggle off **Allow External Connections** (or click Stop Remote Access).
   - The public HTTPS endpoint is destroyed immediately.
   - Any active remote client streams or incoming requests are terminated.
   - Local API and local UI chat continue running unaffected.

---

## 8. Sample Endpoints & In-App API Testing (UI Enhancement)

Accessible directly from **Settings** -> **Local API Server** -> **Sample Endpoints & Testing**:
- **Reference-Accurate Design:** Dark theme card hierarchy matching the API server specification with rounded containers, status pill badges, and copy utilities.
- **Server Status Card:** Live status banner (Running/Stopped) displaying active base URL.
- **Live GET /v1/models Testing:** Sends real HTTP requests to the running local server, formats the JSON list response, and records round-trip latency.
- **Live POST /v1/chat/completions Testing:** Executes real inference prompts against the loaded GGUF model via the shared inference coordinator, displaying HTTP status, assistant output, and response payload.
- **Security & Key Integration:** Protected requests automatically use ephemeral test credentials from `ApiKeyService` without ever displaying secrets in plaintext URLs or hardcoded code.
- **Model State Awareness:** Chat completion testing is disabled with honest guidance when no model is currently loaded in RAM.
