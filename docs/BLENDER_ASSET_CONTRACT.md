# Blender 3D Asset & glTF 2.0 (`.glb`) Integration Contract

This specification defines the exact 3D modeling, coordinate, hierarchy, PBR material, NLA animation, and manifest contract between **Blender artists** and the **Flutter 3D engine layer** (`lib/features/game/engine/`). Adhering to this contract allows Blender-authored `.glb` pieces and terrain boards to replace the starter procedural 3D primitives with **zero changes** to `models/`, `rules/`, `repositories/`, or Riverpod `state/`.

---

## 1. File Format & Export Settings

- **Container Format**: Khronos **glTF 2.0 Binary (`.glb`)** with embedded textures (`Format: glTF Binary (.glb)`).
- **Asset Directory**:
  - Board mesh: `assets/models/board/commander_board_11x12.glb`
  - Piece meshes: `assets/models/pieces/<piece_type>_lod0.glb` and `<piece_type>_lod1.glb`
  - Runtime registry: `assets/models/asset_manifest.json`
- **Coordinate System & Transform**:
  - **Khronos glTF 2.0 Standard**: Right-handed, **`+Y` Up**, **`+Z` Forward** (model local forward axis), `+X` model's left.
  - **Blender Authoring**: Model in Blender's native **`+Z` Up**, **`-Y` Front** orientation.
  - **Mandatory Pre-Export Step**: Select all objects and run **`Ctrl+A -> Apply -> All Transforms`** so Location `(0, 0, 0)` (on root), Rotation `(0, 0, 0)`, and Scale `(1, 1, 1)` are baked cleanly.
  - **Blender Exporter (`File -> Export -> glTF 2.0`)**:
    - `Include > Selected Objects` (or dedicated collection per piece)
    - `Transform > +Y Up` = **Checked**
    - `Data > Mesh > Apply Modifiers` = **Checked**, `UVs` = **Checked**, `Normals` = **Checked**
    - `Data > Material > Materials: Export`, `Images: Automatic` (PNG/WebP)
    - `Animation > Animation` = **Checked**, `Group by NLA Track` = **Checked**, `Always Sample Animations` = **Checked**, `Limit to Playback Range` = **Checked**, `Optimize Animation Size` = **Checked**

### Engine Handedness Integration Note
- **`flutter_scene` (`flutter_gpu`)** uses a left-handed world coordinate space (`+Z` into screen) and automatically converts glTF 2.0 right-handed assets during import.
- **`thermion_flutter` (Filament)** uses right-handed world space; when loading piece `.glb` files in Filament, set `transformToUnitCube: false` so metric tile proportions are preserved.
- **`BoardCoordinateMapper`** in `lib/features/game/engine/` is the single source of truth mapping `(file 0..10, rank 0..11)` to world `(X, Y, Z)`.

---

## 2. Metric Scale, Pivot & Triangle Budgets

### Metric Board Scale
- **1.0 glTF unit (1.0 m) = 1 board intersection spacing**.
- **Playable Intersection Span**: `10.0` units wide (`X ∈ [-5.0, +5.0]`, files `a..k` / `0..10`) × `11.0` units deep (`Z ∈ [-5.5, +5.5]`, ranks `1..12` / `0..11`).
- **Full Board Mesh Footprint**: `11.0 × 12.0` units centered at `(0, 0, 0)` with top playing surface flush at **`Y = 0.0`**.
- **Piece Orientation**: In Blender/glTF local space, every piece faces local **`+Z`**. In world space (`BoardCoordinateMapper`: Red rank 1 baseline at `Z = +5.5`, Blue rank 12 baseline at `Z = -5.5`), Red pieces are rotated `π` radians (`180°`) around `Y` so local `+Z` faces world `-Z` (toward rank 12 / Blue); Blue pieces use `0` radians (`0°`) around `Y` so local `+Z` faces world `+Z` (toward rank 1 / Red).

### Piece Pivot & Bounding Box
- **Pivot / Origin**: Strictly at **bottom-center `(0.0, 0.0, 0.0)`** resting flush on `Y = 0.0`.
- **Maximum Bounding Box**:
  - `X ∈ [-0.425, +0.425]` (width `<= 0.85` units)
  - `Y ∈ [0.000, +1.200]` (height `<= 1.20` units)
  - `Z ∈ [-0.425, +0.425]` (depth `<= 0.85` units)
  - Keeping footprint `<= 0.85` guarantees adjacent pieces at `1.0` tile spacing never clip.

### Triangle & Texture Budgets

| Tier | Simple Pieces (`I, M, E, G, S, H, C`) | Complex Vehicles (`T, A, F, N`) | Board Mesh | Full 38-Piece Match + Board |
| --- | --- | --- | --- | --- |
| **LOD0 (Close / Desktop / High)** | `500 – 1,200` tris | `1,200 – 3,000` tris | `500 – 2,000` tris | **`<= 65,000` tris** |
| **LOD1 (Overview / Mobile Low)** | `300 – 800` tris | `300 – 800` tris | `300 – 800` tris | **`<= 25,000` tris** |

- Use **`Shade Auto Smooth`** (or weighted normals) on hard-surface mechanical edges.
- Keep skeleton bone count `<= 48` bones per piece if rigged.

---

## 3. Canonical Node Hierarchy (`snake_case`)

Runtime scripts locate sub-meshes (for turret aiming, Heroic base tinting, and passenger mounting) by exact node names. Do **not** leave default Blender names (`Cube.001`, `Empty.002`).

### Piece Outliner Hierarchy

```text
piece_<type>                     # Root empty/mesh; <type> in 11 canonical IDs below
├── base_pedestal                # Required: circular/octagonal tactical base resting at y = 0.0
├── body_hull                    # Required: primary chassis, torso, hull, or bunker body
├── turret                       # Optional: Y-rotatable turret (tank, artillery, anti_aircraft, navy)
│   └── barrel                   # Optional: elevation child of turret
├── insignia_star                # Optional: commander star / heroic emblem mesh
├── wing_rotor                   # Optional: aircraft wings / rotor assembly (air_force)
├── socket_passenger_0           # Required Empty on carriers (navy, air_force, tank, engineer, headquarters)
└── socket_passenger_1           # Required Empty on multi-passenger carriers (navy, air_force, tank)
```

Canonical `<type>` identifiers matching `PieceType`:
`commander`, `headquarters`, `infantry`, `militia`, `engineer`, `tank`, `artillery`, `anti_aircraft`, `missile`, `air_force`, `navy`.

### Board Outliner Hierarchy

```text
board_root
├── board_frame                  # Outer wooden/tactical border around 11x12 grid
├── terrain_land                 # Land landmass (files d..k + shared coast border)
├── terrain_sea                  # Deep sea flank (files a, b) and coastal shelf (file c)
├── terrain_river                # River trench separating ranks 6 and 7
├── ford_f                       # Shallow crossing bridge/stones at f6-f7
├── ford_h                       # Shallow crossing bridge/stones at h6-h7
└── grid_overlay                 # Crisp 11x12 intersection line & coordinate markers at y = 0.002
```

---

## 4. PBR Material Slots & ORM Texture Packing

Each piece `.glb` is authored **once** and shared between Red and Blue teams via **5 exact named material slots** using Blender `Principled BSDF` nodes (no unsupported procedural `Noise`/`Musgrave` nodes — bake all textures to images):

| Material Slot Name | Role | Runtime Faction Parameterization |
| --- | --- | --- |
| `mat_faction_primary` | Main hull/armor/uniform albedo | Red `#C62828` vs Blue `#1565C0` |
| `mat_faction_accent` | Stripes, trim, insignia bands | Red Gold/Crimson vs Blue Silver/Cyan |
| `mat_base_pedestal` | Tactical pedestal base | Standard Slate/Bronze; **Heroic Gold `#FFD54F`** when `isHero == true` |
| `mat_neutral_metal` | Tracks, gun barrels, hatches, tires | Neutral dark gunmetal/steel |
| `mat_heroic_emissive` | Star/trim glow channel | Emissive `0.0` normally; activated on Heroic promotion |

### Texture Packing Standard
- **Resolution**: `512×512` (mobile/LOD1) up to `1024×1024` (LOD0 hero pieces & board).
- **Color Spaces**:
  - `Base Color` & `Emissive`: **sRGB**
  - `Normal` (DirectX/OpenGL tangent space per glTF standard): **Non-Color**
  - **Packed ORM Texture (`Non-Color`)**:
    - **R**: Ambient Occlusion
    - **G**: Roughness
    - **B**: Metallic

---

## 5. Standardized NLA Animation Clips

Each animated `.glb` must stash individual Blender **Actions** as **NLA Tracks** using these exact lowercase names matching `PieceAnimClip`:

| Clip Name | Playback | Purpose |
| --- | --- | --- |
| `idle` | Loop | Subtle breathing, radar rotation, rotor hum, or water bob |
| `select` | One-shot | Pedestal lift + ready stance pulse when selected |
| `move` | Loop | Walking cycle, track roll, propeller/jet flight, or wake glide |
| `attack` | One-shot | Barrel recoil, missile launch, or bombing run dive |
| `capture` | One-shot | Close-quarters strike / ramming impact |
| `promote` | One-shot | Heroic spin/elevation + insignia flare on checking enemy Commander |
| `defeat` | One-shot | Collapse, sink, or smoke-out disassembly on capture |

---

## 6. Runtime Manifest & Exact Swap Procedure

### 6.1 Manifest Registration (`assets/models/asset_manifest.json`)
Every `.glb` is mapped by `(type, side, isHero)` via `AssetManifest` and `MeshAssetDescriptor` (`lib/features/game/models/asset_manifest_model.dart`). When `GlbPieceAssetProvider` resolves a `PieceVisualKey`, it loads `glbPath` (and selects `lodTiers` by squared camera distance), attaches `carriedPieces` to `socket_passenger_0` / `socket_passenger_1`, and swaps `mat_faction_primary` / `mat_faction_accent` / `mat_base_pedestal` / `mat_heroic_emissive` material instances.

### 6.2 Step-by-Step Swap from Starter Placeholder to Production `.glb`
1. **Drop Models**: Place exported `<piece>_lod0.glb`, `<piece>_lod1.glb`, and `commander_board_11x12.glb` into `assets/models/pieces/` and `assets/models/board/` (canonical `boardGlbPath`: `assets/models/board/commander_board_11x12.glb`), then update paths in `assets/models/asset_manifest.json` (and `pubspec.yaml` asset entries if adding subdirectories).
2. **Add `flutter_scene` + `flutter_gpu`**: Add `flutter_scene: ^0.24.3` to `pubspec.yaml`, run `dart run flutter_scene:init` to configure `hook/build.dart`, and enable Flutter GPU in platform manifests (`AndroidManifest.xml`, `Info.plist`, `windows/runner/main.cpp`).
3. **Implement `GlbPieceAssetProvider`**: Create `lib/features/game/engine/assets/glb_piece_asset_provider.dart` implementing `PieceAssetProvider` to preload `flutter_scene` `Node` / `Mesh` templates, cache material variants (`red`, `blue`, `heroic`), and resolve `PieceVisualHandle` handles.
4. **Implement `FlutterSceneBoardRenderer`**: Create `lib/features/game/engine/render/flutter_scene_board_renderer.dart` implementing `BoardSceneRenderer`, rendering the `Scene`, driving `AnimationPlayer` with the 7 NLA clips (`idle`, `select`, `move`, `attack`, `capture`, `promote`, `defeat`), rotating `turret` toward targets, and mounting `carriedPieces` onto `socket_passenger_0` / `socket_passenger_1`.
5. **Bind in Presentation / DI**: Swap the `PieceAssetProvider` and `BoardSceneRenderer` instances constructed in `Board3DViewport` (while keeping `Placeholder3DBoardRenderer` as the Web/software fallback and headless `flutter test` mock).
6. **Zero Domain Changes**: `lib/core/`, `lib/features/game/models/`, `lib/features/game/rules/`, `lib/features/game/repositories/`, and `lib/features/game/state/` remain **100% untouched**.
