import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../../core/result/app_failure.dart';
import '../../../core/result/result.dart';
import '../models/asset_manifest_model.dart';
import '../models/faction_model.dart';
import '../models/piece_model.dart';

/// Loads and validates the Blender 3D [AssetManifest] registry.
abstract interface class AssetManifestLoader {
  Future<Result<AssetManifest>> loadManifest();
}

/// Loads `assets/models/asset_manifest.json` from a Flutter [AssetBundle].
final class BundledAssetManifestLoader implements AssetManifestLoader {
  static const String defaultManifestPath = 'assets/models/asset_manifest.json';

  const BundledAssetManifestLoader({
    this.bundle,
    this.manifestPath = defaultManifestPath,
    this.requireFactionMeshes = false,
  });

  final AssetBundle? bundle;
  final String manifestPath;
  final bool requireFactionMeshes;

  @override
  Future<Result<AssetManifest>> loadManifest() async {
    final normalizedPath = manifestPath.trim();
    if (normalizedPath.isEmpty) {
      return const Err<AssetManifest>(
        ValidationAppFailure(
          'Asset manifest path must not be empty.',
          code: 'INVALID_MANIFEST_PATH',
          fieldErrors: <String, String>{
            'manifestPath': 'Must not be empty.',
          },
        ),
      );
    }

    final resolvedBundle = bundle ?? rootBundle;
    final String rawJson;
    try {
      rawJson = await resolvedBundle.loadString(normalizedPath);
    } catch (error) {
      return Err<AssetManifest>(
        ValidationAppFailure(
          'Failed to load asset manifest at "$normalizedPath".',
          code: 'ASSET_MANIFEST_LOAD_FAILED',
          cause: error,
          fieldErrors: <String, String>{'manifestPath': normalizedPath},
        ),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      return Err<AssetManifest>(
        ValidationAppFailure(
          'Malformed JSON in asset manifest at "$normalizedPath".',
          code: 'INVALID_ASSET_MANIFEST_JSON',
          cause: error,
          fieldErrors: <String, String>{'manifestPath': 'Malformed JSON.'},
        ),
      );
    } catch (error) {
      return Err<AssetManifest>(
        ValidationAppFailure(
          'Failed to decode asset manifest at "$normalizedPath".',
          code: 'INVALID_ASSET_MANIFEST_JSON',
          cause: error,
          fieldErrors: <String, String>{'manifestPath': 'Decode error.'},
        ),
      );
    }

    if (decoded is! Map) {
      return Err<AssetManifest>(
        ValidationAppFailure(
          'Asset manifest at "$normalizedPath" must be a JSON object.',
          code: 'INVALID_ASSET_MANIFEST_FORMAT',
          fieldErrors: const <String, String>{
            'manifest': 'Expected top-level JSON object.',
          },
        ),
      );
    }

    final jsonMap = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded);

    final schemaError = _validateManifestJson(jsonMap);
    if (schemaError != null) {
      return Err<AssetManifest>(schemaError);
    }

    try {
      final manifest = AssetManifest.fromJson(jsonMap);
      return Ok<AssetManifest>(manifest);
    } catch (error) {
      return Err<AssetManifest>(
        ValidationAppFailure(
          'Failed to parse AssetManifest from "$normalizedPath".',
          code: 'INVALID_ASSET_MANIFEST_SCHEMA',
          cause: error,
        ),
      );
    }
  }

  ValidationAppFailure? _validateManifestJson(Map<String, dynamic> json) {
    final errors = <String, String>{};

    final rawBoardPath = json['boardGlbPath'] ?? json['board_glb_path'];
    if (rawBoardPath is! String || rawBoardPath.trim().isEmpty) {
      errors['boardGlbPath'] = 'Must be a non-empty string.';
    }

    final rawPieces = json['pieces'];
    if (rawPieces is! List) {
      errors['pieces'] = 'Must be a JSON array.';
    } else if (rawPieces.isEmpty) {
      errors['pieces'] = 'Must contain at least one piece descriptor.';
    } else {
      for (var i = 0; i < rawPieces.length; i++) {
        final item = rawPieces[i];
        if (item is! Map) {
          errors['pieces[$i]'] = 'Must be a JSON object.';
          continue;
        }
        final assetId = item['assetId'] ?? item['asset_id'];
        if (assetId is! String || assetId.trim().isEmpty) {
          errors['pieces[$i].assetId'] = 'Must be a non-empty string.';
        }
        final glbPath = item['glbPath'] ?? item['glb_path'];
        if (glbPath is! String || glbPath.trim().isEmpty) {
          errors['pieces[$i].glbPath'] = 'Must be a non-empty string.';
        }
        final rawVisualKey = item['visualKey'] ?? item['visual_key'];
        if (rawVisualKey is! Map) {
          errors['pieces[$i].visualKey'] = 'Must be a JSON object.';
        } else {
          final rawType = rawVisualKey['type'] ??
              rawVisualKey['pieceType'] ??
              rawVisualKey['piece_type'];
          if (PieceType.tryFromJsonValue(rawType) == null) {
            errors['pieces[$i].visualKey.type'] =
                'Must be a valid PieceType.';
          }
          if (PlayerSide.tryFromJsonValue(rawVisualKey['side']) == null) {
            errors['pieces[$i].visualKey.side'] =
                'Must be a valid PlayerSide.';
          }
        }
      }
    }

    final rawVersion = json['schemaVersion'] ?? json['schema_version'];
    if (rawVersion != null && (rawVersion is! int || rawVersion < 1)) {
      errors['schemaVersion'] = 'Must be a positive integer.';
    }

    final rawUnitScale = json['unitScaleMeters'] ?? json['unit_scale_meters'];
    if (rawUnitScale != null &&
        (rawUnitScale is! num || !rawUnitScale.isFinite || rawUnitScale <= 0)) {
      errors['unitScaleMeters'] = 'Must be a finite positive number.';
    }

    _validateFactionMeshes(json, errors);

    if (errors.isEmpty) {
      return null;
    }

    return ValidationAppFailure(
      'Asset manifest failed schema validation.',
      code: 'INVALID_ASSET_MANIFEST_SCHEMA',
      fieldErrors: Map<String, String>.unmodifiable(errors),
    );
  }

  void _validateFactionMeshes(
    Map<String, dynamic> json,
    Map<String, String> errors,
  ) {
    final rawFactionMeshes = json['factionMeshes'] ?? json['faction_meshes'];
    if (rawFactionMeshes == null) {
      if (requireFactionMeshes) {
        errors['factionMeshes'] =
            'Must be a JSON object mapping all 11 factions.';
      }
      return;
    }

    if (rawFactionMeshes is! Map) {
      errors['factionMeshes'] =
          'Must be a JSON object mapping all 11 factions.';
      return;
    }

    final factionMaps = <FactionId, Map<dynamic, dynamic>>{};
    for (final outerEntry in rawFactionMeshes.entries) {
      final faction = FactionId.tryFromJsonValue(outerEntry.key);
      if (faction == null) {
        errors['factionMeshes.${outerEntry.key}'] =
            'Unknown FactionId "${outerEntry.key}".';
        continue;
      }
      if (factionMaps.containsKey(faction)) {
        errors['factionMeshes.${faction.code}'] =
            'Duplicate faction entry "${outerEntry.key}".';
        continue;
      }
      final rawFactionMap = outerEntry.value;
      if (rawFactionMap is! Map) {
        errors['factionMeshes.${faction.code}'] =
            'Must be a JSON object mapping all 11 PieceTypes.';
        continue;
      }
      factionMaps[faction] = rawFactionMap;
    }

    for (final faction in FactionId.values) {
      final rawPiecesMap = factionMaps[faction];
      if (rawPiecesMap == null) {
        if (!errors.containsKey('factionMeshes.${faction.code}')) {
          errors['factionMeshes.${faction.code}'] =
              'Missing faction meshes for "${faction.code}".';
        }
        continue;
      }

      final seenTypes = <PieceType>{};
      for (final innerEntry in rawPiecesMap.entries) {
        final pieceType = PieceType.tryFromJsonValue(innerEntry.key);
        if (pieceType == null) {
          errors['factionMeshes.${faction.code}.${innerEntry.key}'] =
              'Unknown PieceType "${innerEntry.key}".';
          continue;
        }
        if (!seenTypes.add(pieceType)) {
          errors['factionMeshes.${faction.code}.${pieceType.snakeCaseName}'] =
              'Duplicate piece entry "${innerEntry.key}".';
          continue;
        }
        final expectedPath =
            'assets/models/pieces/${faction.code}_${pieceType.snakeCaseName}_lod0.glb';
        final rawPath = innerEntry.value;
        if (rawPath is! String || rawPath.trim() != expectedPath) {
          errors['factionMeshes.${faction.code}.${pieceType.snakeCaseName}'] =
              'Must equal "$expectedPath".';
        }
      }

      for (final pieceType in PieceType.values) {
        if (!seenTypes.contains(pieceType) &&
            !errors.containsKey(
              'factionMeshes.${faction.code}.${pieceType.snakeCaseName}',
            )) {
          errors['factionMeshes.${faction.code}.${pieceType.snakeCaseName}'] =
              'Missing mesh path for "${faction.code}.${pieceType.snakeCaseName}".';
        }
      }
    }
  }
}
