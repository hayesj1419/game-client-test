# Client Overview

## 1. Purpose

The client is responsible for input capture, rendering, and smoothing.

It does not own authoritative game state.

---

## 2. Responsibilities

- Capture player input
- Send input intent to the server
- Receive authoritative snapshots
- Buffer snapshots
- Interpolate between snapshots
- Render the result

---

## 3. Non-Responsibilities

- Determining player position
- Resolving collisions
- Validating movement
- Owning game rules

---

## 4. Architecture Model

The client is a visualizer of server truth.

All gameplay authority lives on the server.
