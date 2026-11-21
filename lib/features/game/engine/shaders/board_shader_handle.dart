import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Lifecycle-safe wrapper around `assets/shaders/terrain_highlight.frag`.
///
/// Gracefully degrades to `isReady == false` when runtime shaders are
/// unavailable (such as inside headless `flutter test` environments).
final class BoardShaderHandle {
  BoardShaderHandle({
    this.assetKey = 'assets/shaders/terrain_highlight.frag',
  });

  final String assetKey;

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  final Paint _paint = Paint();
  bool _disposed = false;

  bool get isReady => _shader != null && !_disposed;
  ui.FragmentProgram? get program => _program;

  /// Asynchronously compiles the fragment program with a safe `null` fallback.
  Future<void> initialize() async {
    if (_disposed || _shader != null) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(assetKey);
      if (_disposed) return;
      _program = program;
      _shader = program.fragmentShader();
    } catch (_) {
      // Headless widget tests or unsupported software renderers fall back
      // cleanly to pure Canvas fills without crashing.
      _program = null;
      _shader = null;
    }
  }

  /// Updates shader uniforms and returns a reusable [Paint], or `null` if
  /// shader compilation is unavailable or disposed.
  Paint? updateAndBind({
    required Size size,
    required double timeSeconds,
    required Color baseColor,
    required Color accentColor,
  }) {
    final shader = _shader;
    if (_disposed || shader == null) {
      return null;
    }

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, timeSeconds)
      ..setFloat(3, baseColor.r)
      ..setFloat(4, baseColor.g)
      ..setFloat(5, baseColor.b)
      ..setFloat(6, baseColor.a)
      ..setFloat(7, accentColor.r)
      ..setFloat(8, accentColor.g)
      ..setFloat(9, accentColor.b)
      ..setFloat(10, accentColor.a);
    _paint.shader = shader;
    return _paint;
  }

  /// Deterministically disposes GPU shader resources. Safe to call repeatedly.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _paint.shader = null;
    _shader?.dispose();
    _shader = null;
    _program = null;
  }
}
