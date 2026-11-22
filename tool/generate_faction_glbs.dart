import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commander_chess_3d/features/game/engine/assets/faction_mesh_builder.dart';
import 'package:commander_chess_3d/features/game/engine/assets/glb_binary_reader.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';

void main() {
  final outDir = Directory('assets/models/pieces');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final manifestFile = File('assets/models/asset_manifest.json');
  Map<String, dynamic>? manifestFactionMeshes;
  if (manifestFile.existsSync()) {
    final decoded = jsonDecode(manifestFile.readAsStringSync());
    if (decoded is Map<String, dynamic> && decoded['factionMeshes'] is Map) {
      manifestFactionMeshes = Map<String, dynamic>.from(
        decoded['factionMeshes'] as Map,
      );
    }
  }

  var generatedCount = 0;
  var minTris = 1 << 30;
  var maxTris = 0;
  final violations = <String>[];

  for (final type in PieceType.values) {
    final seenHashes = <int, String>{};
    for (final faction in FactionId.values) {
      final mesh = FactionUnitMeshBuilder.build(faction, type);
      final tris = mesh.triangleCount;
      if (tris < minTris) minTris = tris;
      if (tris > maxTris) maxTris = tris;

      if (tris < 250 || tris > 500) {
        violations.add('TRIS ${faction.code}.${type.snakeCaseName}: $tris');
      }

      // Compute geometry hash over vertices and indices to prove 11 distinct silhouettes.
      var geomHash = 0xcbf29ce484222325;
      for (var i = 0; i < mesh.vertices.length; i++) {
        final bits = mesh.vertices.buffer.asByteData().getUint32(i * 4, Endian.little);
        geomHash ^= bits;
        geomHash = (geomHash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      }
      for (var i = 0; i < mesh.faceIndices.length; i++) {
        geomHash ^= mesh.faceIndices[i];
        geomHash = (geomHash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      }
      final prev = seenHashes[geomHash];
      if (prev != null) {
        violations.add('DUP ${type.snakeCaseName}: ${faction.code} == $prev');
      } else {
        seenHashes[geomHash] = faction.code;
      }

      final glbBytes = FactionGlbEncoder.encode(
        faction: faction,
        type: type,
        mesh: mesh,
      );
      final parsed = GlbBinaryReader.parse(glbBytes);
      if (parsed.minBounds.x < -0.4251 ||
          parsed.maxBounds.x > 0.4251 ||
          parsed.minBounds.y < -0.0001 ||
          parsed.maxBounds.y > 1.2001 ||
          parsed.minBounds.z < -0.4251 ||
          parsed.maxBounds.z > 0.4251) {
        throw StateError(
          'Bounds violation for ${faction.code}.${type.snakeCaseName}: '
          'min=${parsed.minBounds} max=${parsed.maxBounds}',
        );
      }

      var targetPath =
          'assets/models/pieces/${faction.code}_${type.snakeCaseName}_lod0.glb';
      if (manifestFactionMeshes != null) {
        final inner = manifestFactionMeshes[faction.code];
        if (inner is Map && inner[type.snakeCaseName] is String) {
          targetPath = inner[type.snakeCaseName] as String;
        }
      }

      File(targetPath).writeAsBytesSync(glbBytes, flush: true);
      generatedCount++;
    }
  }

  if (violations.isNotEmpty) {
    throw StateError(
      'Triangle budget violations (${violations.length}):\n${violations.join('\n')}',
    );
  }

  stdout.writeln(
    'Generated $generatedCount faction .glb files cleanly '
    '(triangles per piece: min=$minTris, max=$maxTris).',
  );
}
