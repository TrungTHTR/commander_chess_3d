# Commander Chess 3D (Cờ Tư Lệnh)

A production-grade Flutter 3D **Commander Chess (Cờ Tư Lệnh)** starter scaffold and architectural foundation designed with strict layer separation, a two-speed 60/120Hz 3D engine boundary, and a Blender glTF 2.0 (`.glb`) asset integration contract.

Commander Chess (*Cờ Tư Lệnh*, created by Colonel Nguyễn Quý Hải) is a Vietnamese combined-arms strategy board game played on an **11×12 intersection grid** (132 points) spanning **Land**, **River** (with two shallow **Fords** at `f` and `h` and an **Estuary** at `d6, e6, d7, e7`), **Coast**, **Deep Sea**, and **Airspace**, featuring 19 pieces per side across 11 unit types, carrier stacking (*cõng quân*), air-defense interception zones, ranged stay-captures, and Heroic promotion.

---

## Quick Start

### Prerequisites
- **Flutter SDK**: `>=3.47.0` (verified on **Flutter 3.50.1 stable / Dart 3.14.0**)
- **UI Package**: Uses `package:material_ui/material_ui.dart` (`package:flutter/material.dart` is `@Deprecated` in Flutter 3.50.1+)
- On Windows hosts where Flutter is installed at `D:\Dev\flutter\bin` and not on the active shell `PATH`:

```powershell
$env:PATH = "D:\Dev\flutter\bin;$env:PATH"
```

### Run & Verify

```powershell
cd D:\Project\commander_chess_3d

# 1. Resolve dependencies
flutter pub get

# 2. Static analysis (zero errors, zero warnings)
flutter analyze

# 3. Run automated 4-layer test suite (headless)
flutter test

# 4. Run live in Chrome (Web)
flutter run -d chrome

# 5. Build Web release bundle
flutter build web
```

> **Platform Note (Windows)**: Android, iOS, Web, Windows, macOS, and Linux runners are generated. On Windows hosts without Visual Studio C++ ("Desktop development with C++"), use `flutter test`, `flutter run -d chrome`, `flutter build web`, or Android targets (`flutter build apk`).

---

## Project Structure

```text
commander_chess_3d/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
├── docs/
│   ├── ARCHITECTURE.md                  # 6-layer + two-speed architecture & Dart contracts (R1, R3)
│   ├── BLENDER_ASSET_CONTRACT.md        # glTF 2.0 (.glb) export, hierarchy, PBR & NLA spec (R3)
│   └── ROADMAP.md                       # 5-phase future roadmap (R4)
├── openapi/
│   └── commander_chess_v1.yaml          # Authoritative REST + WebSocket multiplayer contract
├── assets/
│   ├── models/
│   │   ├── asset_manifest.json          # PieceVisualKey <-> .glb + LOD + animation mapping
│   │   └── pieces/                      # Future Blender-exported .glb piece & board models
│   └── shaders/
│       └── terrain_highlight.frag       # Impeller GLSL (#version 460 core) highlight shader
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/                            # Pure Dart shared primitives (Result, AppFailure, Clock)
│   └── features/game/
│       ├── models/                      # [flutter-model] Pure Dart entities, DTOs, AssetManifest
│       ├── rules/                       # [flutter-business-rules] Pure Dart 11x12 topology & rules
│       ├── repositories/                # [flutter-api] Persistence, WS transport, manifest loader
│       ├── state/                       # [flutter-state-riverpod] Manual Riverpod 3.x HUD Notifier
│       ├── engine/                      # [flutter-3d-performance] 60/120Hz loop, camera & 3D renderer
│       └── presentation/                # [flutter-ui] Material 3 Light/Dark HUD & RepaintBoundary view
└── test/
    ├── unit/                            # Pure Dart model & rules tests
    ├── state/                           # Riverpod ProviderContainer lifecycle & state tests
    ├── api/                             # Repository & multiplayer transport contract tests
    └── widget/                          # Responsive Light/Dark UI & 3D viewport mount tests
```

---

## Squad Architecture Summary

This repository follows the **Flutter Full-Stack Squad** layer boundaries (`AGENTS.md`):

1. **Pure-Dart Domain (`core/`, `models/`, `rules/`)**: Zero imports from `package:flutter/*`, `package:material_ui/*`, or `package:flutter_riverpod/*`. Shared identically across local play, background `Isolate` AI search, and future server-side validation.
2. **Repositories & Contracts (`repositories/`, `openapi/`)**: Clean async `Result<T>` interfaces for match persistence (`GameRepository`), online sync (`MultiplayerTransport`), AI inference (`AiOpponentEngine`), and Blender manifest loading (`AssetManifestLoader`).
3. **Cold HUD State (`state/`)**: Zero-codegen **Manual Riverpod 3.x** (`Notifier` / `NotifierProvider`) storing only discrete `GameHudSnapshot` updates — never driven by 60/120Hz frame ticks.
4. **Hot-Path 3D Engine (`engine/`)**: `FixedTimestepDriver` (`Ticker` + `AppLifecycleListener`, clamped `dt <= 0.05`) drives `SpringOrbitCamera3D` and piece motion inside `Board3DSceneController` (`ChangeNotifier`), isolated behind a `RepaintBoundary` and abstract `BoardSceneRenderer` / `PieceAssetProvider` contracts.
5. **Swappable 3D Stack**: The starter mounts a deterministic `CustomPainter` + `vector_math_64` 3D renderer (with optional `ui.FragmentProgram` shader hook) that runs identically in headless `flutter test` and Web/Mobile. Phase B swaps in `flutter_scene` + `flutter_gpu` (Impeller `.glb`) with zero changes to `models/`, `rules/`, `repositories/`, or `state/`.

---

## Documentation

- [Architecture & Interface Contracts](docs/ARCHITECTURE.md)
- [Blender glTF 2.0 (`.glb`) 3D Asset Contract](docs/BLENDER_ASSET_CONTRACT.md)
- [5-Phase Implementation Roadmap](docs/ROADMAP.md)
