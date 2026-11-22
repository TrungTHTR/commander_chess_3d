import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commander_chess_3d/core/result/result.dart';
import 'package:commander_chess_3d/features/game/engine/animation/camera_rig_3d.dart';
import 'package:commander_chess_3d/features/game/engine/assets/faction_mesh_builder.dart';
import 'package:commander_chess_3d/features/game/engine/assets/glb_binary_reader.dart';
import 'package:commander_chess_3d/features/game/engine/assets/piece_asset_provider.dart';
import 'package:commander_chess_3d/features/game/engine/loop/board_3d_scene_controller.dart';
import 'package:commander_chess_3d/features/game/engine/render/placeholder_3d_board_renderer.dart';
import 'package:commander_chess_3d/features/game/engine/shaders/board_shader_handle.dart';
import 'package:commander_chess_3d/features/game/engine/world/board_3d_scene_state.dart';
import 'package:commander_chess_3d/features/game/models/action_model.dart';
import 'package:commander_chess_3d/features/game/models/asset_manifest_model.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/repositories/asset_manifest_loader.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';

final class _MissingGlbAssetBundle extends CachingAssetBundle {
  _MissingGlbAssetBundle(this._manifestJson);

  final String _manifestJson;

  @override
  Future<ByteData> load(String key) async {
    if (key == BundledAssetManifestLoader.defaultManifestPath) {
      final bytes = Uint8List.fromList(utf8.encode(_manifestJson));
      return ByteData.sublistView(bytes);
    }
    throw FlutterError('Simulated missing asset: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == BundledAssetManifestLoader.defaultManifestPath) {
      return _manifestJson;
    }
    throw FlutterError('Simulated missing string asset: $key');
  }
}

final class _ControlledGlbAssetBundle extends CachingAssetBundle {
  _ControlledGlbAssetBundle(this._loadHandler);

  final Future<ByteData> Function(String key) _loadHandler;

  @override
  Future<ByteData> load(String key) => _loadHandler(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    throw FlutterError('Unexpected loadString: $key');
  }
}

int _hashMeshGeometry(ProceduralMeshPrimitive mesh) {
  var hash = 0xcbf29ce484222325;
  final byteData = mesh.vertices.buffer.asByteData();
  for (var i = 0; i < mesh.vertices.length; i++) {
    hash ^= byteData.getUint32(i * 4, Endian.little);
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  for (var i = 0; i < mesh.faceIndices.length; i++) {
    hash ^= mesh.faceIndices[i];
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}

int _hashBytes(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (var i = 0; i < bytes.length; i++) {
    hash ^= bytes[i];
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}

({double hausdorff, double meanNearest}) _meshDistances(
  ProceduralMeshPrimitive a,
  ProceduralMeshPrimitive b,
) {
  final aCount = a.vertices.length ~/ 3;
  final bCount = b.vertices.length ~/ 3;
  var maxDist = 0.0;
  var sumA = 0.0;
  var sumB = 0.0;

  for (var i = 0; i < aCount; i++) {
    final ax = a.vertices[i * 3];
    final ay = a.vertices[i * 3 + 1];
    final az = a.vertices[i * 3 + 2];
    var bestSq = double.infinity;
    for (var j = 0; j < bCount; j++) {
      final dx = ax - b.vertices[j * 3];
      final dy = ay - b.vertices[j * 3 + 1];
      final dz = az - b.vertices[j * 3 + 2];
      final dSq = dx * dx + dy * dy + dz * dz;
      if (dSq < bestSq) bestSq = dSq;
    }
    final d = math.sqrt(bestSq);
    if (d > maxDist) maxDist = d;
    sumA += d;
  }

  for (var j = 0; j < bCount; j++) {
    final bx = b.vertices[j * 3];
    final by = b.vertices[j * 3 + 1];
    final bz = b.vertices[j * 3 + 2];
    var bestSq = double.infinity;
    for (var i = 0; i < aCount; i++) {
      final dx = bx - a.vertices[i * 3];
      final dy = by - a.vertices[i * 3 + 1];
      final dz = bz - a.vertices[i * 3 + 2];
      final dSq = dx * dx + dy * dy + dz * dz;
      if (dSq < bestSq) bestSq = dSq;
    }
    final d = math.sqrt(bestSq);
    if (d > maxDist) maxDist = d;
    sumB += d;
  }

  final meanA = sumA / aCount;
  final meanB = sumB / bCount;
  final meanCombined = (sumA + sumB) / (aCount + bCount);
  final meanAvg = (meanA + meanB) * 0.5;
  return (
    hausdorff: maxDist,
    meanNearest: math.min(meanCombined, meanAvg),
  );
}

Uint8List _rebuildGlbWithJson(
  Uint8List validBytes,
  void Function(Map<String, dynamic> root) mutate,
) {
  final validView = ByteData.sublistView(validBytes);
  final jsonChunkLen = validView.getUint32(12, Endian.little);
  final binOffset = 20 + jsonChunkLen;
  final decoded = jsonDecode(
    utf8.decode(Uint8List.sublistView(validBytes, 20, 20 + jsonChunkLen)),
  ) as Map<String, dynamic>;
  mutate(decoded);
  final badJsonBytes = utf8.encode(jsonEncode(decoded));
  final pad = (4 - (badJsonBytes.length % 4)) % 4;
  final newJsonLen = badJsonBytes.length + pad;
  final binPayload = Uint8List.sublistView(validBytes, binOffset + 8);
  final out = Uint8List(20 + newJsonLen + 8 + binPayload.length);
  final outView = ByteData.sublistView(out);
  outView.setUint32(0, GlbBinaryReader.glbMagic, Endian.little);
  outView.setUint32(4, 2, Endian.little);
  outView.setUint32(8, out.length, Endian.little);
  outView.setUint32(12, newJsonLen, Endian.little);
  outView.setUint32(16, GlbBinaryReader.chunkTypeJson, Endian.little);
  out.setRange(20, 20 + badJsonBytes.length, badJsonBytes);
  for (var i = 0; i < pad; i++) {
    out[20 + badJsonBytes.length + i] = 0x20;
  }
  outView.setUint32(20 + newJsonLen, binPayload.length, Endian.little);
  outView.setUint32(
    20 + newJsonLen + 4,
    GlbBinaryReader.chunkTypeBin,
    Endian.little,
  );
  out.setRange(20 + newJsonLen + 8, out.length, binPayload);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FactionUnitMeshBuilder (121 national silhouettes)', () {
    test('builds all 121 models within strict bounds, extents, triangle budgets, teamRing & sockets', () {
      for (final type in PieceType.values) {
        final geometryHashes = <int>{};

        for (final faction in FactionId.values) {
          final mesh = FactionUnitMeshBuilder.build(faction, type);
          expect(mesh.vertices.length, greaterThan(0));
          expect(mesh.faceCount, greaterThan(0));
          expect(mesh.faceNormals.length, equals(mesh.faceCount * 3));
          expect(mesh.faceIndices.length, equals(mesh.faceCount * 4));
          expect(mesh.facePartTags.length, equals(mesh.faceCount));

          final tris = mesh.triangleCount;
          expect(
            tris,
            inInclusiveRange(250, 500),
            reason: '${faction.code}.${type.snakeCaseName} tris=$tris',
          );

          var minX = double.infinity;
          var maxX = double.negativeInfinity;
          var minY = double.infinity;
          var maxY = double.negativeInfinity;
          var minZ = double.infinity;
          var maxZ = double.negativeInfinity;

          final vertCount = mesh.vertices.length ~/ 3;
          for (var i = 0; i < vertCount; i++) {
            final x = mesh.vertices[i * 3];
            final y = mesh.vertices[i * 3 + 1];
            final z = mesh.vertices[i * 3 + 2];
            expect(x.isFinite && y.isFinite && z.isFinite, isTrue);
            expect(x, inInclusiveRange(-0.425, 0.425));
            expect(y, inInclusiveRange(0.0, 1.20));
            expect(z, inInclusiveRange(-0.425, 0.425));
            expect(math.sqrt(x * x + z * z), lessThanOrEqualTo(0.4251));
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            if (z < minZ) minZ = z;
            if (z > maxZ) maxZ = z;
          }

          expect(maxX - minX, greaterThan(0.05));
          expect(maxY - minY, greaterThan(0.05));
          expect(maxZ - minZ, greaterThan(0.05));

          // Verify teamRing slot & canonical part tags.
          var hasTeamRing = false;
          final parts = <MeshPartTag>{};
          for (var f = 0; f < mesh.faceCount; f++) {
            if (mesh.faceSlots[f] == ProceduralMaterialSlot.teamRing.index) {
              hasTeamRing = true;
            }
            parts.add(mesh.partTagForFace(f));
          }
          expect(hasTeamRing, isTrue);
          expect(parts, contains(MeshPartTag.basePedestal));
          expect(parts, contains(MeshPartTag.bodyHull));
          if (type == PieceType.commander) {
            expect(parts, contains(MeshPartTag.insigniaStar));
          }
          if (type == PieceType.tank ||
              type == PieceType.artillery ||
              type == PieceType.antiAircraft ||
              type == PieceType.navy) {
            expect(parts, contains(MeshPartTag.turret));
          }
          if (type == PieceType.airForce || type == PieceType.navy) {
            expect(parts, contains(MeshPartTag.wingRotor));
          }

          // Verify passenger sockets strictly match PieceType.carrierCapacity.
          expect(mesh.passengerSockets, hasLength(type.carrierCapacity));
          for (final sock in mesh.passengerSockets) {
            expect(sock.x, inInclusiveRange(-0.425, 0.425));
            expect(sock.y, inInclusiveRange(0.0, 1.20));
            expect(sock.z, inInclusiveRange(-0.425, 0.425));
          }

          geometryHashes.add(_hashMeshGeometry(mesh));
        }

        expect(
          geometryHashes,
          hasLength(FactionId.values.length),
          reason: '${type.snakeCaseName} must have 11 distinct silhouettes',
        );
      }
    });

    test('maintains genuine pairwise geometric distinctness across all 605 faction pairs', () {
      var checkedPairs = 0;
      for (final type in PieceType.values) {
        final meshes = <FactionId, ProceduralMeshPrimitive>{
          for (final faction in FactionId.values)
            faction: FactionUnitMeshBuilder.build(faction, type),
        };
        for (var i = 0; i < FactionId.values.length; i++) {
          for (var j = i + 1; j < FactionId.values.length; j++) {
            final fA = FactionId.values[i];
            final fB = FactionId.values[j];
            final dist = _meshDistances(meshes[fA]!, meshes[fB]!);
            checkedPairs++;
            expect(
              dist.hausdorff,
              greaterThanOrEqualTo(0.025),
              reason:
                  '${type.snakeCaseName}: ${fA.code} vs ${fB.code} hausD=${dist.hausdorff}',
            );
            expect(
              dist.meanNearest,
              greaterThanOrEqualTo(0.0025),
              reason:
                  '${type.snakeCaseName}: ${fA.code} vs ${fB.code} meanD=${dist.meanNearest}',
            );
          }
        }
      }
      expect(checkedPairs, equals(605));
    });
  });

  group('GlbBinaryReader & FactionGlbEncoder', () {
    test('round-trips non-carrier, 1-socket, and 2-socket faction models cleanly', () {
      const cases = <(FactionId, PieceType)>[
        (FactionId.usa, PieceType.commander),
        (FactionId.vietnam, PieceType.headquarters),
        (FactionId.unitedKingdom, PieceType.navy),
      ];

      for (final (faction, type) in cases) {
        final mesh = FactionUnitMeshBuilder.build(faction, type);
        final bytes = FactionGlbEncoder.encode(
          faction: faction,
          type: type,
          mesh: mesh,
        );
        final parsed = GlbBinaryReader.parse(bytes);
        final parsedBd = GlbBinaryReader.parseByteData(ByteData.sublistView(bytes));

        expect(parsed.version, 2);
        expect(parsed.totalLength, bytes.length);
        expect(parsed.triangleCount, mesh.triangleCount);
        expect(parsedBd.triangleCount, parsed.triangleCount);
        expect(parsed.nodeNames, contains('piece_${type.snakeCaseName}'));
        expect(parsed.nodeNames, contains('base_pedestal'));
        expect(parsed.nodeNames, contains('body_hull'));

        if (type.carrierCapacity >= 1) {
          expect(parsed.nodeNames, contains('socket_passenger_0'));
        } else {
          expect(parsed.nodeNames, isNot(contains('socket_passenger_0')));
        }
        if (type.carrierCapacity >= 2) {
          expect(parsed.nodeNames, contains('socket_passenger_1'));
        } else {
          expect(parsed.nodeNames, isNot(contains('socket_passenger_1')));
        }

        expect(
          parsed.materialNames,
          containsAll(const <String>[
            'mat_faction_primary',
            'mat_faction_accent',
            'mat_base_pedestal',
            'mat_neutral_metal',
            'mat_heroic_emissive',
            'mat_team_ring',
          ]),
        );

        expect(parsed.minBounds.x, greaterThanOrEqualTo(-0.4251));
        expect(parsed.maxBounds.x, lessThanOrEqualTo(0.4251));
        expect(parsed.minBounds.y, greaterThanOrEqualTo(-0.0001));
        expect(parsed.maxBounds.y, lessThanOrEqualTo(1.2001));
        expect(parsed.minBounds.z, greaterThanOrEqualTo(-0.4251));
        expect(parsed.maxBounds.z, lessThanOrEqualTo(0.4251));
      }
    });

    test('rejects malformed, truncated, or adversarial GLB inputs with FormatException', () {
      final validMesh = FactionUnitMeshBuilder.build(
        FactionId.germany,
        PieceType.tank,
      );
      final validBytes = FactionGlbEncoder.encode(
        faction: FactionId.germany,
        type: PieceType.tank,
        mesh: validMesh,
      );

      // 1. Too short
      expect(() => GlbBinaryReader.parse(Uint8List(12)), throwsFormatException);

      // 2. Non-4-byte aligned total length
      expect(
        () => GlbBinaryReader.parse(Uint8List(validBytes.length + 1)),
        throwsFormatException,
      );

      // 3. Bad magic
      final badMagic = Uint8List.fromList(validBytes);
      ByteData.sublistView(badMagic).setUint32(0, 0x12345678, Endian.little);
      expect(() => GlbBinaryReader.parse(badMagic), throwsFormatException);

      // 4. Unsupported version
      final badVersion = Uint8List.fromList(validBytes);
      ByteData.sublistView(badVersion).setUint32(4, 1, Endian.little);
      expect(() => GlbBinaryReader.parse(badVersion), throwsFormatException);

      // 5. Mismatched total length header
      final badLen = Uint8List.fromList(validBytes);
      ByteData.sublistView(badLen).setUint32(8, validBytes.length - 4, Endian.little);
      expect(() => GlbBinaryReader.parse(badLen), throwsFormatException);

      // 6. Wrong JSON chunk type
      final badJsonType = Uint8List.fromList(validBytes);
      ByteData.sublistView(badJsonType).setUint32(16, 0x58585858, Endian.little);
      expect(() => GlbBinaryReader.parse(badJsonType), throwsFormatException);

      // 7. JSON chunk length not divisible by 4
      final badJsonLen = Uint8List.fromList(validBytes);
      ByteData.sublistView(badJsonLen).setUint32(12, 13, Endian.little);
      expect(() => GlbBinaryReader.parse(badJsonLen), throwsFormatException);

      // 8. Wrong BIN chunk type
      final jsonChunkLen = ByteData.sublistView(validBytes).getUint32(12, Endian.little);
      final binOffset = 20 + jsonChunkLen;
      final badBinType = Uint8List.fromList(validBytes);
      ByteData.sublistView(badBinType).setUint32(binOffset + 4, 0x58585858, Endian.little);
      expect(() => GlbBinaryReader.parse(badBinType), throwsFormatException);

      // 9. Corrupt asset.version inside JSON
      final decoded = jsonDecode(
        utf8.decode(Uint8List.sublistView(validBytes, 20, 20 + jsonChunkLen)),
      ) as Map<String, dynamic>;
      (decoded['asset'] as Map<String, dynamic>)['version'] = '1.0';
      final badJsonBytes = utf8.encode(jsonEncode(decoded));
      final pad = (4 - (badJsonBytes.length % 4)) % 4;
      final newJsonLen = badJsonBytes.length + pad;
      final binPayload = Uint8List.sublistView(validBytes, binOffset + 8);
      final badAssetVer = Uint8List(20 + newJsonLen + 8 + binPayload.length);
      final badAssetView = ByteData.sublistView(badAssetVer);
      badAssetView.setUint32(0, GlbBinaryReader.glbMagic, Endian.little);
      badAssetView.setUint32(4, 2, Endian.little);
      badAssetView.setUint32(8, badAssetVer.length, Endian.little);
      badAssetView.setUint32(12, newJsonLen, Endian.little);
      badAssetView.setUint32(16, GlbBinaryReader.chunkTypeJson, Endian.little);
      badAssetVer.setRange(20, 20 + badJsonBytes.length, badJsonBytes);
      for (var i = 0; i < pad; i++) {
        badAssetVer[20 + badJsonBytes.length + i] = 0x20;
      }
      badAssetView.setUint32(20 + newJsonLen, binPayload.length, Endian.little);
      badAssetView.setUint32(20 + newJsonLen + 4, GlbBinaryReader.chunkTypeBin, Endian.little);
      badAssetVer.setRange(20 + newJsonLen + 8, badAssetVer.length, binPayload);
      expect(() => GlbBinaryReader.parse(badAssetVer), throwsFormatException);

      // 10. NaN vertex coordinate in BIN chunk
      final nanBytes = Uint8List.fromList(validBytes);
      ByteData.sublistView(nanBytes).setFloat32(binOffset + 8, double.nan, Endian.little);
      expect(() => GlbBinaryReader.parse(nanBytes), throwsFormatException);

      // 11. Out-of-range vertex index in BIN chunk
      final parsedValid = GlbBinaryReader.parse(validBytes);
      final firstMesh = (parsedValid.jsonRoot['meshes'] as List).first as Map;
      final firstPrim = (firstMesh['primitives'] as List).first as Map;
      final idxAccIdx = firstPrim['indices'] as int;
      final idxAcc = (parsedValid.jsonRoot['accessors'] as List)[idxAccIdx] as Map;
      final idxBvIdx = idxAcc['bufferView'] as int;
      final idxBv = (parsedValid.jsonRoot['bufferViews'] as List)[idxBvIdx] as Map;
      final idxFileOffset = binOffset + 8 + ((idxBv['byteOffset'] as int?) ?? 0);
      final badIdxBytes = Uint8List.fromList(validBytes);
      ByteData.sublistView(badIdxBytes).setUint16(idxFileOffset, 65000, Endian.little);
      expect(() => GlbBinaryReader.parse(badIdxBytes), throwsFormatException);
    });

    test('rejects malformed JSON field types with FormatException instead of TypeError', () {
      final validMesh = FactionUnitMeshBuilder.build(
        FactionId.usa,
        PieceType.tank,
      );
      final validBytes = FactionGlbEncoder.encode(
        faction: FactionId.usa,
        type: PieceType.tank,
        mesh: validMesh,
      );

      final posAccIdx =
          (((jsonDecode(utf8.decode(Uint8List.sublistView(
                      validBytes,
                      20,
                      20 +
                          ByteData.sublistView(validBytes)
                              .getUint32(12, Endian.little),
                    ))) as Map)['meshes'] as List)
                  .first['primitives'] as List)
              .first['attributes']['POSITION'] as int;
      final normAccIdx =
          (((jsonDecode(utf8.decode(Uint8List.sublistView(
                      validBytes,
                      20,
                      20 +
                          ByteData.sublistView(validBytes)
                              .getUint32(12, Endian.little),
                    ))) as Map)['meshes'] as List)
                  .first['primitives'] as List)
              .first['attributes']['NORMAL'] as int;
      final idxAccIdx =
          (((jsonDecode(utf8.decode(Uint8List.sublistView(
                      validBytes,
                      20,
                      20 +
                          ByteData.sublistView(validBytes)
                              .getUint32(12, Endian.little),
                    ))) as Map)['meshes'] as List)
                  .first['primitives'] as List)
              .first['indices'] as int;

      final cases = <String, void Function(Map<String, dynamic>)>{
        'bv_byteOffset_str': (root) {
          ((root['bufferViews'] as List).first as Map)['byteOffset'] = '0';
        },
        'bv_buffer_str': (root) {
          ((root['bufferViews'] as List).first as Map)['buffer'] = '0';
        },
        'bv_byteStride_str': (root) {
          ((root['bufferViews'] as List).first as Map)['byteStride'] = '12';
        },
        'acc_byteOffset_str': (root) {
          ((root['accessors'] as List)[posAccIdx] as Map)['byteOffset'] = '0';
        },
        'norm_acc_byteOffset_str': (root) {
          ((root['accessors'] as List)[normAccIdx] as Map)['byteOffset'] = '0';
        },
        'idx_acc_byteOffset_str': (root) {
          ((root['accessors'] as List)[idxAccIdx] as Map)['byteOffset'] = '0';
        },
        'node_scale_str': (root) {
          final meshNode = (root['nodes'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((n) => n['mesh'] != null);
          meshNode['scale'] = <Object?>['bad', 1, 1];
        },
        'node_trans_null': (root) {
          final meshNode = (root['nodes'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((n) => n['mesh'] != null);
          meshNode['translation'] = <Object?>[0, null, 0];
        },
        'node_scale_short': (root) {
          final meshNode = (root['nodes'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((n) => n['mesh'] != null);
          meshNode['scale'] = <Object?>[1, 1];
        },
        'node_mesh_str': (root) {
          final meshNode = (root['nodes'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((n) => n['mesh'] != null);
          meshNode['mesh'] = '0';
        },
        'prim_mode_str': (root) {
          (((root['meshes'] as List).first as Map)['primitives'] as List)
              .first['mode'] = '4';
        },
      };

      for (final entry in cases.entries) {
        final mutated = _rebuildGlbWithJson(validBytes, entry.value);
        expect(
          () => GlbBinaryReader.parse(mutated),
          throwsFormatException,
          reason: '${entry.key} must throw FormatException',
        );
      }
    });

    test('rejects 64-bit integer-overflow offsets, strides, and counts with FormatException', () {
      final validMesh = FactionUnitMeshBuilder.build(
        FactionId.usa,
        PieceType.tank,
      );
      final validBytes = FactionGlbEncoder.encode(
        faction: FactionId.usa,
        type: PieceType.tank,
        mesh: validMesh,
      );

      final jsonChunkLen =
          ByteData.sublistView(validBytes).getUint32(12, Endian.little);
      final rootTemplate = jsonDecode(
        utf8.decode(Uint8List.sublistView(validBytes, 20, 20 + jsonChunkLen)),
      ) as Map<String, dynamic>;
      final firstPrim =
          (((rootTemplate['meshes'] as List).first as Map)['primitives']
                  as List)
              .first as Map;
      final attrs = firstPrim['attributes'] as Map;
      final posAccIdx = attrs['POSITION'] as int;
      final normAccIdx = attrs['NORMAL'] as int;
      final idxAccIdx = firstPrim['indices'] as int;
      final accessors = rootTemplate['accessors'] as List;
      final posBvIdx = (accessors[posAccIdx] as Map)['bufferView'] as int;
      final normBvIdx = (accessors[normAccIdx] as Map)['bufferView'] as int;

      final overflowCases = <String, void Function(Map<String, dynamic>)>{
        'bv_offset_overflow': (root) {
          ((root['bufferViews'] as List)[posBvIdx] as Map)['byteOffset'] =
              0x7ffffffffffffffc;
        },
        'pos_acc_offset_overflow': (root) {
          ((root['accessors'] as List)[posAccIdx] as Map)['byteOffset'] =
              0x7ffffffffffffffc;
        },
        'pos_acc_count_overflow': (root) {
          ((root['accessors'] as List)[posAccIdx] as Map)['count'] =
              0x1000000000000000;
        },
        'pos_stride_overflow': (root) {
          ((root['bufferViews'] as List)[posBvIdx] as Map)['byteStride'] =
              0x7ffffffffffffffc;
        },
        'norm_bv_offset_overflow': (root) {
          ((root['bufferViews'] as List)[normBvIdx] as Map)['byteOffset'] =
              0x7ffffffffffffffc;
        },
        'norm_acc_offset_overflow': (root) {
          ((root['accessors'] as List)[normAccIdx] as Map)['byteOffset'] =
              0x7ffffffffffffffc;
        },
        'idx_acc_offset_overflow': (root) {
          ((root['accessors'] as List)[idxAccIdx] as Map)['byteOffset'] =
              0x7ffffffffffffffe;
        },
      };

      for (final entry in overflowCases.entries) {
        final mutated = _rebuildGlbWithJson(validBytes, entry.value);
        expect(
          () => GlbBinaryReader.parse(mutated),
          throwsFormatException,
          reason: '${entry.key} must throw FormatException (never RangeError)',
        );
      }
    });
  });

  group('ProceduralPieceAssetProvider', () {
    test('resolves all 484 faction handles + 44 null-faction handles synchronously with mirror-match teamRing', () {
      final provider = ProceduralPieceAssetProvider();
      addTearDown(provider.dispose);

      for (final faction in FactionId.values) {
        for (final type in PieceType.values) {
          for (final isHero in const <bool>[false, true]) {
            final redHandle = provider.resolvePiece(
              PieceVisualKey(
                type: type,
                side: PlayerSide.red,
                isHero: isHero,
                faction: faction,
              ),
            );
            final blueHandle = provider.resolvePiece(
              PieceVisualKey(
                type: type,
                side: PlayerSide.blue,
                isHero: isHero,
                faction: faction,
              ),
            );

            expect(redHandle.isGlbBacked, isFalse);
            expect(blueHandle.isGlbBacked, isFalse);
            expect(redHandle, isA<ProceduralPieceVisualHandle>());
            expect(blueHandle, isA<ProceduralPieceVisualHandle>());
            expect(redHandle.boundingRadius, lessThanOrEqualTo(0.425));

            final redProc = redHandle as ProceduralPieceVisualHandle;
            final blueProc = blueHandle as ProceduralPieceVisualHandle;

            // Mirror match keeps exact same national mesh while disambiguating teamRing.
            expect(identical(redProc.mesh, blueProc.mesh), isTrue);
            expect(
              redProc.colorForSlot(ProceduralMaterialSlot.teamRing.index),
              equals(ProceduralPieceAssetProvider.redTeamRingColor),
            );
            expect(
              blueProc.colorForSlot(ProceduralMaterialSlot.teamRing.index),
              equals(ProceduralPieceAssetProvider.blueTeamRingColor),
            );

            if (isHero) {
              expect(
                redProc.colorForSlot(ProceduralMaterialSlot.basePedestal.index),
                equals(ProceduralPieceAssetProvider.heroicGoldColor),
              );
              expect(
                redProc.colorForSlot(ProceduralMaterialSlot.heroicEmissive.index),
                equals(ProceduralPieceAssetProvider.heroicGoldColor),
              );
            }
          }
        }
      }

      expect(provider.cachedMeshCount, equals(121));

      // Null faction defaults cleanly to Vietnam (Red) / USA (Blue).
      for (final type in PieceType.values) {
        final redFallback = provider.resolvePiece(
          PieceVisualKey(type: type, side: PlayerSide.red),
        ) as ProceduralPieceVisualHandle;
        final redVn = provider.resolvePiece(
          PieceVisualKey(
            type: type,
            side: PlayerSide.red,
            faction: FactionId.vietnam,
          ),
        ) as ProceduralPieceVisualHandle;
        expect(identical(redFallback.mesh, redVn.mesh), isTrue);

        final blueFallback = provider.resolvePiece(
          PieceVisualKey(type: type, side: PlayerSide.blue),
        ) as ProceduralPieceVisualHandle;
        final blueUs = provider.resolvePiece(
          PieceVisualKey(
            type: type,
            side: PlayerSide.blue,
            faction: FactionId.usa,
          ),
        ) as ProceduralPieceVisualHandle;
        expect(identical(blueFallback.mesh, blueUs.mesh), isTrue);
      }
    });

    test('preloadAll tolerates missing GLB mock bundles, preloads 121 bundled GLBs, and survives dispose', () async {
      final manifestJson = File(
        BundledAssetManifestLoader.defaultManifestPath,
      ).readAsStringSync();
      final manifestResult = await BundledAssetManifestLoader(
        bundle: _MissingGlbAssetBundle(manifestJson),
        requireFactionMeshes: true,
      ).loadManifest();
      final manifest = switch (manifestResult) {
        Ok(:final data) => data,
        Err(:final failure) => fail('Failed to load manifest: $failure'),
      };

      final mockProvider = ProceduralPieceAssetProvider(
        bundle: _MissingGlbAssetBundle(manifestJson),
      );
      await mockProvider.preloadAll(manifest);
      expect(mockProvider.cachedMeshCount, equals(121));
      expect(mockProvider.preloadedGlbCount, equals(0));
      mockProvider.dispose();

      // Real bundled assets load all 121 GLB payloads via GlbBinaryReader.
      final realProvider = ProceduralPieceAssetProvider();
      await realProvider.preloadAll(manifest);
      expect(realProvider.cachedMeshCount, equals(121));
      expect(realProvider.preloadedGlbCount, equals(121));

      final sampleGlb = realProvider.preloadedGlbFor(
        const PieceVisualKey(
          type: PieceType.airForce,
          side: PlayerSide.blue,
          faction: FactionId.france,
        ),
      );
      expect(sampleGlb, isNotNull);
      expect(sampleGlb!.nodeNames, contains('socket_passenger_0'));
      expect(sampleGlb.nodeNames, contains('socket_passenger_1'));

      realProvider.dispose();
      expect(realProvider.cachedMeshCount, equals(0));
      expect(realProvider.preloadedGlbCount, equals(0));

      // Resolving after dispose still returns a synchronous procedural handle safely.
      final afterDispose = realProvider.resolvePiece(
        const PieceVisualKey(
          type: PieceType.commander,
          side: PlayerSide.red,
          faction: FactionId.japan,
        ),
      );
      expect(afterDispose.isGlbBacked, isFalse);
    });

    test('preloadAll + dispose async epoch race does not leak stale GLB entries into cache', () async {
      final mesh = FactionUnitMeshBuilder.build(
        FactionId.vietnam,
        PieceType.commander,
      );
      final validBytes = FactionGlbEncoder.encode(
        faction: FactionId.vietnam,
        type: PieceType.commander,
        mesh: mesh,
      );
      final completer = Completer<ByteData>();
      final bundle = _ControlledGlbAssetBundle((_) => completer.future);
      final provider = ProceduralPieceAssetProvider(bundle: bundle);
      addTearDown(provider.dispose);

      const manifestWithGlb = AssetManifest(
        boardGlbPath: 'assets/models/board/commander_board_11x12.glb',
        pieces: <MeshAssetDescriptor>[],
        factionMeshes: <FactionId, Map<PieceType, String>>{
          FactionId.vietnam: <PieceType, String>{
            PieceType.commander:
                'assets/models/pieces/vietnam_commander_lod0.glb',
          },
        },
      );
      const emptyManifest = AssetManifest(
        boardGlbPath: 'assets/models/board/commander_board_11x12.glb',
        pieces: <MeshAssetDescriptor>[],
      );

      final f1 = provider.preloadAll(manifestWithGlb);
      provider.dispose();
      await provider.preloadAll(emptyManifest);
      completer.complete(ByteData.sublistView(validBytes));
      await f1;

      expect(provider.preloadedGlbCount, equals(0));
    });
  });

  group('Disk 121 .glb files vs asset_manifest.json', () {
    test('all 121 faction .glb files exist, validate as glTF 2.0, and have distinct geometry per PieceType', () async {
      final manifestResult = await const BundledAssetManifestLoader(
        requireFactionMeshes: true,
      ).loadManifest();
      final manifest = switch (manifestResult) {
        Ok(:final data) => data,
        Err(:final failure) => fail('Failed to load manifest: $failure'),
      };

      expect(manifest.factionMeshes.length, equals(11));

      for (final type in PieceType.values) {
        final fileHashes = <int>{};
        for (final faction in FactionId.values) {
          final path = manifest.findFactionMeshPath(faction, type);
          expect(path, isNotNull);
          final file = File(path!);
          expect(file.existsSync(), isTrue, reason: 'Missing $path');

          final bytes = file.readAsBytesSync();
          fileHashes.add(_hashBytes(bytes));
          final parsed = GlbBinaryReader.parse(bytes);

          expect(parsed.minBounds.x, greaterThanOrEqualTo(-0.4251));
          expect(parsed.maxBounds.x, lessThanOrEqualTo(0.4251));
          expect(parsed.minBounds.y, greaterThanOrEqualTo(-0.0001));
          expect(parsed.maxBounds.y, lessThanOrEqualTo(1.2001));
          expect(parsed.minBounds.z, greaterThanOrEqualTo(-0.4251));
          expect(parsed.maxBounds.z, lessThanOrEqualTo(0.4251));
          expect(parsed.maxBounds.x - parsed.minBounds.x, greaterThan(0.05));
          expect(parsed.maxBounds.y - parsed.minBounds.y, greaterThan(0.05));
          expect(parsed.maxBounds.z - parsed.minBounds.z, greaterThan(0.05));

          expect(
            parsed.materialNames,
            containsAll(const <String>[
              'mat_faction_primary',
              'mat_faction_accent',
              'mat_base_pedestal',
              'mat_neutral_metal',
              'mat_heroic_emissive',
              'mat_team_ring',
            ]),
          );

          if (type.carrierCapacity >= 1) {
            expect(parsed.nodeNames, contains('socket_passenger_0'));
          } else {
            expect(parsed.nodeNames, isNot(contains('socket_passenger_0')));
          }
          if (type.carrierCapacity >= 2) {
            expect(parsed.nodeNames, contains('socket_passenger_1'));
          } else {
            expect(parsed.nodeNames, isNot(contains('socket_passenger_1')));
          }
        }
        expect(fileHashes, hasLength(11));
      }
    });
  });

  group('Board3DSceneController & Placeholder3DBoardRenderer', () {
    testWidgets('propagates session factions onto visualKey, triggers promote clip, and keeps carriedVisualKeys regression contract', (tester) async {
      final provider = ProceduralPieceAssetProvider();
      final renderer = Placeholder3DBoardRenderer(assetProvider: provider);
      final shaderHandle = BoardShaderHandle();
      final controller = Board3DSceneController(
        vsync: tester,
        renderer: renderer,
        assetProvider: provider,
        shaderHandle: shaderHandle,
      );
      addTearDown(controller.dispose);

      final infantry = PieceEntity(
        id: 'red_inf_1',
        side: PlayerSide.red,
        type: PieceType.infantry,
        position: BoardCoord.fromAlgebraic('e5'),
      );
      final carrier = PieceEntity(
        id: 'blue_navy_1',
        side: PlayerSide.blue,
        type: PieceType.navy,
        position: BoardCoord.fromAlgebraic('b10'),
        carriedPieces: <PieceEntity>[
          PieceEntity(
            id: 'blue_mil_1',
            side: PlayerSide.blue,
            type: PieceType.militia,
            position: BoardCoord.fromAlgebraic('b10'),
          ),
        ],
      );

      final initialSession = GameSessionState(
        matchId: 'faction_sync_test',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        redFaction: FactionId.germany,
        blueFaction: FactionId.france,
        pieces: <PieceEntity>[infantry, carrier],
      );

      controller.syncFromGameState(session: initialSession);
      final nodes = <String, RenderPieceNode>{
        for (final n in controller.snapshot.pieces) n.pieceId: n,
      };
      expect(nodes['red_inf_1']!.visualKey.faction, FactionId.germany);
      expect(nodes['blue_navy_1']!.visualKey.faction, FactionId.france);
      expect(
        nodes['blue_navy_1']!.carriedVisualKeys,
        equals(const <PieceVisualKey>[
          PieceVisualKey(type: PieceType.militia, side: PlayerSide.blue),
        ]),
      );

      // Promoting a piece triggers PieceAnimClip.promote.
      controller.syncFromGameState(
        session: initialSession.copyWith(
          pieces: <PieceEntity>[infantry.copyWith(isHero: true), carrier],
        ),
      );
      final promotedNode = controller.snapshot.pieces
          .firstWhere((n) => n.pieceId == 'red_inf_1');
      expect(promotedNode.animClip, PieceAnimClip.promote);
      expect(promotedNode.visualKey.isHero, isTrue);

      // Demoting (e.g. undo) resets promoteTimer immediately.
      controller.syncFromGameState(
        session: initialSession.copyWith(
          pieces: <PieceEntity>[infantry.copyWith(isHero: false), carrier],
        ),
      );
      final demotedNode = controller.snapshot.pieces
          .firstWhere((n) => n.pieceId == 'red_inf_1');
      expect(demotedNode.animClip, isNot(PieceAnimClip.promote));
      expect(demotedNode.visualKey.isHero, isFalse);

      // Transitioning to empty pieces or all-dead pieces clears snapshot.pieces.
      controller.syncFromGameState(
        session: initialSession.copyWith(
          pieces: <PieceEntity>[
            infantry.copyWith(isAlive: false),
            carrier.copyWith(isAlive: false),
          ],
        ),
      );
      expect(controller.snapshot.pieces, isEmpty);

      controller.syncFromGameState(session: initialSession);
      expect(controller.snapshot.pieces, hasLength(2));
      controller.syncFromGameState(
        session: initialSession.copyWith(pieces: const <PieceEntity>[]),
      );
      expect(controller.snapshot.pieces, isEmpty);

      // External updateSnapshot scenes still retain pieces across ticks.
      await controller.initialize();
      final customSnapshot = RenderBoardSnapshot(
        tiles: controller.mapper.buildDefaultTiles(),
        pieces: <RenderPieceNode>[
          RenderPieceNode(
            pieceId: 'external_1',
            visualKey: const PieceVisualKey(
              type: PieceType.commander,
              side: PlayerSide.red,
              faction: FactionId.vietnam,
            ),
            worldPosition: controller.mapper.coordToWorld(
              BoardCoord.fromAlgebraic('e5'),
            ),
            yawRadians: math.pi,
          ),
        ],
      );
      controller.updateSnapshot(customSnapshot);
      await tester.pump(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 25));
      expect(controller.snapshot.pieces, hasLength(1));
      expect(controller.snapshot.elapsedSeconds, greaterThan(0.0));
      controller.dispose();
    });

    test('sanitizes NaN animProgress and elapsedSeconds in Placeholder3DBoardRenderer without dropping upper mesh', () async {
      final provider = ProceduralPieceAssetProvider();
      final renderer = Placeholder3DBoardRenderer(assetProvider: provider);
      final camera = SpringOrbitCamera3D();
      const mapper = BoardCoordinateMapper();
      final tiles = mapper.buildDefaultTiles();
      addTearDown(() {
        renderer.dispose();
        provider.dispose();
      });

      Future<int> renderClipPixels(
        PieceAnimClip clip,
        double animProgress,
        double elapsedSeconds,
      ) async {
        final snapshot = RenderBoardSnapshot(
          tiles: tiles,
          elapsedSeconds: elapsedSeconds,
          pieces: <RenderPieceNode>[
            RenderPieceNode(
              pieceId: 'nan_test',
              visualKey: const PieceVisualKey(
                type: PieceType.tank,
                side: PlayerSide.red,
                faction: FactionId.usa,
              ),
              worldPosition: mapper.coordToWorld(BoardCoord.fromAlgebraic('f6')),
              yawRadians: math.pi,
              animClip: clip,
              animProgress: animProgress,
              movePitchRadians: double.nan,
              moveRollRadians: double.nan,
              phaseSeed: double.nan,
            ),
          ],
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        renderer.render(canvas, const ui.Size(128, 128), snapshot, camera);
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        picture.dispose();
        image.dispose();
        var nonZero = 0;
        final data = bytes!;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if (data.getUint32(i) != 0) nonZero++;
        }
        return nonZero;
      }

      for (final clip in PieceAnimClip.values) {
        final validCount = await renderClipPixels(clip, 0.0, 0.0);
        final nanCount = await renderClipPixels(clip, double.nan, double.nan);
        expect(
          nanCount,
          equals(validCount),
          reason: 'NaN sanitization for $clip must match progress=0.0 render',
        );
      }
    });

    test('edge topology filters coplanar cylinder cap spokes while keeping hard creases', () {
      final mesh = FactionUnitMeshBuilder.build(
        FactionId.india,
        PieceType.commander,
      );
      final edges = Placeholder3DBoardRenderer.debugExtractEdges(mesh);
      expect(edges, isNotEmpty);
      expect(edges.any((e) => e.isCrease), isTrue);
      expect(edges.any((e) => !e.isCrease), isTrue);
    });

    test('renders all 11 factions, mirror matches, carried passengers, stack fallback & all 7 PieceAnimClips via batched drawVertices', () {
      final provider = ProceduralPieceAssetProvider();
      final renderer = Placeholder3DBoardRenderer(assetProvider: provider);
      final camera = SpringOrbitCamera3D();
      const mapper = BoardCoordinateMapper();
      final tiles = mapper.buildDefaultTiles();
      addTearDown(() {
        renderer.dispose();
        provider.dispose();
      });

      final pieces = <RenderPieceNode>[];
      var idx = 0;
      for (final faction in FactionId.values) {
        final file = idx % BoardCoord.fileCount;
        final rank = idx ~/ BoardCoord.fileCount;
        final type = PieceType.values[idx % PieceType.values.length];
        final clip = PieceAnimClip.values[idx % PieceAnimClip.values.length];
        final side = idx.isEven ? PlayerSide.red : PlayerSide.blue;
        final carried = switch (type.carrierCapacity) {
          2 => const <PieceVisualKey>[
            PieceVisualKey(type: PieceType.infantry, side: PlayerSide.red, isHero: true),
            PieceVisualKey(type: PieceType.militia, side: PlayerSide.red),
          ],
          1 => const <PieceVisualKey>[
            PieceVisualKey(type: PieceType.commander, side: PlayerSide.blue),
          ],
          _ => const <PieceVisualKey>[],
        };

        pieces.add(
          RenderPieceNode(
            pieceId: 'p_$idx',
            visualKey: PieceVisualKey(
              type: type,
              side: side,
              isHero: idx % 3 == 0,
              faction: faction,
            ),
            worldPosition: mapper.coordToWorld(BoardCoord(file: file, rank: rank)),
            yawRadians: side == PlayerSide.red ? math.pi : 0.0,
            stackCount: 1 + carried.length + (idx == 0 ? 1 : 0),
            carriedVisualKeys: carried,
            isSelected: idx == 1,
            animClip: clip,
            animProgress: 0.45,
            phaseSeed: idx * 0.25,
            movePitchRadians: 0.1,
            moveRollRadians: -0.1,
          ),
        );
        idx++;
      }

      // Mirror-match pair + explicit all-7 clips smoke.
      pieces.add(
        RenderPieceNode(
          pieceId: 'mirror_red',
          visualKey: const PieceVisualKey(
            type: PieceType.navy,
            side: PlayerSide.red,
            faction: FactionId.usa,
          ),
          worldPosition: mapper.coordToWorld(BoardCoord.fromAlgebraic('a2')),
          yawRadians: math.pi,
          stackCount: 3,
          carriedVisualKeys: const <PieceVisualKey>[
            PieceVisualKey(type: PieceType.infantry, side: PlayerSide.red),
            PieceVisualKey(type: PieceType.engineer, side: PlayerSide.red),
          ],
          animClip: PieceAnimClip.attack,
          animProgress: 0.5,
        ),
      );
      pieces.add(
        RenderPieceNode(
          pieceId: 'mirror_blue',
          visualKey: const PieceVisualKey(
            type: PieceType.navy,
            side: PlayerSide.blue,
            faction: FactionId.usa,
          ),
          worldPosition: mapper.coordToWorld(BoardCoord.fromAlgebraic('a10')),
          yawRadians: 0.0,
          animClip: PieceAnimClip.defeat,
          animProgress: 0.4,
        ),
      );

      final snapshot = RenderBoardSnapshot(
        tiles: tiles,
        pieces: pieces,
        selectedCoord: BoardCoord.fromAlgebraic('b1'),
        elapsedSeconds: 2.5,
      );

      for (final viewport in const <ui.Size>[
        ui.Size(320, 568),
        ui.Size(1280, 800),
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        renderer.render(canvas, viewport, snapshot, camera);
        final picture = recorder.endRecording();
        picture.dispose();
        expect(renderer.debugLastDrawVerticesCallCount, greaterThanOrEqualTo(1));
      }

      // Hit-test ground plane invariants remain exact.
      expect(
        renderer.hitTestBoardCoord(
          localPosition: const ui.Offset(640, 400),
          viewportSize: const ui.Size(1280, 800),
          camera: camera,
          files: BoardCoord.fileCount,
          ranks: BoardCoord.rankCount,
        ),
        isNotNull,
      );
    });

    test('preserves opaque background alpha across consecutive frames after hero and grid renders', () async {
      final provider = ProceduralPieceAssetProvider();
      final renderer = Placeholder3DBoardRenderer(assetProvider: provider);
      final camera = SpringOrbitCamera3D();
      const mapper = BoardCoordinateMapper();
      final tiles = mapper.buildDefaultTiles();
      addTearDown(() {
        renderer.dispose();
        provider.dispose();
      });

      final snapshot = RenderBoardSnapshot(
        tiles: tiles,
        elapsedSeconds: 1.0,
        selectedCoord: BoardCoord.fromAlgebraic('f6'),
        pieces: <RenderPieceNode>[
          RenderPieceNode(
            pieceId: 'hero_frame_alpha',
            visualKey: const PieceVisualKey(
              type: PieceType.commander,
              side: PlayerSide.red,
              isHero: true,
              faction: FactionId.vietnam,
            ),
            worldPosition: mapper.coordToWorld(BoardCoord.fromAlgebraic('f6')),
            yawRadians: math.pi,
          ),
        ],
      );

      Future<Uint8List> renderRgba() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        renderer.render(canvas, const ui.Size(160, 160), snapshot, camera);
        final picture = recorder.endRecording();
        final image = await picture.toImage(160, 160);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        picture.dispose();
        image.dispose();
        return byteData!.buffer.asUint8List();
      }

      final frame1 = await renderRgba();
      final frame2 = await renderRgba();

      // Top-left pixel (0, 0) must remain fully opaque gradient sky (alpha 255).
      expect(frame1[3], equals(255));
      expect(frame2[3], equals(255));

      var diffPixels = 0;
      for (var i = 0; i < frame1.length; i += 4) {
        if (frame1[i] != frame2[i] ||
            frame1[i + 1] != frame2[i + 1] ||
            frame1[i + 2] != frame2[i + 2] ||
            frame1[i + 3] != frame2[i + 3]) {
          diffPixels++;
        }
      }
      expect(diffPixels, equals(0));
    });

    test('sanitizes non-finite elapsedSeconds on hero pieces and selection/hint rings', () async {
      final provider = ProceduralPieceAssetProvider();
      final renderer = Placeholder3DBoardRenderer(assetProvider: provider);
      final camera = SpringOrbitCamera3D();
      const mapper = BoardCoordinateMapper();
      final tiles = mapper.buildDefaultTiles();
      addTearDown(() {
        renderer.dispose();
        provider.dispose();
      });

      final hints = <LegalActionHint>[
        LegalActionHint(
          targetCoord: BoardCoord.fromAlgebraic('f7'),
          kind: ActionKind.move,
        ),
        LegalActionHint(
          targetCoord: BoardCoord.fromAlgebraic('g6'),
          kind: ActionKind.capture,
        ),
      ];

      Future<Uint8List> renderHero(PieceType type, double elapsedSeconds) async {
        final snapshot = RenderBoardSnapshot(
          tiles: tiles,
          elapsedSeconds: elapsedSeconds,
          selectedCoord: BoardCoord.fromAlgebraic('f6'),
          legalHints: hints,
          pieces: <RenderPieceNode>[
            RenderPieceNode(
              pieceId: 'hero_${type.name}',
              visualKey: PieceVisualKey(
                type: type,
                side: PlayerSide.red,
                isHero: true,
                faction: FactionId.usa,
              ),
              worldPosition: mapper.coordToWorld(BoardCoord.fromAlgebraic('f6')),
              yawRadians: math.pi,
            ),
          ],
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        renderer.render(canvas, const ui.Size(160, 160), snapshot, camera);
        final picture = recorder.endRecording();
        final image = await picture.toImage(160, 160);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        picture.dispose();
        image.dispose();
        return byteData!.buffer.asUint8List();
      }

      const heroTypes = <PieceType>[
        PieceType.commander,
        PieceType.infantry,
        PieceType.militia,
        PieceType.airForce,
      ];

      for (final type in heroTypes) {
        final baseline = await renderHero(type, 0.0);
        final nanBytes = await renderHero(type, double.nan);
        final infBytes = await renderHero(type, double.infinity);

        var diffNan = 0;
        var diffInf = 0;
        for (var i = 0; i < baseline.length; i += 4) {
          if (baseline[i] != nanBytes[i] ||
              baseline[i + 1] != nanBytes[i + 1] ||
              baseline[i + 2] != nanBytes[i + 2] ||
              baseline[i + 3] != nanBytes[i + 3]) {
            diffNan++;
          }
          if (baseline[i] != infBytes[i] ||
              baseline[i + 1] != infBytes[i + 1] ||
              baseline[i + 2] != infBytes[i + 2] ||
              baseline[i + 3] != infBytes[i + 3]) {
            diffInf++;
          }
        }
        expect(diffNan, equals(0), reason: 'Hero $type NaN mismatch');
        expect(diffInf, equals(0), reason: 'Hero $type Infinity mismatch');
      }
    });
  });
}
