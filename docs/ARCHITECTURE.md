# Architecture & Core Interface Contracts (`commander_chess_3d`)

This document defines the production-grade architecture for **Commander Chess 3D (Cờ Tư Lệnh)** across module boundaries, two-speed 3D/state separation, Cờ Tư Lệnh domain representation, target platforms, 3D rendering stack decisions, and exact Dart contracts.

---

## 1. Architectural Goals

1. **Strict Layer Separation**: Keep Cờ Tư Lệnh rules and board topology 100% pure Dart so the exact same rules engine runs in the Flutter client, a background AI search `Isolate`, and an authoritative online multiplayer server.
2. **Two-Speed 60/120Hz Decoupling**: Keep continuous camera orbit physics, piece translation tweens, and 3D projection buffers inside `engine/` (`Ticker` + `ChangeNotifier` + `RepaintBoundary`), while Riverpod `state/` holds only discrete HUD snapshots (`GameHudSnapshot`).
3. **Zero-Rewrite Blender `.glb` Swappability**: Isolate 3D geometry, materials, animations, and shader pipelines behind `AssetManifest`, `PieceAssetProvider`, and `BoardSceneRenderer` so future Blender `.glb` models drop into `engine/` without modifying `models/`, `rules/`, `repositories/`, or `state/`.
4. **Deterministic Cross-Platform Baseline**: Compile cleanly with zero analyzer warnings on Flutter 3.50.1 (`material_ui`), execute headless widget/render tests in `flutter test`, and run live on Web/Mobile/Desktop.

---

## 2. Six-Layer + Two-Speed Squad Architecture

| Layer | Directory | Squad Owner | Responsibilities |
| --- | --- | --- | --- |
| **Core** | `lib/core/` | `flutter-model` | `Result<T>` (`Ok`/`Err`), sealed `AppFailure` hierarchy, `Clock` abstraction. |
| **Models** | `lib/features/game/models/` | `flutter-model` | Immutable entities (`BoardCoord`, `PieceEntity`, `GameMove`, `GameSessionState`), Blender `AssetManifest` models, multiplayer DTOs, defensive JSON. |
| **Rules** | `lib/features/game/rules/` | `flutter-business-rules` | 11×12 `BoardTopology`, `CommanderRulesEngine`, initial FEN setup, move/capture/stacking validation, `StartMatchUseCase`, `SubmitMoveUseCase`. |
| **Repositories** | `lib/features/game/repositories/` | `flutter-api` | `GameRepository`, `MultiplayerTransport`, `AssetManifestLoader`, `AiOpponentEngine` contracts + starter implementations (`InMemoryGameRepository`, `StubMultiplayerTransport`, `BundledAssetManifestLoader`). |
| **State (Cold)** | `lib/features/game/state/` | `flutter-state-riverpod` | Manual Riverpod 3.x (`Notifier` / `NotifierProvider`, zero codegen) owning `GameHudSnapshot` with `ref.mounted` and `ref.onDispose` safety. |
| **Engine (Hot)** | `lib/features/game/engine/` | `flutter-3d-performance` | `FixedTimestepDriver` (`Ticker` + `AppLifecycleListener`), `SpringOrbitCamera3D`, `BoardCoordinateMapper`, `PieceAssetProvider`, `BoardSceneRenderer`, `BoardShaderHandle`, `Board3DSceneController`. |
| **Presentation** | `lib/features/game/presentation/`, `lib/app.dart`, `lib/main.dart` | `flutter-ui` | `package:material_ui/material_ui.dart` Light/Dark `ThemeData`, `RepaintBoundary`-isolated `Board3DViewport`, responsive `GameHudOverlay`, `CommanderGameScreen`. |

### Dependency Direction Matrix

| Layer ↓ \ May Import → | Dart stdlib | `core/` | `models/` | `rules/` | `repositories/` | `flutter_riverpod` | `vector_math` | `flutter/*` / `material_ui` | `engine/` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `core/` | Yes | — | **No** | **No** | **No** | **No** | **No** | **No** | **No** |
| `models/` | Yes | Yes | — | **No** | **No** | **No** | **No** | **No** | **No** |
| `rules/` | Yes | Yes | Yes | — | Abstract interface only (`usecases/` -> `GameRepository`) | **No** | **No** | **No** | **No** |
| `repositories/` | Yes | Yes | Yes | **No** | — | **No** | **No** | `services.dart` only in asset bundle loader | **No** |
| `state/` | Yes | Yes | Yes | Yes | Yes | Yes | **No** | **No** | **No** |
| `engine/` | Yes | Yes | Yes | **No** | **No** | **No** | Yes | `widgets`/`painting`/`scheduler`/`ui` | — |
| `presentation/` | Yes | Yes | Yes | **No** | **No** | Yes (`ConsumerWidget` / `ConsumerStatefulWidget`, reads `state/`) | `Vector3` only (`Board3DViewport`) | Yes (`material_ui`, `gestures.dart`) | Yes (controller & viewport) |

> **Critical Invariants**:
> - Zero `package:flutter/*`, `package:material_ui/*`, or `package:flutter_riverpod/*` imports inside `core/`, `models/`, or `rules/`.
> - Zero `package:flutter/material.dart` imports anywhere (deprecated in Flutter 3.50.1; always use `package:material_ui/material_ui.dart`).
> - `engine/` never mutates Riverpod providers during `Ticker` frames; discrete user picks/actions flow back via callbacks (`onCoordTapped`) into `GameSessionNotifier`.

### Two-Speed Execution Flow

```text
  [Hot Path: 60–120 Hz]                         [Cold Path: Discrete Turns]
  Ticker -> FixedTimestepDriver (dt <= 0.05)     User Tap -> Ray-Plane Pick (BoardCoord)
         -> SpringOrbitCamera3D.step(dt)                  -> GameSessionNotifier.selectCoord / attemptMoveTo
         -> PieceTweenState.step(dt)                      -> SubmitMoveUseCase -> CommanderRulesEngine
         -> Board3DSceneController.notifyListeners()      -> GameHudSnapshot (immutable state update)
         -> CustomPainter.paint() inside RepaintBoundary  -> Board3DViewport syncs RenderBoardSnapshot
```

Because `Board3DViewport` wraps the 3D `CustomPaint` in a dedicated `RepaintBoundary` and passes `Board3DSceneController` directly to `CustomPainter(repaint: controller)`, camera orbiting and piece animations trigger **zero widget rebuilds** in the Material HUD.

---

## 3. Target Platform Matrix & 3D Rendering Stack Decision

### Target Platforms

| Platform | Starter Scaffold Status | Production Target (Phase B+) | Notes |
| --- | --- | --- | --- |
| **Web (Chrome/Edge)** | Active & verified (`flutter run -d chrome`, `flutter build web`) | Starter `CustomPainter` fallback or `flutter_scene` WebGL2 | Zero COOP/COEP headers required |
| **Android (SDK 36)** | Active (`flutter build apk`) | Impeller + `flutter_gpu` (`flutter_scene`) | Opt-in `io.flutter.embedding.android.EnableFlutterGPU` in Phase B |
| **iOS** | Runner generated | Impeller + `flutter_gpu` (`flutter_scene`) | Opt-in `FLTEnableFlutterGPU` in `Info.plist` in Phase B |
| **macOS / Linux** | Runners generated | Impeller + `flutter_gpu` (`flutter_scene`) | Desktop builds require native platform SDKs |
| **Windows** | Runner generated | Impeller + `flutter_gpu` (`flutter_scene`) | Requires Visual Studio "Desktop development with C++" for native compilation |
| **Headless `flutter test`** | Active & verified (`flutter_tester.exe`) | Mock/placeholder `BoardSceneRenderer` injected via DI | Avoids hardware GPU swapchain dependency in unit/widget tests |

### Why `CustomPainter` + `vector_math_64` + Optional `ui.FragmentProgram` for the Starter?

1. **Headless Testability**: Both `flutter_scene` (`flutter_gpu`) and `thermion_flutter` (Filament C++ FFI) require an active hardware GPU context / Flutter GPU runner flag and throw inside headless `flutter_tester.exe` unless mocked. `CustomPainter` + `vector_math_64` renders deterministically in `WidgetTester` with zero native FFI.
2. **Perspective 3D Depth & Silhouette Clarity**: Using `Matrix4` view-projection matrices (`vector_math_64`), backface culling, painter's depth sorting, extruded 3D piece primitives (pedestals, hulls, turrets, barrels, wings, command stars), and 3D ray-plane intersection picking provides a genuine interactive 3D viewport today.
3. **Impeller Shader Hook**: `assets/shaders/terrain_highlight.frag` (`#version 460 core`) integrates through `BoardShaderHandle` using `ui.FragmentProgram.fromAsset(...)` with a graceful `null` fallback in headless tests or software backends.
4. **Production Upgrade Path (Phase B)**: **`flutter_scene` + `flutter_gpu` + `vector_math`** (Impeller-native `.glb` PBR/skeletal animations on Flutter `>=3.47.0` stable, plus WebGL2 fallback) is the primary Phase B backend, with **`thermion_flutter`** (Google Filament PBR) as an optional alternative if advanced `.ktx` IBL lighting is needed. Swapping requires implementing `GlbPieceAssetProvider` and `FlutterSceneBoardRenderer` behind the contracts below — **zero** changes to `models/`, `rules/`, `repositories/`, or `state/`.

---

## 4. Cờ Tư Lệnh Domain Summary

The domain models and topology encode Colonel Nguyễn Quý Hải's standard Cờ Tư Lệnh board and unit taxonomy:

- **Intersection Grid**: **11 vertical files** (`0..10`, algebraic `a`–`k`) × **12 horizontal ranks** (`0..11`, algebraic `1`–`12`) = **132 playable intersections**. Pieces stand on intersections, not inside squares.
- **Terrain Zones (`TerrainType`)**:
  - `deepSea`: Files `a` (`0`) and `b` (`1`), ranks `1..12`. Accessible by `Navy` and airborne `AirForce` (Air Force cannot land on empty sea, only on friendly `Navy`).
  - `mixed` (Coast & Estuary): File `c` (`2`, ranks `1..12`) plus the 4 **Estuary (*Cửa sông*)** vertices `d6, e6, d7, e7`. Accessible by both naval and land forces; `Navy` cannot cut land corners diagonally (`c5 -> d6` or `c8 -> e7`) and must enter the estuary via `c6` or `c7`.
  - `land`: Files `d..k` (`3..10`), excluding the estuary dual-use classification.
  - **River (*Sông*) & Fords (*Ngầm*)**: Horizontal divider between rank `6` (`0`-based `5`) and rank `7` (`0`-based `6`), with **2 shallow fords** at **`f6–f7`** (`file 5`) and **`h6–h7`** (`file 7`). Heavy pieces (`Artillery`, `AntiAircraft`, `Missile`) cannot cross the deep river unassisted (must use fords `f`/`h`, `Engineer` ferry, or capture across the bank).
- **11 Piece Types (19 pieces/side = 38 total)**:
  `commander` (1, 100 pts), `headquarters` (2, 10 pts), `infantry` (2, 10 pts), `militia` (1, 10 pts), `engineer` (2, 10 pts), `tank` (2, 20 pts), `artillery` (2, 30 pts), `missile` (1, 20 pts), `navy` (2, 80 pts), `airForce` (2, 40 pts), `antiAircraft` (2, 10 pts).
- **Verified Initial FEN**:
  `6c4/1n2fh1hf2/3a2s2a1/2n1gt1tg2/2ie2m2ei/11/11/2IE2M2EI/2N1GT1TG2/3A2S2A1/1N2FH1HF2/6C4 r - - 0 1`
- **Starter vs. Phase A Rules Scope**: The starter `CommanderRulesEngine` implements the 11×12 topology, terrain & estuary corner-cut admissibility, 38-piece FEN setup, `Headquarters` immobility, Commander Line-of-Sight prohibition (*Flying General*), turn order, baseline movement/captures, and Commander capture victory, while locking all multi-mode actions (`ActionKind`), `carriedPieces` stacking, `isHero`, and `RuleVariantConfig` hooks into the interfaces for Phase A expansion.

---

## 5. Exact Dart Interfaces & Contracts

### 5.1 Core (`lib/core/result/`, `lib/core/time/`)

- `Result<T>` (`Ok<T>`, `Err<T>`) with `.when(ok: ..., err: ...)`.
- `AppFailure` sealed hierarchy: `NetworkAppFailure`, `ValidationAppFailure`, `AuthAppFailure`, `ServerAppFailure`, `RulesViolationFailure`.
- `Clock` interface (`SystemClock`, deterministic test clock) for UTC timestamps.

### 5.2 Domain Models (`lib/features/game/models/`)

```dart
enum TerrainType { deepSea, mixed, land }

final class BoardCoord extends Equatable {
  const BoardCoord({required this.file, required this.rank});
  static const int fileCount = 11;
  static const int rankCount = 12;
  final int file; // 0..10 (a..k)
  final int rank; // 0..11 (1..12, Red bottom 0..5, Blue top 6..11)
  bool get isValid;
  String toAlgebraic(); // e.g. 'g1'
  factory BoardCoord.fromAlgebraic(String notation);
  factory BoardCoord.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

enum PlayerSide { red, blue }

enum PieceType {
  commander, headquarters, infantry, militia, engineer,
  tank, artillery, antiAircraft, missile, airForce, navy,
}

final class PieceEntity extends Equatable {
  const PieceEntity({
    required this.id,
    required this.side,
    required this.type,
    required this.position,
    this.isHero = false,
    this.carriedPieces = const <PieceEntity>[],
    this.isAlive = true,
  });
  final String id;
  final PlayerSide side;
  final PieceType type;
  final BoardCoord position;
  final bool isHero;
  final List<PieceEntity> carriedPieces; // Max 2 passengers (stack max 3)
  final bool isAlive;
}

enum ActionKind { move, capture, stayCapture, embark, disembark }

final class GameMove extends Equatable {
  const GameMove({
    required this.side,
    required this.pieceId,
    required this.from,
    required this.to,
    required this.kind,
    this.targetPieceId,
    this.carriedPieceId,
    required this.timestampUtc,
  });
  // ...
}

final class GameSessionState extends Equatable {
  const GameSessionState({
    required this.matchId,
    required this.mode,
    this.boardRanks = BoardCoord.rankCount,
    this.boardFiles = BoardCoord.fileCount,
    required this.pieces,
    required this.currentTurn,
    required this.phase,
    this.winner,
    this.victoryReason,
    this.moveHistory = const <GameMove>[],
    this.turnNumber = 1,
    this.variantConfig = const RuleVariantConfig(),
  });
  // ...
}
```

### 5.3 Pure-Dart Rules & Use-Cases (`lib/features/game/rules/`)

```dart
abstract interface class BoardTopology {
  int get ranks;
  int get files;

  bool isValidCoord(BoardCoord coord);
  TerrainType terrainAt(BoardCoord coord);
  bool isEstuary(BoardCoord coord);
  bool isRiverCrossing(BoardCoord from, BoardCoord to);
  bool isFordCrossing(BoardCoord from, BoardCoord to);
  bool isPassableFor(PieceType type, BoardCoord coord);
  bool canCrossStep(PieceType type, BoardCoord from, BoardCoord to);
  List<BoardTileSpec> buildAllTiles();
  List<PieceEntity> createInitialPieces();
}

abstract interface class CommanderRulesEngine {
  GameSessionState createInitialSession({
    required String matchId,
    GameMode mode = GameMode.localPassAndPlay,
    RuleVariantConfig? variantConfig,
  });

  List<LegalActionHint> legalActionsFor({
    required GameSessionState state,
    required BoardCoord from,
  });

  MoveValidationResult validateMove({
    required GameSessionState state,
    required GameMove move,
  });

  Result<GameSessionState> applyMove({
    required GameSessionState state,
    required GameMove move,
  });

  ({MatchPhase phase, PlayerSide? winner, VictoryReason? reason})
      evaluateMatchOutcome(GameSessionState state);
}
```

Orchestrated by `StartMatchUseCase` and `SubmitMoveUseCase` combining `BoardTopology`, `CommanderRulesEngine`, and `GameRepository`.

### 5.4 Repositories, Transport & AI Contracts (`lib/features/game/repositories/`)

```dart
abstract interface class GameRepository {
  Future<Result<GameSessionState>> createMatch({
    required String matchId,
    required GameSessionState initialState,
  });
  Future<Result<GameSessionState>> loadMatch(String matchId);
  Future<Result<GameSessionState>> saveSnapshot(GameSessionState state);
  Future<Result<GameSessionState>> undoLastMove(String matchId);
  Stream<GameSessionState> watchMatch(String matchId);
  void dispose();
}

abstract interface class MultiplayerTransport {
  Future<Result<void>> connect({
    required String matchId,
    required String authToken,
  });
  Future<Result<void>> submitMove(MoveSubmissionDto dto);
  Stream<MatchSyncEventDto> get events;
  Future<void> disconnect();
  void dispose();
}

abstract interface class AssetManifestLoader {
  Future<Result<AssetManifest>> loadManifest();
}

enum AiDifficulty { casual, tactical, master }

abstract interface class AiOpponentEngine {
  Future<Result<GameMove?>> selectBestMove({
    required GameSessionState state,
    required PlayerSide aiSide,
    AiDifficulty difficulty = AiDifficulty.tactical,
    Duration timeBudget = const Duration(milliseconds: 800),
  });
  void dispose();
}
```

### 5.5 Riverpod 3.x HUD State (`lib/features/game/state/`)

```dart
enum OrbitCameraPreset { redCommander, blueCommander, tacticalTop, sideOverview }

final class GameHudSnapshot extends Equatable {
  // Immutable discrete state: session, selectedCoord, legalHints,
  // cameraPreset, isBusy, statusMessage, errorMessage, canUndo
}

final class GameSessionNotifier extends Notifier<GameHudSnapshot> {
  @override
  GameHudSnapshot build();
  Future<void> startNewMatch({GameMode mode = GameMode.localPassAndPlay});
  void selectCoord(BoardCoord coord);
  Future<void> attemptMoveTo(BoardCoord target);
  Future<void> undoLastMove();
  void setCameraPreset(OrbitCameraPreset preset);
  void clearError();
}
```

### 5.6 Blender Asset Manifest & 3D Rendering Contracts (`lib/features/game/models/asset_manifest_model.dart`, `lib/features/game/engine/`)

```dart
enum PieceAnimClip { idle, select, move, attack, capture, promote, defeat }

final class AssetManifest extends Equatable {
  final int schemaVersion;
  final double unitScaleMeters;
  final String boardGlbPath;
  final String boardRootNodeName;
  final List<MeshAssetDescriptor> pieces;
  MeshAssetDescriptor? findPiece(PieceVisualKey key);
}

final class MeshAssetDescriptor extends Equatable {
  final String assetId;
  final PieceVisualKey visualKey;
  final String glbPath;
  final String rootNodeName;
  final List<MeshLodSpec> lodTiers;
  final double boundingRadius;
  final List<String> passengerSockets;
  final List<MaterialSlotBinding> materialSlots;
  final Map<PieceAnimClip, String> animations;
  String get effectiveRootNodeName;
}

final class RenderPieceNode {
  final String pieceId;
  final PieceVisualKey visualKey;
  final Vector3 worldPosition;
  final double yawRadians;
  final int stackCount;
  final List<PieceVisualKey> carriedVisualKeys;
  final bool isSelected;
  final PieceAnimClip animClip;
}

abstract interface class PieceAssetProvider {
  Future<void> preloadAll(AssetManifest manifest);
  PieceVisualHandle resolvePiece(PieceVisualKey key);
  void dispose();
}

abstract interface class BoardSceneRenderer {
  Future<void> initialize();
  void render(
    Canvas canvas,
    Size size,
    RenderBoardSnapshot snapshot,
    SpringOrbitCamera3D camera,
  );
  BoardCoord? hitTestBoardCoord({
    required Offset localPosition,
    required Size viewportSize,
    required SpringOrbitCamera3D camera,
    required int files,
    required int ranks,
  });
  void dispose();
}
```

See [BLENDER_ASSET_CONTRACT.md](BLENDER_ASSET_CONTRACT.md) for the exact Blender modeling, `.glb` export, material slot, and runtime swap specification.
