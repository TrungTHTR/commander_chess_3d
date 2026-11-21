import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart';

/// Frame-rate-independent damped spring orbit camera in `+Y` up world space.
final class SpringOrbitCamera3D {
  SpringOrbitCamera3D({
    double yaw = 0.0,
    double pitch = 0.86,
    double distance = 16.2,
    Vector3? target,
    double fovDegrees = 42.0,
    double stiffness = 12.0,
    double minPitch = 0.24,
    double maxPitch = 1.44,
    double minDistance = 7.5,
    double maxDistance = 64.0,
    double nearPlane = 0.2,
    double farPlane = 180.0,
  })  : fovDegrees = _sanitizeFovDegrees(fovDegrees),
        stiffness = _sanitizeStiffness(stiffness),
        minPitch = _sanitizeMinPitch(minPitch),
        maxPitch = _sanitizeMaxPitch(maxPitch, _sanitizeMinPitch(minPitch)),
        minDistance = _sanitizeMinDistance(minDistance),
        maxDistance = _sanitizeMaxDistance(
          maxDistance,
          _sanitizeMinDistance(minDistance),
        ),
        nearPlane = _sanitizeNearPlane(nearPlane),
        farPlane = _sanitizeFarPlane(farPlane, _sanitizeNearPlane(nearPlane)),
        _yaw = _wrapAngle(yaw.isFinite ? yaw : 0.0),
        _targetYaw = _wrapAngle(yaw.isFinite ? yaw : 0.0),
        _pitch = (pitch.isFinite ? pitch : 0.86).clamp(
          _sanitizeMinPitch(minPitch),
          _sanitizeMaxPitch(maxPitch, _sanitizeMinPitch(minPitch)),
        ),
        _targetPitch = (pitch.isFinite ? pitch : 0.86).clamp(
          _sanitizeMinPitch(minPitch),
          _sanitizeMaxPitch(maxPitch, _sanitizeMinPitch(minPitch)),
        ),
        _distance = (distance.isFinite ? distance : 16.2).clamp(
          _sanitizeMinDistance(minDistance),
          _sanitizeMaxDistance(
            maxDistance,
            _sanitizeMinDistance(minDistance),
          ),
        ),
        _targetDistance = (distance.isFinite ? distance : 16.2).clamp(
          _sanitizeMinDistance(minDistance),
          _sanitizeMaxDistance(
            maxDistance,
            _sanitizeMinDistance(minDistance),
          ),
        ),
        _target = _finiteVectorOrZero(target),
        _targetLookAt = _finiteVectorOrZero(target);

  final double fovDegrees;
  final double stiffness;
  final double minPitch;
  final double maxPitch;
  final double minDistance;
  final double maxDistance;
  final double nearPlane;
  final double farPlane;

  double _yaw;
  double _pitch;
  double _distance;
  final Vector3 _target;

  double _targetYaw;
  double _targetPitch;
  double _targetDistance;
  final Vector3 _targetLookAt;

  // Pre-allocated scratch buffers for zero-GC hot-loop matrix & ray math.
  final Vector3 _eyeScratch = Vector3.zero();
  final Vector3 _upScratch = Vector3(0.0, 1.0, 0.0);
  final Matrix4 _viewScratch = Matrix4.identity();
  final Matrix4 _projScratch = Matrix4.identity();
  final Matrix4 _vpScratch = Matrix4.identity();
  final Matrix4 _invVpScratch = Matrix4.identity();
  final Vector4 _nearScratch = Vector4.zero();
  final Vector4 _farScratch = Vector4.zero();

  double get yaw => _yaw;
  double get pitch => _pitch;
  double get distance => _distance;
  Vector3 get target => _target.clone();

  /// Computes the minimum orbit distance needed for the entire 11×12 board
  /// (`[-boardHalfWidth, +boardHalfWidth] × [-boardHalfDepth, +boardHalfDepth]`)
  /// to project within `[-viewportFill, +viewportFill]` in NDC at [aspectRatio],
  /// never shrinking below [baseDistance] and clamping to
  /// `[minDistance, maxDistance]`.
  static double computeBoardFitDistance({
    required double baseDistance,
    required double aspectRatio,
    double yaw = 0.0,
    double pitch = 0.86,
    double fovDegrees = 42.0,
    double minDistance = 7.5,
    double maxDistance = 64.0,
    double boardHalfWidth = 5.2,
    double boardHalfDepth = 5.7,
    double viewportFill = 0.96,
  }) {
    final safeMin = _sanitizeMinDistance(minDistance);
    final safeMax = _sanitizeMaxDistance(maxDistance, safeMin);
    if (!baseDistance.isFinite) return safeMin;
    final clampedBase = baseDistance.clamp(safeMin, safeMax);
    if (!aspectRatio.isFinite || aspectRatio <= 0.0) {
      return clampedBase;
    }
    if (!yaw.isFinite ||
        !pitch.isFinite ||
        !fovDegrees.isFinite ||
        fovDegrees <= 5.0 ||
        fovDegrees >= 165.0 ||
        !boardHalfWidth.isFinite ||
        !boardHalfDepth.isFinite ||
        !viewportFill.isFinite) {
      return clampedBase;
    }

    final halfFovY = radians(fovDegrees) * 0.5;
    final tanHalfY = math.tan(halfFovY);
    final tanHalfX = tanHalfY * aspectRatio;
    if (tanHalfY <= 1e-6 || tanHalfX <= 1e-6) {
      return clampedBase;
    }

    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    // Orthonormal camera basis vectors for eye(yaw, pitch) -> target(0, 0, 0).
    final rx = cosYaw;
    final rz = -sinYaw;
    final ux = -sinPitch * sinYaw;
    final uz = -sinPitch * cosYaw;
    final fx = -cosPitch * sinYaw;
    final fz = -cosPitch * cosYaw;

    final fill = viewportFill.clamp(0.5, 0.99);
    var required = clampedBase;

    for (final sx in const <double>[-1.0, 1.0]) {
      final px = sx * boardHalfWidth;
      for (final sz in const <double>[-1.0, 1.0]) {
        final pz = sz * boardHalfDepth;
        final xCam = (px * rx + pz * rz).abs();
        final yCam = (px * ux + pz * uz).abs();
        final pDotF = px * fx + pz * fz;

        final dForX = xCam / (fill * tanHalfX) - pDotF;
        final dForY = yCam / (fill * tanHalfY) - pDotF;
        final cornerMinD = math.max(dForX, dForY);
        if (cornerMinD > required) {
          required = cornerMinD;
        }
      }
    }

    return required.clamp(safeMin, safeMax);
  }

  /// Instance convenience wrapper computing aspect-aware distance using this
  /// camera's [fovDegrees], [minDistance], [maxDistance], and current target
  /// orientation when [yaw] / [pitch] are omitted.
  double fitDistanceForBoard({
    required double baseDistance,
    required double aspectRatio,
    double? yaw,
    double? pitch,
    double? boardHalfExtent,
    double boardHalfWidth = 5.2,
    double boardHalfDepth = 5.7,
    double viewportFill = 0.96,
  }) {
    return computeBoardFitDistance(
      baseDistance: baseDistance,
      aspectRatio: aspectRatio,
      yaw: yaw ?? _targetYaw,
      pitch: pitch ?? _targetPitch,
      fovDegrees: fovDegrees,
      minDistance: minDistance,
      maxDistance: maxDistance,
      boardHalfWidth: boardHalfExtent ?? boardHalfWidth,
      boardHalfDepth: boardHalfExtent ?? boardHalfDepth,
      viewportFill: viewportFill,
    );
  }

  /// Computes current world-space camera eye coordinates into [out].
  void eyePositionInto(Vector3 out) {
    final horiz = _distance * math.cos(_pitch);
    out.setValues(
      _target.x + horiz * math.sin(_yaw),
      _target.y + _distance * math.sin(_pitch),
      _target.z + horiz * math.cos(_yaw),
    );
  }

  /// Current world-space camera eye coordinates.
  Vector3 get eyePosition {
    final out = Vector3.zero();
    eyePositionInto(out);
    return out;
  }

  /// Orbits the camera around its target by screen-space pixel deltas.
  void orbitBy(double dx, double dy, {double sensitivity = 0.0075}) {
    if (!dx.isFinite || !dy.isFinite || !sensitivity.isFinite) return;
    _targetYaw = _wrapAngle(_targetYaw - dx * sensitivity);
    _targetPitch = (_targetPitch + dy * sensitivity).clamp(minPitch, maxPitch);
  }

  /// Adjusts camera orbit distance (positive zooms out, negative zooms in).
  void zoomBy(double delta) {
    if (!delta.isFinite) return;
    _targetDistance =
        (_targetDistance + delta).clamp(minDistance, maxDistance);
  }

  /// Immediately snaps camera position and target without spring lag.
  void snapToPreset({
    required double yaw,
    required double pitch,
    required double distance,
    Vector3? target,
  }) {
    if (!yaw.isFinite || !pitch.isFinite || !distance.isFinite) return;
    if (target != null && !_isFiniteVector(target)) return;
    final clampedPitch = pitch.clamp(minPitch, maxPitch);
    final clampedDistance = distance.clamp(minDistance, maxDistance);
    _yaw = _wrapAngle(yaw);
    _targetYaw = _yaw;
    _pitch = clampedPitch;
    _targetPitch = clampedPitch;
    _distance = clampedDistance;
    _targetDistance = clampedDistance;
    if (target != null) {
      _target.setFrom(target);
      _targetLookAt.setFrom(target);
    }
  }

  /// Smoothly interpolates toward the requested orbital view preset.
  void animateToPreset({
    required double yaw,
    required double pitch,
    required double distance,
    Vector3? target,
  }) {
    if (!yaw.isFinite || !pitch.isFinite || !distance.isFinite) return;
    if (target != null && !_isFiniteVector(target)) return;
    _targetYaw = _wrapAngle(yaw);
    _targetPitch = pitch.clamp(minPitch, maxPitch);
    _targetDistance = distance.clamp(minDistance, maxDistance);
    if (target != null) {
      _targetLookAt.setFrom(target);
    }
  }

  /// Advances exponential spring damping by [dt] seconds.
  ///
  /// Returns `true` while still visibly interpolating toward target.
  bool step(double dt) {
    if (!dt.isFinite || dt <= 0.0) return false;
    final alpha = 1.0 - math.exp(-stiffness * dt);

    final yawDiff = _shortestAngleDelta(_yaw, _targetYaw);
    final pitchDiff = _targetPitch - _pitch;
    final distDiff = _targetDistance - _distance;
    final txDiff = _targetLookAt.x - _target.x;
    final tyDiff = _targetLookAt.y - _target.y;
    final tzDiff = _targetLookAt.z - _target.z;

    const eps = 1e-4;
    if (yawDiff.abs() < eps &&
        pitchDiff.abs() < eps &&
        distDiff.abs() < eps &&
        txDiff.abs() < eps &&
        tyDiff.abs() < eps &&
        tzDiff.abs() < eps) {
      _yaw = _targetYaw;
      _pitch = _targetPitch;
      _distance = _targetDistance;
      _target.setFrom(_targetLookAt);
      return false;
    }

    _yaw = _wrapAngle(_yaw + yawDiff * alpha);
    _pitch += pitchDiff * alpha;
    _distance += distDiff * alpha;
    _target.x += txDiff * alpha;
    _target.y += tyDiff * alpha;
    _target.z += tzDiff * alpha;
    return true;
  }

  /// Writes the combined `Projection * View` matrix into [out] with zero allocations.
  void viewProjectionMatrixInto(Size size, Matrix4 out) {
    final safeHeight =
        !size.height.isFinite || size.height <= 0.0 ? 1.0 : size.height;
    final safeWidth =
        !size.width.isFinite || size.width <= 0.0 ? 1.0 : size.width;
    final aspect = safeWidth / safeHeight;

    eyePositionInto(_eyeScratch);
    setViewMatrix(_viewScratch, _eyeScratch, _target, _upScratch);
    setPerspectiveMatrix(
      _projScratch,
      radians(fovDegrees),
      aspect,
      nearPlane,
      farPlane,
    );
    out.setFrom(_projScratch);
    out.multiply(_viewScratch);
  }

  /// Returns a newly allocated `Projection * View` matrix for [size].
  Matrix4 viewProjectionMatrix(Size size) {
    final out = Matrix4.identity();
    viewProjectionMatrixInto(size, out);
    return out;
  }

  /// Casts a ray from [localPos] in viewport pixels onto the horizontal plane
  /// `y = planeY` (default `0.0`), returning the world intersection or `null`.
  Vector3? unprojectRayToGroundPlane(
    Offset localPos,
    Size size, {
    double planeY = 0.0,
  }) {
    if (!localPos.dx.isFinite ||
        !localPos.dy.isFinite ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !planeY.isFinite ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      return null;
    }

    viewProjectionMatrixInto(size, _vpScratch);
    final det = _invVpScratch.copyInverse(_vpScratch);
    if (!det.isFinite || det.abs() < 1e-10) {
      return null;
    }

    final ndcX = (2.0 * localPos.dx / size.width) - 1.0;
    final ndcY = 1.0 - (2.0 * localPos.dy / size.height);

    _nearScratch.setValues(ndcX, ndcY, -1.0, 1.0);
    _farScratch.setValues(ndcX, ndcY, 1.0, 1.0);
    _invVpScratch.transform(_nearScratch);
    _invVpScratch.transform(_farScratch);

    if (_nearScratch.w.abs() < 1e-9 || _farScratch.w.abs() < 1e-9) {
      return null;
    }

    final invNearW = 1.0 / _nearScratch.w;
    final nx = _nearScratch.x * invNearW;
    final ny = _nearScratch.y * invNearW;
    final nz = _nearScratch.z * invNearW;

    final invFarW = 1.0 / _farScratch.w;
    final fx = _farScratch.x * invFarW;
    final fy = _farScratch.y * invFarW;
    final fz = _farScratch.z * invFarW;

    final dx = fx - nx;
    final dy = fy - ny;
    final dz = fz - nz;
    if (dy.abs() < 1e-7) {
      return null;
    }

    final t = (planeY - ny) / dy;
    if (!t.isFinite || t < 0.0) {
      return null;
    }

    return Vector3(
      nx + dx * t,
      planeY,
      nz + dz * t,
    );
  }

  static double _sanitizeFovDegrees(double fovDegrees) =>
      (!fovDegrees.isFinite || fovDegrees <= 5.0 || fovDegrees >= 165.0)
          ? 42.0
          : fovDegrees;

  static double _sanitizeStiffness(double stiffness) =>
      (!stiffness.isFinite || stiffness <= 0.0) ? 12.0 : stiffness;

  static double _sanitizeNearPlane(double nearPlane) =>
      (!nearPlane.isFinite || nearPlane <= 0.0) ? 0.2 : nearPlane;

  static double _sanitizeFarPlane(double farPlane, double safeNear) =>
      (!farPlane.isFinite || farPlane <= safeNear)
          ? math.max(180.0, safeNear * 2.0)
          : farPlane;

  static double _sanitizeMinDistance(double minDistance) =>
      (!minDistance.isFinite || minDistance <= 0.0) ? 7.5 : minDistance;

  static double _sanitizeMaxDistance(double maxDistance, double safeMin) =>
      (!maxDistance.isFinite || maxDistance < safeMin)
          ? math.max(64.0, safeMin)
          : maxDistance;

  static double _sanitizeMinPitch(double minPitch) =>
      (!minPitch.isFinite || minPitch <= 0.0 || minPitch >= math.pi * 0.5)
          ? 0.24
          : minPitch;

  static double _sanitizeMaxPitch(double maxPitch, double safeMinPitch) =>
      (!maxPitch.isFinite ||
              maxPitch < safeMinPitch ||
              maxPitch >= math.pi * 0.5)
          ? math.max(1.44, safeMinPitch)
          : maxPitch;

  static bool _isFiniteVector(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;

  static Vector3 _finiteVectorOrZero(Vector3? v) {
    if (v == null || !_isFiniteVector(v)) return Vector3.zero();
    return v.clone();
  }

  static double _wrapAngle(double radians) {
    if (!radians.isFinite) return 0.0;
    var a = (radians + math.pi) % (2.0 * math.pi);
    if (a < 0.0) a += 2.0 * math.pi;
    return a - math.pi;
  }

  static double _shortestAngleDelta(double from, double to) {
    return _wrapAngle(to - from);
  }
}
