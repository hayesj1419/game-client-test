# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Project

This is a **Godot 4.5** project. There is no build step — open the project in the Godot editor and press **F5** (or the Play button) to run. There are no tests or linting tools configured.

The game requires a WebSocket server running at `ws://localhost:5177/ws` (configurable via the `server_url` @export on the `NetworkClient` node).

## Architecture

This is a **server-authoritative multiplayer game client** demonstrating client-side prediction and snapshot interpolation. The server is the sole source of truth; the client is a visualizer that smooths between server snapshots.

### Core Components

**`NetworkClient.gd`** — Autoload singleton (globally accessible as `NetworkClient`). This is the heart of the system:
- Manages the WebSocket connection and JSON message parsing
- Buffers up to 20 authoritative server snapshots; renders at `INTERPOLATION_DELAY_TICKS` (4 ticks) behind the latest to enable smooth playback
- Applies **client-side prediction**: locally simulates player movement each tick so input feels instant
- Applies **reconciliation**: each frame, lerps the predicted position toward the server-authoritative position using `reconciliation_alpha` (0.15)
- Sends input to the server only when it changes

**`main.gd`** / `main.tscn` — Root scene. Reads the interpolated + predicted position from `NetworkClient` each frame and moves the player sprite. Also updates the `DebugHUD`.

**`player.gd`** — Attached to the player `Node2D`. Captures WASD/arrow key input and stores a `predicted_offset` (visual-only smoothing at SPEED 1000 px/s) that `main.gd` layers on top of the server-reconciled position.

**`DebugHud.gd`** / `DebugHUD.tscn` — `CanvasLayer` overlay showing connection state, player ID, snapshot age/count, entity positions, and correction distance. Instantiated by `main.gd` at startup.

### Message Protocol

**Server → Client:**
```json
// On connect
{ "type": "welcome", "playerId": "<uuid>" }

// Each tick (~20 Hz)
{ "tick": 42, "players": [{ "Id": "<uuid>", "X": 100.0, "Y": 200.0 }], "received_at_ms": 1234567890 }
```

**Client → Server:**
```json
{ "type": "input", "x": 1, "y": 0 }
```

### Key Constants (in `NetworkClient.gd`)

| Constant | Value | Purpose |
|---|---|---|
| `TICK_RATE` | 20 | Server ticks per second |
| `INTERPOLATION_DELAY_TICKS` | 4 | Render behind latest snapshot (~200 ms) |
| `reconciliation_alpha` | 0.15 | Lerp factor for error correction per frame |
| `server_url` | `ws://localhost:5177/ws` | WebSocket endpoint (@export, editable in editor) |
