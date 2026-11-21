# Implementation Roadmap (`commander_chess_3d`)

This roadmap defines the post-starter implementation phases required to evolve the compilable `commander_chess_3d` scaffold into a complete, production-grade 3D Commander Chess (Cờ Tư Lệnh) product, aligned with `AGENTS.md` specialist ownership.

---

## Phase A — Full Cờ Tư Lệnh Rules & Mechanics
**Primary Owners**: `flutter-model`, `flutter-business-rules`, `flutter-test`

### Deliverables
1. **Complete 11-Piece Movement & Capture Matrix**:
   - `Commander`: Unlimited orthogonal slide, 1-step orthogonal capture, Flying General / Exposed Commander line-of-sight prohibition (including when carried or exiting `Headquarters`), cannot capture `Navy` in deep sea.
   - `Infantry`, `Militia`, `Engineer`: 1-step orthogonal (`I`, `E`) and 8-way (`M`) movement/capture; independent deep-river wading; `Engineer` single heavy-piece (`A`, `G`, `S`) river ferry.
   - `Tank`: 1–2 step orthogonal slide/capture, deep-river wading, `stayCapture` vs deep-sea `Navy` (displaces on coast/estuary).
   - `Artillery`: 1–3 step 8-way movement (blocked), 1–3 step 8-way capture jumping blockers, deep-river crossing restricted to fords `f`/`h`, `Engineer` ferry, or capture across bank.
   - `AntiAircraft` & `Missile`: 1-step orthogonal (`G`) and 1–2 ortho / 1-diag (`S`) movement, heavy-piece river restrictions, `stayCapture` vs deep-sea `Navy`.
   - `Navy`: 1–4 step 8-way movement on `deepSea` (`a,b`), coast (`c`), and estuary (`d6,e6,d7,e7`), blocking on enemy `Navy` only, prohibiting `f`-ford crossing and diagonal land-corner cuts (`c5->d6`, `c8->e7`); 3 weapons (Anti-ship Missile 1–4 displace, Naval Gun 1–3 jumping blockers with coastal displace / inland `stayCapture`, 1-step ortho Shipboard AA).
   - `AirForce`: 1–4 step 8-way flight over all obstacles; cannot stop on empty `deepSea` (lands on land, coast, or friendly `Navy`); optional `stayCapture` bombing return against ground/sea targets vs mandatory displacement on air-to-air captures.
2. **Combined-Arms Stacking (`cõng quân`)**:
   - Max 3 pieces per stack (1 carrier + up to 2 passengers) across `Navy` (`F,T,I,M,C`), `AirForce` (`T,I,M,C`), `Tank` (`I,M,C`), and `Engineer` (`A,G,S` river ferry).
   - Embark, split/disembark (`tách chồng`), same-turn passenger cooldown rules, and full-stack capture/scoring.
3. **Air Defense Zones & `AIR-KAMIKAZE`**:
   - Project dynamic AD zones from `AntiAircraft` (4 ortho), `Missile` (2 ortho + 1 diag), and `Navy` (4 ortho), expanded when Heroic.
   - Shoot down non-stealth `AirForce` passing through AD zones; resolve 1-for-1 `AIR-KAMIKAZE` when deliberately bombing a defended target.
4. **Heroic Promotion (`Quân anh hùng`) & `Headquarters` Policy**:
   - Auto-promote pieces checking the enemy Commander or acting as last defender; apply `+1` range, 45° diagonal unlock, `+10` points, and `AirForce` Stealth (range 5, AD immune).
   - Configurable `RuleVariantConfig` hooks for `Headquarters` shelter/destruction rules (`nguh.org` vs `commanderchess.app` v1.3) and 17-piece/9-piece quick setups.
5. **Victory, Scoring & Full Notation**:
   - Support **Total Power** (Commander checkmate/capture) and **Tactical 4-Battle** (Raid, Naval, Air, Land battles), timeout material scoring (`C`=100, `N`=80, `F`=40, `A`=30, `T/S`=20, `I/M/E/G/H`=10, `+10` Heroic), and draw rules (equal points, mutual agreement, 3-fold repetition, 50-move rule).
   - Full algebraic FEN import/export and move notation parser/serializer.

### Acceptance Checks
- Comprehensive pure-Dart unit test matrix verifying every piece movement, river/ford/estuary edge case, stacking rule, AD interception, Heroic promotion, and FEN round-trip.

---

## Phase B — Blender 3D Assets, Animations & Production PBR Engine
**Primary Owners**: `flutter-3d-performance`, `flutter-backend` (manifest), `flutter-test`

### Deliverables
1. **Blender `.glb` Asset Pack** (following `docs/BLENDER_ASSET_CONTRACT.md`):
   - 11 unique piece `.glb` models (LOD0 + LOD1) with canonical node hierarchy (`base_pedestal`, `body_hull`, `turret`, `barrel`, `socket_passenger_0/1`), 5 named PBR slots, packed ORM textures, and all 7 NLA clips (`idle`, `select`, `move`, `attack`, `capture`, `promote`, `defeat`).
   - Board terrain `.glb` (`board_root`, `terrain_land`, `terrain_sea`, `terrain_river`, `ford_f`, `ford_h`, `grid_overlay`).
2. **Production `flutter_scene` + `flutter_gpu` Renderer**:
   - Enable `flutter_scene` (`hook/build.dart` + Android/iOS/Windows GPU runner flags) behind `GlbPieceAssetProvider` and `FlutterSceneBoardRenderer`.
   - Distance-based LOD0/LOD1 switching, live turret Y-aiming during attacks, passenger sub-mesh mounting onto `socket_passenger_0/1`, and runtime Red/Blue/Heroic material instancing.
3. **Impeller Shaders, VFX & Audio**:
   - Animated water ripples (`terrain_highlight.frag` extension), Air Defense dome/ring visualization, bombing/explosion particle bursts, and spatialized SFX (`move`, `cannon`, `jet`, `ship_horn`, `hero_fanfare`).

### Acceptance Checks
- 60/120fps frame-time budget verified in Flutter DevTools; total visible scene <= 65k tris (LOD0) / <= 25k tris (LOD1); headless widget tests continue passing using an injected mock `BoardSceneRenderer`.

---

## Phase C — Local 2-Player Mode & Match UX
**Primary Owners**: `flutter-state-riverpod`, `flutter-ui`, `flutter-api`

### Deliverables
1. **Pass-and-Play Tabletop Ergonomics**:
   - Smooth automatic or manual camera flip between Red and Blue baselines, plus tactical top-down and side-overview presets.
   - Multi-step interactive UI for carrier embarkation, disembark passenger selection, and Air Force bombing stay-vs-return prompt.
2. **Match Clocks & Hidden Setup Mode**:
   - Dual chess clocks (Fischer increment / sudden death) and optional **1-minute hidden deployment (`Setup`) phase** with curtain/fog-of-war before turn 1.
3. **Match History, Replay & Local Persistence**:
   - Replace `InMemoryGameRepository` with SQLite/Drift local persistence for saved matches, move-by-move PGN-like replay scrubber, and variant rule toggles (`Total Power` vs `4-Battle`, `19-piece` vs `17-piece`).

### Acceptance Checks
- Widget & Riverpod state tests covering full pass-and-play turn cycle, embark/disembark sheet flows, clock expiration scoring, and Drift save/resume round-trips.

---

## Phase D — AI Opponent (`Isolate` Search Engine)
**Primary Owners**: `flutter-business-rules`, `flutter-3d-performance`, `flutter-state-riverpod`

### Deliverables
1. **Zero-Copy `Isolate` Worker (`AiOpponentEngine`)**:
   - Run search inside a long-lived background `Isolate` communicating packed board states via `TransferableTypedData` so the 60/120Hz 3D loop never drops a frame.
2. **Search & Tactical Evaluation**:
   - Alpha-Beta / Principal Variation Search (PVS) with Zobrist transposition tables, iterative deepening, quiescent capture search, and Monte Carlo Tree Search (MCTS) option for deep tactical lines.
   - Domain-specific evaluation function scoring material, Heroic stealth value, Air Defense coverage overlap, river-ford control, carrier stack risk, and Commander safety.
3. **Difficulty Tiers & Hint Mode**:
   - Casual (depth 2 + noise), Tactical (depth 4), and Commander (iterative deepening time-budgeted), plus on-demand player move hints.

### Acceptance Checks
- Benchmark test verifying zero UI frame drops during AI think time, deterministic legal move output across 50+ positions, and time-budget compliance.

---

## Phase E — Online Multiplayer & Competitive Backend
**Primary Owners**: `flutter-backend`, `flutter-api`, `flutter-state-riverpod`, `flutter-test`

### Deliverables
1. **Authoritative Game Server (`openapi/commander_chess_v1.yaml`)**:
   - Implement Dart (Dart Frog / Shelf) or Go/Node backend sharing the exact pure-Dart `CommanderRulesEngine` (if Dart server) for anti-cheat server-side move validation, hidden-setup fog enforcement, and authoritative match clocks.
2. **Real-Time WebSocket Sync & Resiliency**:
   - Concrete `WebSocketMultiplayerTransport` replacing `StubMultiplayerTransport`, supporting sequence-numbered `MatchSyncEventDto`, exponential backoff reconnects, and full snapshot resynchronization.
3. **Auth, Matchmaking & Spectator/Replay Sharing**:
   - JWT authentication, ELO/Glicko-2 matchmaking queues (`Total Power` & `4-Battle`), friend room invite codes, live spectator streams, and shareable match replay links.

### Acceptance Checks
- OpenAPI/WebSocket contract tests verifying request/event schema parity, reconnect state recovery, and server rejection of illegal moves.
