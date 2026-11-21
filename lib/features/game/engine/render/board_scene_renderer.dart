import 'dart:ui' show Canvas, Offset, Size;

import '../../models/board_coord.dart';
import '../animation/camera_rig_3d.dart';
import '../world/board_3d_scene_state.dart';

/// Rendering & picking contract decoupling the 3D scene loop and viewport from
/// concrete renderer backends (`Placeholder3DBoardRenderer`, future
/// `FlutterSceneBoardRenderer` / `ThermionBoardRenderer`).
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
