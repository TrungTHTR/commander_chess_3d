import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../../models/faction_model.dart';
import '../../models/piece_model.dart';
import 'faction_mesh_builder.dart';

/// Parsed metadata and validated geometry summary for a Khronos glTF 2.0 `.glb`.
final class GlbParsedAsset {
  const GlbParsedAsset({
    required this.version,
    required this.totalLength,
    required this.nodeNames,
    required this.materialNames,
    required this.vertexCount,
    required this.triangleCount,
    required this.minBounds,
    required this.maxBounds,
    required this.jsonRoot,
    this.renderMesh,
  });

  final int version;
  final int totalLength;
  final List<String> nodeNames;
  final List<String> materialNames;
  final int vertexCount;
  final int triangleCount;
  final Vector3 minBounds;
  final Vector3 maxBounds;
  final Map<String, dynamic> jsonRoot;
  final ProceduralMeshPrimitive? renderMesh;
}

/// Pure-Dart Khronos glTF 2.0 binary (`.glb`) parser and validator.
///
/// Zero `dart:ui`, `dart:io`, or `package:flutter/*` dependencies so it works
/// identically on Flutter Web, Desktop, Mobile, and standalone Dart CLI tools.
abstract final class GlbBinaryReader {
  static const int glbMagic = 0x46546C67; // "glTF"
  static const int glbVersion = 2;
  static const int chunkTypeJson = 0x4E4F534A; // "JSON"
  static const int chunkTypeBin = 0x004E4942; // "BIN\0"
  static const int componentTypeFloat = 5126;
  static const int componentTypeUnsignedShort = 5123;
  static const String _teamRingMaterialName = 'mat_team_ring';

  static int _readOptionalInt(
    Map<dynamic, dynamic> map,
    String key,
    int defaultValue,
    String fieldName,
  ) {
    final raw = map[key];
    if (raw == null) return defaultValue;
    if (raw is int) return raw;
    throw FormatException('Invalid integer field "$fieldName": $raw.');
  }

  static List<double> _readVec3(Object? raw, String fieldName) {
    if (raw is! List || raw.length != 3) {
      throw FormatException('Invalid vec3 field "$fieldName": $raw.');
    }
    final result = <double>[];
    for (var i = 0; i < 3; i++) {
      final value = raw[i];
      if (value is! num) {
        throw FormatException('Non-numeric element in "$fieldName"[$i]: $value.');
      }
      final d = value.toDouble();
      if (!d.isFinite) {
        throw FormatException('Non-finite element in "$fieldName"[$i]: $value.');
      }
      result.add(d);
    }
    return result;
  }

  static GlbParsedAsset parseByteData(
    ByteData data, {
    bool includeRenderMesh = false,
  }) {
    return parse(
      Uint8List.sublistView(
        data.buffer.asUint8List(),
        data.offsetInBytes,
        data.offsetInBytes + data.lengthInBytes,
      ),
      includeRenderMesh: includeRenderMesh,
    );
  }

  static GlbParsedAsset parse(Uint8List bytes, {bool includeRenderMesh = false}) {
    if (bytes.length < 20 || bytes.length % 4 != 0) {
      throw FormatException('Invalid GLB byte length: ${bytes.length}.');
    }

    final view = ByteData.sublistView(bytes);
    final magic = view.getUint32(0, Endian.little);
    if (magic != glbMagic) {
      throw FormatException('Invalid GLB magic: 0x${magic.toRadixString(16)}.');
    }

    final version = view.getUint32(4, Endian.little);
    if (version != glbVersion) {
      throw FormatException('Unsupported glTF version: $version.');
    }

    final declaredLength = view.getUint32(8, Endian.little);
    if (declaredLength != bytes.length) {
      throw FormatException(
        'GLB length mismatch: declared=$declaredLength actual=${bytes.length}.',
      );
    }

    final jsonChunkLen = view.getUint32(12, Endian.little);
    final jsonChunkType = view.getUint32(16, Endian.little);
    if (jsonChunkType != chunkTypeJson) {
      throw FormatException(
        'Expected JSON chunk (0x4E4F534A), got 0x${jsonChunkType.toRadixString(16)}.',
      );
    }
    if (jsonChunkLen <= 0 ||
        jsonChunkLen % 4 != 0 ||
        20 + jsonChunkLen > bytes.length) {
      throw FormatException('Invalid JSON chunk length: $jsonChunkLen.');
    }

    final Object? decoded;
    try {
      final jsonText = utf8.decode(Uint8List.sublistView(bytes, 20, 20 + jsonChunkLen));
      decoded = jsonDecode(jsonText);
    } on Object catch (err) {
      throw FormatException('Failed to decode GLB JSON chunk: $err');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('GLB JSON root must be an object.');
    }

    final asset = decoded['asset'];
    if (asset is! Map || asset['version'] != '2.0') {
      throw const FormatException('glTF asset.version must be "2.0".');
    }

    final binOffset = 20 + jsonChunkLen;
    if (binOffset + 8 > bytes.length) {
      throw const FormatException('Missing BIN chunk header.');
    }
    final binChunkLen = view.getUint32(binOffset, Endian.little);
    final binChunkType = view.getUint32(binOffset + 4, Endian.little);
    if (binChunkType != chunkTypeBin) {
      throw FormatException(
        'Expected BIN chunk (0x004E4942), got 0x${binChunkType.toRadixString(16)}.',
      );
    }
    if (binChunkLen <= 0 ||
        binChunkLen % 4 != 0 ||
        binOffset + 8 + binChunkLen != bytes.length) {
      throw FormatException('Invalid BIN chunk length: $binChunkLen.');
    }

    final binBytes = Uint8List.sublistView(
      bytes,
      binOffset + 8,
      binOffset + 8 + binChunkLen,
    );
    final binView = ByteData.sublistView(binBytes);

    final buffers = decoded['buffers'];
    final bufferViews = decoded['bufferViews'];
    final accessors = decoded['accessors'];
    final meshes = decoded['meshes'];
    final nodes = decoded['nodes'];
    final materials = decoded['materials'];

    if (buffers is! List ||
        buffers.isEmpty ||
        bufferViews is! List ||
        bufferViews.isEmpty ||
        accessors is! List ||
        accessors.isEmpty ||
        meshes is! List ||
        meshes.isEmpty ||
        nodes is! List ||
        nodes.isEmpty ||
        materials is! List ||
        materials.isEmpty) {
      throw const FormatException(
        'glTF JSON missing required non-empty arrays (buffers/bufferViews/accessors/meshes/nodes/materials).',
      );
    }

    final buf0 = buffers.first;
    if (buf0 is! Map || buf0['byteLength'] is! int) {
      throw const FormatException('Invalid glTF buffer[0].byteLength.');
    }
    final buf0ByteLength = buf0['byteLength'] as int;
    if (buf0ByteLength <= 0 || buf0ByteLength > binBytes.length) {
      throw FormatException(
        'glTF buffer[0].byteLength ($buf0ByteLength) out of BIN bounds (${binBytes.length}).',
      );
    }

    for (final bv in bufferViews) {
      if (bv is! Map || bv['byteLength'] is! int) {
        throw const FormatException('Invalid bufferView entry.');
      }
      final offset = _readOptionalInt(bv, 'byteOffset', 0, 'bufferView.byteOffset');
      final length = bv['byteLength'] as int;
      final bufferIdx = _readOptionalInt(bv, 'buffer', 0, 'bufferView.buffer');
      final stride = _readOptionalInt(bv, 'byteStride', 0, 'bufferView.byteStride');
      if (bv['byteStride'] != null && (stride <= 0 || stride % 4 != 0)) {
        throw FormatException('Invalid bufferView.byteStride: $stride.');
      }
      if (bufferIdx != 0 ||
          length <= 0 ||
          length > buf0ByteLength ||
          offset < 0 ||
          offset % 4 != 0 ||
          offset > buf0ByteLength - length) {
        throw FormatException(
          'Invalid bufferView bounds: buffer=$bufferIdx offset=$offset length=$length.',
        );
      }
    }

    final nodeNames = <String>[];
    final meshTransformScale = <int, List<double>>{};
    final meshTransformTranslate = <int, List<double>>{};
    final pedestalMeshes = <int>{};
    final sockets = <int, Vector3>{};
    for (final node in nodes) {
      if (node is! Map) {
        throw const FormatException('Invalid glTF node entry.');
      }
      final name = node['name'];
      if (name != null && name is! String) {
        throw FormatException('Invalid glTF node.name: $name.');
      }
      if (name is String && name.isNotEmpty) {
        nodeNames.add(name);
      }
      final meshIdx = node['mesh'];
      if (meshIdx != null && meshIdx is! int) {
        throw FormatException('Invalid glTF node.mesh: $meshIdx.');
      }
      final scale = node['scale'];
      List<double>? parsedScale;
      if (scale != null) {
        parsedScale = _readVec3(scale, 'node.scale');
      }
      final trans = node['translation'];
      List<double>? parsedTrans;
      if (trans != null) {
        parsedTrans = _readVec3(trans, 'node.translation');
      }
      if (meshIdx is int) {
        if (meshIdx < 0 || meshIdx >= meshes.length) {
          throw FormatException('Node references invalid mesh index $meshIdx.');
        }
        if (parsedScale != null) {
          meshTransformScale[meshIdx] = parsedScale;
        }
        if (parsedTrans != null) {
          meshTransformTranslate[meshIdx] = parsedTrans;
        }
        if (name == MeshPartTag.basePedestal.nodeName) {
          pedestalMeshes.add(meshIdx);
        }
      }
      if (includeRenderMesh &&
          name is String &&
          name.startsWith('socket_passenger_')) {
        final index = int.tryParse(name.substring('socket_passenger_'.length));
        if (index != null) {
          sockets[index] = parsedTrans == null
              ? Vector3.zero()
              : Vector3(parsedTrans[0], parsedTrans[1], parsedTrans[2]);
        }
      }
    }

    final materialNames = <String>[];
    for (final mat in materials) {
      if (mat is! Map) {
        throw const FormatException('Invalid material entry.');
      }
      final name = mat['name'];
      if (name != null && name is! String) {
        throw FormatException('Invalid material.name: $name.');
      }
      materialNames.add(name is String ? name : '');
    }

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var minZ = double.infinity;
    var maxZ = double.negativeInfinity;
    var totalVertices = 0;
    var totalTriangles = 0;
    final vertices = <double>[];
    final indices = <int>[];
    final normals = <double>[];
    final faceSlots = <int>[];
    final partTags = <int>[];
    if (includeRenderMesh &&
        materials.length + ProceduralMaterialSlot.values.length > 256) {
      throw const FormatException('Too many materials for the board renderer.');
    }

    for (var mIdx = 0; mIdx < meshes.length; mIdx++) {
      final mesh = meshes[mIdx];
      if (mesh is! Map || mesh['primitives'] is! List) {
        throw const FormatException('Invalid mesh entry in glTF JSON.');
      }
      final prims = mesh['primitives'] as List;
      if (prims.isEmpty) {
        throw const FormatException('Mesh contains zero primitives.');
      }
      final scale = meshTransformScale[mIdx] ?? const <double>[1.0, 1.0, 1.0];
      final trans =
          meshTransformTranslate[mIdx] ?? const <double>[0.0, 0.0, 0.0];
      final part = pedestalMeshes.contains(mIdx)
          ? MeshPartTag.basePedestal
          : MeshPartTag.bodyHull;

      for (final prim in prims) {
        if (prim is! Map || prim['attributes'] is! Map) {
          throw const FormatException('Invalid mesh primitive.');
        }
        final mode = _readOptionalInt(prim, 'mode', 4, 'primitive.mode');
        if (mode != 4) {
          throw FormatException('Unsupported primitive mode: $mode (expected TRIANGLES=4).');
        }
        final matIdx = prim['material'];
        if (matIdx != null &&
            (matIdx is! int || matIdx < 0 || matIdx >= materials.length)) {
          throw FormatException('Invalid primitive material index: $matIdx.');
        }

        final attrs = prim['attributes'] as Map;
        final materialIndex = matIdx as int? ?? 0;
        final slot = materialNames[materialIndex] == _teamRingMaterialName
            ? ProceduralMaterialSlot.teamRing.index
            : ProceduralMaterialSlot.values.length + materialIndex;
        final posAccessorIdx = attrs['POSITION'];
        if (posAccessorIdx is! int ||
            posAccessorIdx < 0 ||
            posAccessorIdx >= accessors.length) {
          throw const FormatException('Primitive missing valid POSITION accessor.');
        }
        final posAcc = accessors[posAccessorIdx];
        if (posAcc is! Map ||
            posAcc['componentType'] != componentTypeFloat ||
            posAcc['type'] != 'VEC3') {
          throw const FormatException('POSITION accessor must be FLOAT (5126) VEC3.');
        }
        final posCount = posAcc['count'];
        final posBvIdx = posAcc['bufferView'];
        if (posCount is! int ||
            posCount <= 0 ||
            posBvIdx is! int ||
            posBvIdx < 0 ||
            posBvIdx >= bufferViews.length) {
          throw const FormatException('Invalid POSITION accessor count/bufferView.');
        }
        final posBv = bufferViews[posBvIdx] as Map;
        final posBvOffset = _readOptionalInt(
          posBv,
          'byteOffset',
          0,
          'bufferView.byteOffset',
        );
        final posBvLen = posBv['byteLength'] as int;
        final posAccOffset = _readOptionalInt(
          posAcc,
          'byteOffset',
          0,
          'accessor.byteOffset',
        );
        final posStride = _readOptionalInt(
          posBv,
          'byteStride',
          12,
          'bufferView.byteStride',
        );
        if (posAccOffset < 0 ||
            posAccOffset % 4 != 0 ||
            posAccOffset > posBvLen ||
            posStride < 12 ||
            posStride > posBvLen - posAccOffset ||
            posCount > (posBvLen - posAccOffset) ~/ posStride) {
          throw const FormatException('POSITION accessor out of bufferView bounds.');
        }

        final vertexOffset = totalVertices;
        for (var i = 0; i < posCount; i++) {
          final base = posBvOffset + posAccOffset + i * posStride;
          final rx = binView.getFloat32(base, Endian.little);
          final ry = binView.getFloat32(base + 4, Endian.little);
          final rz = binView.getFloat32(base + 8, Endian.little);
          final x = rx * scale[0] + trans[0];
          final y = ry * scale[1] + trans[1];
          final z = rz * scale[2] + trans[2];
          if (!x.isFinite || !y.isFinite || !z.isFinite) {
            throw const FormatException('Non-finite POSITION coordinate.');
          }
          if (includeRenderMesh) {
            vertices
              ..add(x)
              ..add(y)
              ..add(z);
          }
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          if (z < minZ) minZ = z;
          if (z > maxZ) maxZ = z;
        }
        totalVertices += posCount;

        // Validate NORMAL accessor.
        final normAccessorIdx = attrs['NORMAL'];
        if (normAccessorIdx is! int ||
            normAccessorIdx < 0 ||
            normAccessorIdx >= accessors.length) {
          throw const FormatException('Primitive missing valid NORMAL accessor.');
        }
        final normAcc = accessors[normAccessorIdx];
        if (normAcc is! Map ||
            normAcc['componentType'] != componentTypeFloat ||
            normAcc['type'] != 'VEC3' ||
            normAcc['count'] != posCount) {
          throw const FormatException('NORMAL accessor must match POSITION count as FLOAT VEC3.');
        }
        final normBvIdx = normAcc['bufferView'];
        if (normBvIdx is! int ||
            normBvIdx < 0 ||
            normBvIdx >= bufferViews.length) {
          throw const FormatException('Invalid NORMAL accessor bufferView.');
        }
        final normBv = bufferViews[normBvIdx] as Map;
        final normBvOffset = _readOptionalInt(
          normBv,
          'byteOffset',
          0,
          'bufferView.byteOffset',
        );
        final normBvLen = normBv['byteLength'] as int;
        final normAccOffset = _readOptionalInt(
          normAcc,
          'byteOffset',
          0,
          'accessor.byteOffset',
        );
        final normStride = _readOptionalInt(
          normBv,
          'byteStride',
          12,
          'bufferView.byteStride',
        );
        if (normAccOffset < 0 ||
            normAccOffset % 4 != 0 ||
            normAccOffset > normBvLen ||
            normStride < 12 ||
            normStride > normBvLen - normAccOffset ||
            posCount > (normBvLen - normAccOffset) ~/ normStride) {
          throw const FormatException('NORMAL accessor out of bufferView bounds.');
        }
        for (var i = 0; i < posCount; i++) {
          final base = normBvOffset + normAccOffset + i * normStride;
          final nx = binView.getFloat32(base, Endian.little);
          final ny = binView.getFloat32(base + 4, Endian.little);
          final nz = binView.getFloat32(base + 8, Endian.little);
          if (!nx.isFinite || !ny.isFinite || !nz.isFinite) {
            throw const FormatException('Non-finite NORMAL vector.');
          }
        }

        // Validate indices accessor (UNSIGNED_SHORT 5123 SCALAR).
        final indicesIdx = prim['indices'];
        if (indicesIdx is! int ||
            indicesIdx < 0 ||
            indicesIdx >= accessors.length) {
          throw const FormatException('Primitive missing valid indices accessor.');
        }
        final idxAcc = accessors[indicesIdx];
        if (idxAcc is! Map ||
            idxAcc['componentType'] != componentTypeUnsignedShort ||
            idxAcc['type'] != 'SCALAR') {
          throw const FormatException(
            'indices accessor must be UNSIGNED_SHORT (5123) SCALAR.',
          );
        }
        final idxCount = idxAcc['count'];
        final idxBvIdx = idxAcc['bufferView'];
        if (idxCount is! int ||
            idxCount <= 0 ||
            idxCount % 3 != 0 ||
            idxBvIdx is! int ||
            idxBvIdx < 0 ||
            idxBvIdx >= bufferViews.length) {
          throw const FormatException('Invalid indices accessor count/bufferView.');
        }
        final idxBv = bufferViews[idxBvIdx] as Map;
        final idxBvOffset = _readOptionalInt(
          idxBv,
          'byteOffset',
          0,
          'bufferView.byteOffset',
        );
        final idxBvLen = idxBv['byteLength'] as int;
        final idxAccOffset = _readOptionalInt(
          idxAcc,
          'byteOffset',
          0,
          'accessor.byteOffset',
        );
        if (idxAccOffset < 0 ||
            idxAccOffset % 2 != 0 ||
            idxAccOffset > idxBvLen ||
            idxCount > (idxBvLen - idxAccOffset) ~/ 2) {
          throw const FormatException('indices accessor out of bufferView bounds.');
        }
        final firstFace = indices.length;
        for (var k = 0; k < idxCount; k++) {
          final idxVal = binView.getUint16(
            idxBvOffset + idxAccOffset + k * 2,
            Endian.little,
          );
          if (idxVal >= posCount) {
            throw FormatException(
              'Vertex index $idxVal out of range [0, $posCount).',
            );
          }
          if (includeRenderMesh) {
            final index = vertexOffset + idxVal;
            indices.add(index);
            // A triangle repeats its last vertex in the canvas mesh format.
            if (k % 3 == 2) indices.add(index);
          }
        }
        for (var face = firstFace; face < indices.length; face += 4) {
          final a = indices[face] * 3;
          final b = indices[face + 1] * 3;
          final c = indices[face + 2] * 3;
          final ab = Vector3(
            vertices[b] - vertices[a],
            vertices[b + 1] - vertices[a + 1],
            vertices[b + 2] - vertices[a + 2],
          );
          final ac = Vector3(
            vertices[c] - vertices[a],
            vertices[c + 1] - vertices[a + 1],
            vertices[c + 2] - vertices[a + 2],
          );
          final normal = ab.cross(ac)..normalize();
          normals.addAll(normal.storage);
          faceSlots.add(slot);
          partTags.add(part.index);
        }
        totalTriangles += idxCount ~/ 3;
      }
    }

    if (totalVertices <= 0 || totalTriangles <= 0) {
      throw const FormatException('GLB contains no valid triangles.');
    }

    return GlbParsedAsset(
      version: version,
      totalLength: bytes.length,
      nodeNames: List<String>.unmodifiable(nodeNames),
      materialNames: List<String>.unmodifiable(materialNames),
      vertexCount: totalVertices,
      triangleCount: totalTriangles,
      minBounds: Vector3(minX, minY, minZ),
      maxBounds: Vector3(maxX, maxY, maxZ),
      jsonRoot: Map<String, dynamic>.unmodifiable(decoded),
      renderMesh: includeRenderMesh
          ? ProceduralMeshPrimitive(
              vertices: Float32List.fromList(vertices),
              faceIndices: Int32List.fromList(indices),
              faceNormals: Float32List.fromList(normals),
              faceSlots: Uint8List.fromList(faceSlots),
              facePartTags: Uint8List.fromList(partTags),
              passengerSockets: [
                for (final index in sockets.keys.toList()..sort()) sockets[index]!,
              ],
            )
          : null,
    );
  }
}

/// Pure-Dart Khronos glTF 2.0 binary (`.glb`) encoder for
/// [ProceduralMeshPrimitive] models.
abstract final class FactionGlbEncoder {
  static Uint8List encode({
    required FactionId faction,
    required PieceType type,
    required ProceduralMeshPrimitive mesh,
  }) {
    final palette = FactionCatalog.of(faction).palette;
    final profile = FactionCatalog.unitOf(faction, type);

    // 6 canonical PBR materials matching BLENDER_ASSET_CONTRACT + teamRing.
    final materials = <Map<String, dynamic>>[
      _pbrMaterial('mat_faction_primary', palette.primaryHex, metallic: 0.30, roughness: 0.45),
      _pbrMaterial('mat_faction_accent', palette.accentHex, metallic: 0.65, roughness: 0.30),
      _pbrMaterial('mat_base_pedestal', 0xFF455A64, metallic: 0.40, roughness: 0.50),
      _pbrMaterial('mat_neutral_metal', palette.neutralMetalHex, metallic: 0.85, roughness: 0.35),
      _pbrMaterial('mat_heroic_emissive', palette.emblemHex, metallic: 0.50, roughness: 0.25, emissive: const [0.0, 0.0, 0.0]),
      _pbrMaterial('mat_team_ring', 0xFF78909C, metallic: 0.35, roughness: 0.40),
    ];

    int mapSlotToMaterial(int slotIdx) {
      if (slotIdx == ProceduralMaterialSlot.factionUniform.index) {
        return ProceduralMaterialSlot.factionPrimary.index;
      }
      if (slotIdx == ProceduralMaterialSlot.factionEmblem.index) {
        return ProceduralMaterialSlot.factionAccent.index;
      }
      if (slotIdx >= 0 && slotIdx < materials.length) {
        return slotIdx;
      }
      return 0;
    }

    // Group faces by MeshPartTag -> materialIndex.
    final partFaces = <MeshPartTag, Map<int, List<int>>>{};
    for (var f = 0; f < mesh.faceCount; f++) {
      final part = mesh.partTagForFace(f);
      final matIdx = mapSlotToMaterial(mesh.faceSlots[f]);
      partFaces
          .putIfAbsent(part, () => <int, List<int>>{})
          .putIfAbsent(matIdx, () => <int>[])
          .add(f);
    }

    final binBuilder = BytesBuilder(copy: false);
    final bufferViews = <Map<String, dynamic>>[];
    final accessors = <Map<String, dynamic>>[];
    final gltfMeshes = <Map<String, dynamic>>[];
    final nodes = <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'piece_${type.snakeCaseName}',
        'children': <int>[],
        'extras': <String, dynamic>{
          'faction': faction.code,
          'unitDesignation': profile.unitDesignation,
        },
      },
    ];
    final rootChildren = nodes[0]['children'] as List<int>;

    void padBinTo4() {
      final rem = binBuilder.length % 4;
      if (rem != 0) {
        for (var i = 0; i < 4 - rem; i++) {
          binBuilder.addByte(0);
        }
      }
    }

    final partNodeIndices = <MeshPartTag, int>{};

    // Emit canonical part mesh nodes in stable order.
    for (final part in MeshPartTag.values) {
      final byMat = partFaces[part];
      if (byMat == null || byMat.isEmpty) continue;

      final primitives = <Map<String, dynamic>>[];
      final sortedMats = byMat.keys.toList()..sort();

      for (final matIdx in sortedMats) {
        final faceList = byMat[matIdx]!;
        final posList = <double>[];
        final normList = <double>[];
        final idxList = <int>[];

        var minX = double.infinity;
        var minY = double.infinity;
        var minZ = double.infinity;
        var maxX = double.negativeInfinity;
        var maxY = double.negativeInfinity;
        var maxZ = double.negativeInfinity;

        void pushVertex(int vIdx, double nx, double ny, double nz) {
          final x = mesh.vertices[vIdx * 3];
          final y = mesh.vertices[vIdx * 3 + 1];
          final z = mesh.vertices[vIdx * 3 + 2];
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          if (z < minZ) minZ = z;
          if (z > maxZ) maxZ = z;
          posList.add(x);
          posList.add(y);
          posList.add(z);
          normList.add(nx);
          normList.add(ny);
          normList.add(nz);
          idxList.add(idxList.length);
        }

        for (final f in faceList) {
          final base = f * 4;
          final i0 = mesh.faceIndices[base];
          final i1 = mesh.faceIndices[base + 1];
          final i2 = mesh.faceIndices[base + 2];
          final i3 = mesh.faceIndices[base + 3];
          final nx = mesh.faceNormals[f * 3];
          final ny = mesh.faceNormals[f * 3 + 1];
          final nz = mesh.faceNormals[f * 3 + 2];

          pushVertex(i0, nx, ny, nz);
          pushVertex(i1, nx, ny, nz);
          pushVertex(i2, nx, ny, nz);

          if (i3 != i2) {
            pushVertex(i0, nx, ny, nz);
            pushVertex(i2, nx, ny, nz);
            pushVertex(i3, nx, ny, nz);
          }
        }

        final vCount = posList.length ~/ 3;

        // POSITION bufferView + accessor.
        padBinTo4();
        final posOffset = binBuilder.length;
        final posBytes = Float32List.fromList(posList).buffer.asUint8List();
        binBuilder.add(posBytes);
        final posBvIdx = bufferViews.length;
        bufferViews.add(<String, dynamic>{
          'buffer': 0,
          'byteOffset': posOffset,
          'byteLength': posBytes.length,
          'byteStride': 12,
          'target': 34962,
        });
        final posAccIdx = accessors.length;
        accessors.add(<String, dynamic>{
          'bufferView': posBvIdx,
          'byteOffset': 0,
          'componentType': GlbBinaryReader.componentTypeFloat,
          'count': vCount,
          'type': 'VEC3',
          'min': <double>[minX, minY, minZ],
          'max': <double>[maxX, maxY, maxZ],
        });

        // NORMAL bufferView + accessor.
        padBinTo4();
        final normOffset = binBuilder.length;
        final normBytes = Float32List.fromList(normList).buffer.asUint8List();
        binBuilder.add(normBytes);
        final normBvIdx = bufferViews.length;
        bufferViews.add(<String, dynamic>{
          'buffer': 0,
          'byteOffset': normOffset,
          'byteLength': normBytes.length,
          'byteStride': 12,
          'target': 34962,
        });
        final normAccIdx = accessors.length;
        accessors.add(<String, dynamic>{
          'bufferView': normBvIdx,
          'byteOffset': 0,
          'componentType': GlbBinaryReader.componentTypeFloat,
          'count': vCount,
          'type': 'VEC3',
        });

        // indices bufferView + accessor.
        padBinTo4();
        final idxOffset = binBuilder.length;
        final idxBytes = Uint16List.fromList(idxList).buffer.asUint8List();
        binBuilder.add(idxBytes);
        final idxBvIdx = bufferViews.length;
        bufferViews.add(<String, dynamic>{
          'buffer': 0,
          'byteOffset': idxOffset,
          'byteLength': idxBytes.length,
          'target': 34963,
        });
        final idxAccIdx = accessors.length;
        accessors.add(<String, dynamic>{
          'bufferView': idxBvIdx,
          'byteOffset': 0,
          'componentType': GlbBinaryReader.componentTypeUnsignedShort,
          'count': idxList.length,
          'type': 'SCALAR',
          'min': <int>[0],
          'max': <int>[vCount - 1],
        });

        primitives.add(<String, dynamic>{
          'attributes': <String, dynamic>{
            'POSITION': posAccIdx,
            'NORMAL': normAccIdx,
          },
          'indices': idxAccIdx,
          'material': matIdx,
        });
      }

      final meshIdx = gltfMeshes.length;
      gltfMeshes.add(<String, dynamic>{
        'name': '${part.nodeName}_mesh',
        'primitives': primitives,
      });

      final nodeIdx = nodes.length;
      nodes.add(<String, dynamic>{
        'name': part.nodeName,
        'mesh': meshIdx,
      });
      partNodeIndices[part] = nodeIdx;

      if (part == MeshPartTag.barrel && partNodeIndices.containsKey(MeshPartTag.turret)) {
        final turretNode = nodes[partNodeIndices[MeshPartTag.turret]!];
        final children = (turretNode['children'] as List<int>?) ?? <int>[];
        children.add(nodeIdx);
        turretNode['children'] = children;
      } else {
        rootChildren.add(nodeIdx);
      }
    }

    // Emit Empty socket nodes strictly matching PieceType.carrierCapacity.
    final cap = type.carrierCapacity;
    for (var s = 0; s < cap && s < mesh.passengerSockets.length; s++) {
      final sock = mesh.passengerSockets[s];
      final sockNodeIdx = nodes.length;
      nodes.add(<String, dynamic>{
        'name': 'socket_passenger_$s',
        'translation': <double>[sock.x, sock.y, sock.z],
      });
      rootChildren.add(sockNodeIdx);
    }

    padBinTo4();
    final binBytes = binBuilder.takeBytes();

    final gltfJson = <String, dynamic>{
      'asset': <String, dynamic>{
        'version': '2.0',
        'generator': 'commander_chess_3d_faction_glb_generator',
      },
      'scene': 0,
      'scenes': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'scene',
          'nodes': <int>[0],
        },
      ],
      'nodes': nodes,
      'meshes': gltfMeshes,
      'materials': materials,
      'accessors': accessors,
      'bufferViews': bufferViews,
      'buffers': <Map<String, dynamic>>[
        <String, dynamic>{'byteLength': binBytes.length},
      ],
    };

    final rawJsonBytes = utf8.encode(jsonEncode(gltfJson));
    final jsonPad = (4 - (rawJsonBytes.length % 4)) % 4;
    final jsonChunkLen = rawJsonBytes.length + jsonPad;
    final totalLen = 12 + 8 + jsonChunkLen + 8 + binBytes.length;

    final out = Uint8List(totalLen);
    final header = ByteData.sublistView(out);
    header.setUint32(0, GlbBinaryReader.glbMagic, Endian.little);
    header.setUint32(4, GlbBinaryReader.glbVersion, Endian.little);
    header.setUint32(8, totalLen, Endian.little);

    // JSON chunk header + payload + space padding (0x20).
    header.setUint32(12, jsonChunkLen, Endian.little);
    header.setUint32(16, GlbBinaryReader.chunkTypeJson, Endian.little);
    out.setRange(20, 20 + rawJsonBytes.length, rawJsonBytes);
    for (var i = 0; i < jsonPad; i++) {
      out[20 + rawJsonBytes.length + i] = 0x20;
    }

    // BIN chunk header + payload.
    final binChunkOffset = 20 + jsonChunkLen;
    header.setUint32(binChunkOffset, binBytes.length, Endian.little);
    header.setUint32(binChunkOffset + 4, GlbBinaryReader.chunkTypeBin, Endian.little);
    out.setRange(binChunkOffset + 8, totalLen, binBytes);

    return out;
  }

  static Map<String, dynamic> _pbrMaterial(
    String name,
    int argbHex, {
    required double metallic,
    required double roughness,
    List<double>? emissive,
  }) {
    double toLinear(int channel) {
      final srgb = (channel & 0xFF) / 255.0;
      return srgb <= 0.04045
          ? srgb / 12.92
          : math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
    }

    final mat = <String, dynamic>{
      'name': name,
      'pbrMetallicRoughness': <String, dynamic>{
        'baseColorFactor': <double>[
          toLinear(argbHex >> 16),
          toLinear(argbHex >> 8),
          toLinear(argbHex),
          1.0,
        ],
        'metallicFactor': metallic,
        'roughnessFactor': roughness,
      },
    };
    if (emissive != null) {
      mat['emissiveFactor'] = emissive;
    }
    return mat;
  }
}
