# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Project

This is a **Godot 4.5** project. There is no build step — open the project in the Godot editor and press **F5** (or the Play button) to run. There are no tests or linting tools configured.

The game requires a WebSocket server running at `ws://localhost:5177/ws` (configurable via the `server_url` @export on the `NetworkClient` node).

## Architecture

This is a **server-authoritative multiplayer game client** demonstrating client-side prediction and snapshot reconciliation. The server is the sole source of truth; the client predicts ahead and corrects using acknowledged sequence numbers.

### Core Components

**`NetworkClient.gd`** — Autoload singleton (globally accessible as `NetworkClient`). This is the heart of the system:
- Manages the WebSocket connection and JSON message parsing
- Buffers up to 20 authoritative server snapshots for interpolation of remote players
- Implements **seq-based client-side prediction**: every input sent gets an incrementing `seq` number and is stored in `_input_buffer` with a `tick_sent` timestamp
- Implements **reconciliation**: each frame, re-simulates `predicted_position` from `server_position` using unacked buffer entries; when the buffer is empty (all inputs acked), predicts ahead using `last_sent_input` for `in_flight` ticks since the last snapshot
- `_prediction_tick` is a monotonic counter incrementing at 20 Hz; `_ack_received_tick` resets on every snapshot to keep `in_flight` bounded to ~1 tick
- Sends input to the server only when it changes

**`main.gd`** / `main.tscn` — Root scene. Each frame reads `get_interpolated_position()` for the local player (returns `predicted_position`) and positions the sprite. Also updates `DebugHUD`.

**`player.gd`** — Attached to the player `Node2D`. Captures WASD/arrow key input. `predicted_offset` is currently zeroed out — `NetworkClient` handles all positional prediction.

**`DebugHud.gd`** / `DebugHUD.tscn` — `CanvasLayer` overlay showing connection state, player ID, snapshot age/count, entity positions, and correction distance. Instantiated by `main.gd` at startup.

### Message Protocol

**Server → Client:**
```json
// On connect
{ "type": "welcome", "playerId": "<uuid>" }

// Each tick (~20 Hz) — all keys camelCase
{ "type": "snapshot", "tick": 42, "players": [{ "id": "<uuid>", "x": 5.0, "y": 3.0, "ackedSeq": 24 }] }
```

**Client → Server:**
```json
{ "type": "input", "seq": 42, "x": 1, "y": 0 }
```

### Key Constants / Variables (in `NetworkClient.gd`)

| Name | Value | Purpose |
|---|---|---|
| `MAX_SNAPSHOTS` | 20 | Snapshot buffer cap |
| `INTERPOLATION_DELAY_TICKS` | 4 | Render behind latest snapshot for remote player interpolation |
| `speed_per_tick` | 0.1 | Must match server movement speed exactly |
| `server_url` | `ws://localhost:5177/ws` | WebSocket endpoint (@export, editable in editor) |
| `_next_seq` | increments per send | Sequence number assigned to each outgoing input |
| `_input_buffer` | `[{seq, input, tick_sent}]` | Unacked inputs pending re-simulation |
| `_last_acked_seq` | from snapshot `ackedSeq` | Highest seq the server has confirmed |
| `_ack_received_tick` | resets every snapshot | Used to compute bounded `in_flight` prediction ticks |

### Known Issues / Next Steps

- `get_interpolated_position()` has a bug: `var local_id = player_id` followed by `if player_id == local_id` is always true, so it always returns `predicted_position` regardless of which player is requested. Remote players are not yet rendered — fixing this is a prerequisite.
- Remote player spawning/despawning is not implemented. The snapshot data for all players is received and buffered but only the local player is rendered.
- Server movement speed (`speed_per_tick = 0.1` at 20 Hz = 2 world units/sec) is intentionally slow for testing.
