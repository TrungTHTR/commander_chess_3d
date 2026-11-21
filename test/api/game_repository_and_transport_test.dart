import 'dart:convert';
import 'dart:io';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/models/action_model.dart';
import 'package:commander_chess_3d/features/game/models/asset_manifest_model.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/multiplayer_dto.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/repositories/asset_manifest_loader.dart';
import 'package:commander_chess_3d/features/game/repositories/game_repository.dart';
import 'package:commander_chess_3d/features/game/repositories/multiplayer_transport.dart';
import 'package:commander_chess_3d/features/game/rules/commander_rules_engine.dart';
import 'package:flutter/services.dart' show AssetBundle, ByteData, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';

final class _MockAssetBundle extends CachingAssetBundle {
  _MockAssetBundle(this._entries);

  final Map<String, String> _entries;

  @override
  Future<ByteData> load(String key) {
    throw UnsupportedError('Binary load not needed in test');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = _entries[key];
    if (value == null) {
      throw StateError('Missing asset key: $key');
    }
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rules = StarterCommanderRulesEngine();
  final fixedClock = FixedClock(DateTime.utc(2026, 11, 20, 15, 0, 0));

  group('InMemoryGameRepository', () {
    late InMemoryGameRepository repo;

    setUp(() {
      repo = InMemoryGameRepository();
    });

    tearDown(() {
      repo.dispose();
    });

    test('createMatch, loadMatch, saveSnapshot, watchMatch, and genuine undoLastMove rollback', () async {
      final initial = rules.createInitialSession(matchId: 'match_1');
      final watched = <GameSessionState>[];
      final sub = repo.watchMatch('match_1').listen(watched.add);
      addTearDown(sub.cancel);

      // Validation boundaries on createMatch & loadMatch.
      final blankCreate = await repo.createMatch(
        matchId: '   ',
        initialState: initial,
      );
      expect(blankCreate.isErr, isTrue);
      expect(blankCreate.failureOrNull!.code, 'INVALID_MATCH_ID');

      final mismatchCreate = await repo.createMatch(
        matchId: 'other_id',
        initialState: initial,
      );
      expect(mismatchCreate.isErr, isTrue);
      expect(mismatchCreate.failureOrNull!.code, 'MATCH_ID_MISMATCH');

      final created = await repo.createMatch(
        matchId: 'match_1',
        initialState: initial,
      );
      expect(created.isOk, isTrue);

      // Duplicate createMatch rejected.
      final duplicate = await repo.createMatch(
        matchId: 'match_1',
        initialState: initial,
      );
      expect(duplicate.isErr, isTrue);
      expect(duplicate.failureOrNull!.code, 'MATCH_ALREADY_EXISTS');

      // Undo boundary when only initial snapshot exists.
      final nothingToUndo = await repo.undoLastMove('match_1');
      expect(nothingToUndo.isErr, isTrue);
      expect(nothingToUndo.failureOrNull!.code, 'NOTHING_TO_UNDO');

      // Apply a legal move and save snapshot.
      final c5 = BoardCoord.fromAlgebraic('c5');
      final c6 = BoardCoord.fromAlgebraic('c6');
      final piece = initial.pieceAt(c5)!;
      final afterMove = rules
          .applyMove(
            state: initial,
            move: GameMove(
              side: PlayerSide.red,
              pieceId: piece.id,
              from: c5,
              to: c6,
              kind: ActionKind.move,
              timestampUtc: fixedClock.nowUtc(),
            ),
          )
          .valueOrNull!;

      final saved = await repo.saveSnapshot(afterMove);
      expect(saved.isOk, isTrue);
      expect((await repo.loadMatch('match_1')).valueOrNull, afterMove);

      // Genuine rollback to initial state.
      final undone = await repo.undoLastMove('match_1');
      expect(undone.isOk, isTrue);
      expect(undone.valueOrNull, initial);
      expect((await repo.loadMatch('match_1')).valueOrNull, initial);

      // Cannot undo past initial snapshot.
      final secondUndo = await repo.undoLastMove('match_1');
      expect(secondUndo.isErr, isTrue);
      expect(secondUndo.failureOrNull!.code, 'NOTHING_TO_UNDO');

      await Future<void>.delayed(Duration.zero);
      expect(watched, <GameSessionState>[initial, afterMove, initial]);
    });

    test('saveSnapshot trims/normalizes matchId and rejects blank matchId', () async {
      final blankSnapshot = rules.createInitialSession(matchId: '   ');
      final blankResult = await repo.saveSnapshot(blankSnapshot);
      expect(blankResult.isErr, isTrue);
      expect(blankResult.failureOrNull!.code, 'INVALID_MATCH_ID');

      final watched = <GameSessionState>[];
      final sub = repo.watchMatch('match_trimmed').listen(watched.add);
      addTearDown(sub.cancel);

      final untrimmedSnapshot = rules.createInitialSession(
        matchId: '  match_trimmed  ',
      );
      final saved = await repo.saveSnapshot(untrimmedSnapshot);
      expect(saved.isOk, isTrue);
      expect(saved.valueOrNull!.matchId, 'match_trimmed');

      final loaded = await repo.loadMatch('match_trimmed');
      expect(loaded.isOk, isTrue);
      expect(loaded.valueOrNull!.matchId, 'match_trimmed');

      await Future<void>.delayed(Duration.zero);
      expect(watched, hasLength(1));
      expect(watched.single.matchId, 'match_trimmed');
    });

    test('dispose closes streams and rejects subsequent calls', () async {
      final initial = rules.createInitialSession(matchId: 'match_dispose');
      await repo.createMatch(matchId: 'match_dispose', initialState: initial);

      var streamDone = false;
      final sub = repo.watchMatch('match_dispose').listen(
            (_) {},
            onDone: () => streamDone = true,
          );
      addTearDown(sub.cancel);

      repo.dispose();
      // Idempotent second dispose call.
      repo.dispose();
      expect(repo.isDisposed, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(streamDone, isTrue);

      final postDisposeLoad = await repo.loadMatch('match_dispose');
      expect(postDisposeLoad.isErr, isTrue);
      expect(postDisposeLoad.failureOrNull!.code, 'REPOSITORY_DISPOSED');

      expect(repo.watchMatch('match_dispose'), emitsDone);
    });
  });

  group('StubMultiplayerTransport', () {
    late StubMultiplayerTransport transport;

    setUp(() {
      transport = StubMultiplayerTransport(clock: fixedClock);
    });

    tearDown(() {
      transport.dispose();
    });

    MoveSubmissionDto validDto({
      String matchId = 'm1',
      String playerId = 'p_red',
      int expectedTurnNumber = 1,
      String pieceId = 'red_infantry_c5',
      BoardCoord? from,
      BoardCoord? to,
      String? clientRequestId = 'req-1',
    }) {
      return MoveSubmissionDto(
        matchId: matchId,
        playerId: playerId,
        expectedTurnNumber: expectedTurnNumber,
        clientRequestId: clientRequestId,
        move: GameMove(
          side: PlayerSide.red,
          pieceId: pieceId,
          from: from ?? BoardCoord.fromAlgebraic('c5'),
          to: to ?? BoardCoord.fromAlgebraic('c6'),
          kind: ActionKind.move,
          timestampUtc: fixedClock.nowUtc(),
        ),
      );
    }

    test('validates connect, submitMove payloads, and enforces idempotency', () async {
      // Submit before connect fails with NetworkAppFailure.
      final disconnectedSubmit = await transport.submitMove(validDto());
      expect(disconnectedSubmit.isErr, isTrue);
      expect(disconnectedSubmit.failureOrNull, isA<NetworkAppFailure>());
      expect(disconnectedSubmit.failureOrNull!.code, 'NOT_CONNECTED');

      // Blank matchId & authToken rejected.
      final badMatch = await transport.connect(
        matchId: '  ',
        authToken: 'token',
      );
      expect(badMatch.failureOrNull, isA<ValidationAppFailure>());

      final badAuth = await transport.connect(
        matchId: 'm1',
        authToken: '  ',
      );
      expect(badAuth.failureOrNull, isA<AuthAppFailure>());

      // Successful connect.
      final connected = await transport.connect(
        matchId: 'm1',
        authToken: 'bearer-123',
      );
      expect(connected.isOk, isTrue);
      expect(transport.isConnected, isTrue);
      expect(transport.activeMatchId, 'm1');

      // Invalid MoveSubmissionDto combinations rejected with fieldErrors.
      final badPayload = await transport.submitMove(
        validDto(
          matchId: 'wrong_match',
          playerId: '',
          expectedTurnNumber: 0,
          pieceId: '',
          from: const BoardCoord(file: -1, rank: 0),
          to: const BoardCoord(file: 0, rank: 12),
          clientRequestId: '   ',
        ),
      );
      expect(badPayload.isErr, isTrue);
      final failure = badPayload.failureOrNull! as ValidationAppFailure;
      expect(failure.code, 'INVALID_MOVE_SUBMISSION');
      expect(
        failure.fieldErrors.keys,
        containsAll(<String>[
          'matchId',
          'playerId',
          'expectedTurnNumber',
          'move.pieceId',
          'move.from',
          'move.to',
          'clientRequestId',
        ]),
      );

      // Listen for events and verify idempotent duplicate clientRequestId.
      final received = <MatchSyncEventDto>[];
      final sub = transport.events.listen(received.add);
      addTearDown(sub.cancel);

      final firstSubmit = await transport.submitMove(
        validDto(clientRequestId: 'req-abc'),
      );
      final duplicateSubmit = await transport.submitMove(
        validDto(clientRequestId: 'req-abc'),
      );
      final secondSubmit = await transport.submitMove(
        validDto(clientRequestId: 'req-def'),
      );

      expect(firstSubmit.isOk, isTrue);
      expect(duplicateSubmit.isOk, isTrue);
      expect(secondSubmit.isOk, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));
      expect(received[0].sequenceNumber, 1);
      expect(received[0].eventType, 'moveAccepted');
      expect(received[1].sequenceNumber, 2);

      // Disconnect resets connection state.
      await transport.disconnect();
      expect(transport.isConnected, isFalse);
      expect(transport.activeMatchId, isNull);
    });

    test('dispose closes events stream and rejects future operations', () async {
      var closed = false;
      final sub = transport.events.listen((_) {}, onDone: () => closed = true);
      addTearDown(sub.cancel);

      transport.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue);

      final connectAfterDispose = await transport.connect(
        matchId: 'm1',
        authToken: 'tok',
      );
      expect(connectAfterDispose.isErr, isTrue);
      expect(connectAfterDispose.failureOrNull!.code, 'TRANSPORT_DISPOSED');

      final submitAfterDispose = await transport.submitMove(validDto());
      expect(submitAfterDispose.isErr, isTrue);
      expect(submitAfterDispose.failureOrNull!.code, 'TRANSPORT_DISPOSED');
    });
  });

  group('BundledAssetManifestLoader', () {
    test('loads real bundled asset_manifest.json with 22 descriptors', () async {
      const loader = BundledAssetManifestLoader();
      final result = await loader.loadManifest();
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.pieces, hasLength(22));
    });

    test('validates mock AssetBundle success, missing asset, malformed JSON, and invalid schemas', () async {
      final AssetBundle validBundle = _MockAssetBundle(<String, String>{
        BundledAssetManifestLoader.defaultManifestPath:
            '{"schemaVersion":1,"boardGlbPath":"assets/models/board/b.glb","pieces":[{"assetId":"red_commander","visualKey":{"type":"commander","side":"red"},"glbPath":"assets/models/pieces/commander_lod0.glb"}]}',
      });
      final validLoader = BundledAssetManifestLoader(bundle: validBundle);
      final validResult = await validLoader.loadManifest();
      expect(validResult.isOk, isTrue);
      expect(validResult.valueOrNull, isA<AssetManifest>());

      final missingLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(const <String, String>{}),
      );
      final missingResult = await missingLoader.loadManifest();
      expect(missingResult.isErr, isTrue);
      expect(
        missingResult.failureOrNull,
        isA<ValidationAppFailure>().having(
          (f) => f.code,
          'code',
          'ASSET_MANIFEST_LOAD_FAILED',
        ),
      );

      final malformedLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath: '{not valid json',
        }),
      );
      final malformedResult = await malformedLoader.loadManifest();
      expect(malformedResult.isErr, isTrue);
      expect(
        malformedResult.failureOrNull,
        isA<ValidationAppFailure>().having(
          (f) => f.code,
          'code',
          'INVALID_ASSET_MANIFEST_JSON',
        ),
      );

      final nonObjectLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath: '[]',
        }),
      );
      final nonObjectResult = await nonObjectLoader.loadManifest();
      expect(nonObjectResult.isErr, isTrue);
      expect(
        nonObjectResult.failureOrNull!.code,
        'INVALID_ASSET_MANIFEST_FORMAT',
      );

      final badSchemaLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath:
              '{"schemaVersion":0,"boardGlbPath":"","pieces":[{"assetId":"","glbPath":""}]}',
        }),
      );
      final badSchemaResult = await badSchemaLoader.loadManifest();
      expect(badSchemaResult.isErr, isTrue);
      final schemaFailure =
          badSchemaResult.failureOrNull! as ValidationAppFailure;
      expect(schemaFailure.code, 'INVALID_ASSET_MANIFEST_SCHEMA');
      expect(
        schemaFailure.fieldErrors.keys,
        containsAll(<String>[
          'boardGlbPath',
          'pieces[0].assetId',
          'pieces[0].glbPath',
          'schemaVersion',
        ]),
      );

      const emptyPathLoader = BundledAssetManifestLoader(manifestPath: '   ');
      final emptyPathResult = await emptyPathLoader.loadManifest();
      expect(emptyPathResult.failureOrNull!.code, 'INVALID_MANIFEST_PATH');

      // Empty pieces array is rejected.
      final emptyPiecesLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath:
              '{"schemaVersion":1,"boardGlbPath":"assets/models/board/b.glb","pieces":[]}',
        }),
      );
      final emptyPiecesResult = await emptyPiecesLoader.loadManifest();
      expect(emptyPiecesResult.isErr, isTrue);
      final emptyPiecesFailure =
          emptyPiecesResult.failureOrNull! as ValidationAppFailure;
      expect(emptyPiecesFailure.code, 'INVALID_ASSET_MANIFEST_SCHEMA');
      expect(emptyPiecesFailure.fieldErrors.keys, contains('pieces'));

      // Piece descriptor missing visualKey is rejected.
      final missingVisualKeyLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath:
              '{"schemaVersion":1,"boardGlbPath":"assets/models/board/b.glb","pieces":[{"assetId":"red_commander","glbPath":"assets/models/pieces/commander_lod0.glb"}]}',
        }),
      );
      final missingVisualKeyResult = await missingVisualKeyLoader.loadManifest();
      expect(missingVisualKeyResult.isErr, isTrue);
      final missingVisualKeyFailure =
          missingVisualKeyResult.failureOrNull! as ValidationAppFailure;
      expect(missingVisualKeyFailure.code, 'INVALID_ASSET_MANIFEST_SCHEMA');
      expect(
        missingVisualKeyFailure.fieldErrors.keys,
        contains('pieces[0].visualKey'),
      );
    });
  });

  group('Multiplayer DTO validation & OpenAPI 3.1.0 schema parity', () {
    test('DTOs throw FormatException on 1e999/NaN and nullify bogus winner', () {
      final decodedInfMoveDto = jsonDecode(
        '{"matchId":"m1","playerId":"p1","expectedTurnNumber":1e999,"move":{"side":"red","pieceId":"p","from":{"file":0,"rank":0},"to":{"file":0,"rank":1},"kind":"move","timestampUtc":"2026-11-20T00:00:00Z"}}',
      ) as Map<String, dynamic>;
      expect(
        () => MoveSubmissionDto.fromJson(decodedInfMoveDto),
        throwsFormatException,
      );

      expect(
        () => MoveSubmissionDto.fromJson(<String, dynamic>{
          'matchId': 'm1',
          'playerId': 'p1',
          'expectedTurnNumber': double.nan,
          'move': <String, dynamic>{
            'side': 'red',
            'pieceId': 'p',
            'from': <String, dynamic>{'file': 0, 'rank': 0},
            'to': <String, dynamic>{'file': 0, 'rank': 1},
            'kind': 'move',
            'timestampUtc': '2026-11-20T00:00:00Z',
          },
        }),
        throwsFormatException,
      );

      final summaryBogusWinner = MatchSummaryDto.fromJson(<String, dynamic>{
        'matchId': 'm1',
        'mode': 'onlineMultiplayer',
        'phase': 'finished',
        'currentTurn': 'red',
        'winner': 'bogus',
        'createdAtUtc': '2026-11-20T00:00:00Z',
        'updatedAtUtc': '2026-11-20T00:00:00Z',
      });
      expect(summaryBogusWinner.winner, isNull);
    });

    test('OpenAPI components.schemas match Dart DTO properties and enums 1:1', () async {
      final specFile = File('openapi/commander_chess_v1.yaml');
      expect(specFile.existsSync(), isTrue);
      final schemas = _parseOpenApiSchemas(specFile.readAsStringSync());

      // 1. VictoryReason enum 1:1 parity
      expect(
        VictoryReason.values.map((e) => e.name).toList(),
        equals(schemas['VictoryReason']!.enumValues),
      );

      // 2. SyncEventType enum contains canonical events + StubMultiplayerTransport eventType
      final openApiSyncEvents = schemas['SyncEventType']!.enumValues;
      expect(
        openApiSyncEvents,
        equals(<String>[
          'matchCreated',
          'moveAccepted',
          'moveApplied',
          'moveRejected',
          'stateSnapshot',
          'matchEnded',
          'opponentConnected',
          'opponentDisconnected',
          'heartbeat',
        ]),
      );

      // Verify StubMultiplayerTransport emits a valid OpenAPI SyncEventType.
      final stub = StubMultiplayerTransport(clock: fixedClock);
      addTearDown(stub.dispose);
      final emitted = <MatchSyncEventDto>[];
      final sub = stub.events.listen(emitted.add);
      addTearDown(sub.cancel);
      await stub.connect(matchId: 'm_parity', authToken: 'tok');
      await stub.submitMove(
        MoveSubmissionDto(
          matchId: 'm_parity',
          playerId: 'p_red',
          expectedTurnNumber: 1,
          move: GameMove(
            side: PlayerSide.red,
            pieceId: 'red_infantry_c5',
            from: BoardCoord.fromAlgebraic('c5'),
            to: BoardCoord.fromAlgebraic('c6'),
            kind: ActionKind.move,
            timestampUtc: fixedClock.nowUtc(),
          ),
          clientRequestId: 'req-12345678',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(openApiSyncEvents, contains(emitted.single.eventType));

      // 3. RuleVariantConfig schema 1:1 parity
      const variantConfig = RuleVariantConfig(
        hqShelterEnabled: true,
        fourBattleMode: true,
        allowDrawByRepetition: false,
      );
      expect(
        variantConfig.toJson().keys.toSet(),
        equals(schemas['RuleVariantConfig']!.properties),
      );

      // 4. CreateMatchRequestDto schema 1:1 parity (all fields + required subset)
      const createFull = CreateMatchRequestDto(
        mode: GameMode.onlineMultiplayer,
        preferredSide: PlayerSide.blue,
        variantConfig: variantConfig,
        timeControlSeconds: 600,
        incrementSeconds: 5,
      );
      expect(
        createFull.toJson().keys.toSet(),
        equals(schemas['CreateMatchRequestDto']!.properties),
      );
      expect(
        const CreateMatchRequestDto().toJson().keys.toSet(),
        containsAll(schemas['CreateMatchRequestDto']!.required),
      );
      expect(CreateMatchRequestDto.fromJson(createFull.toJson()), createFull);

      // 5. MoveSubmissionDto schema 1:1 parity
      final moveSample = GameMove(
        side: PlayerSide.red,
        pieceId: 'red_infantry_c5',
        from: BoardCoord.fromAlgebraic('c5'),
        to: BoardCoord.fromAlgebraic('c6'),
        kind: ActionKind.move,
        timestampUtc: fixedClock.nowUtc(),
      );
      final moveSubFull = MoveSubmissionDto(
        matchId: 'm1',
        playerId: 'p1',
        expectedTurnNumber: 1,
        move: moveSample,
        clientRequestId: 'req-12345678',
      );
      expect(
        moveSubFull.toJson().keys.toSet(),
        equals(schemas['MoveSubmissionDto']!.properties),
      );
      final moveSubMinimal = MoveSubmissionDto(
        matchId: 'm1',
        playerId: 'p1',
        expectedTurnNumber: 1,
        move: moveSample,
      );
      expect(
        moveSubMinimal.toJson().keys.toSet(),
        equals(schemas['MoveSubmissionDto']!.required),
      );
      expect(MoveSubmissionDto.fromJson(moveSubFull.toJson()), moveSubFull);

      // 6. MatchSyncEventDto schema 1:1 parity
      final sessionSample = rules.createInitialSession(matchId: 'm1');
      final syncFull = MatchSyncEventDto(
        matchId: 'm1',
        sequenceNumber: 1,
        eventType: 'moveAccepted',
        occurredAtUtc: fixedClock.nowUtc(),
        move: moveSample,
        sessionSnapshot: sessionSample,
        errorMessage: 'none',
      );
      expect(
        syncFull.toJson().keys.toSet(),
        equals(schemas['MatchSyncEventDto']!.properties),
      );
      final syncMinimal = MatchSyncEventDto(
        matchId: 'm1',
        sequenceNumber: 0,
        eventType: 'heartbeat',
        occurredAtUtc: fixedClock.nowUtc(),
      );
      expect(
        syncMinimal.toJson().keys.toSet(),
        equals(schemas['MatchSyncEventDto']!.required),
      );
      expect(MatchSyncEventDto.fromJson(syncFull.toJson()), syncFull);

      // 7. MatchSummaryDto schema 1:1 parity
      final summaryFull = MatchSummaryDto(
        matchId: 'm1',
        mode: GameMode.onlineMultiplayer,
        phase: MatchPhase.finished,
        currentTurn: PlayerSide.red,
        turnNumber: 12,
        redPlayerId: 'red_1',
        bluePlayerId: 'blue_1',
        winner: PlayerSide.red,
        victoryReason: VictoryReason.commanderCaptured,
        createdAtUtc: fixedClock.nowUtc(),
        updatedAtUtc: fixedClock.nowUtc(),
      );
      expect(
        summaryFull.toJson().keys.toSet(),
        equals(schemas['MatchSummaryDto']!.properties),
      );
      final summaryMinimal = MatchSummaryDto(
        matchId: 'm1',
        mode: GameMode.onlineMultiplayer,
        phase: MatchPhase.playing,
        currentTurn: PlayerSide.red,
        createdAtUtc: fixedClock.nowUtc(),
        updatedAtUtc: fixedClock.nowUtc(),
      );
      expect(
        summaryMinimal.toJson().keys.toSet(),
        equals(schemas['MatchSummaryDto']!.required),
      );
      expect(MatchSummaryDto.fromJson(summaryFull.toJson()), summaryFull);
    });
  });
}

final class _OpenApiSchemaDef {
  final Set<String> properties = <String>{};
  final Set<String> required = <String>{};
  final List<String> enumValues = <String>[];
}

Map<String, _OpenApiSchemaDef> _parseOpenApiSchemas(String yaml) {
  final lines = yaml.replaceAll('\r\n', '\n').split('\n');
  final schemas = <String, _OpenApiSchemaDef>{};

  var inComponents = false;
  var inSchemas = false;
  String? currentSchema;
  String? currentSection; // 'properties' | 'required' | 'enum'

  for (final rawLine in lines) {
    final trimmedRight = rawLine.trimRight();
    if (trimmedRight.trim().isEmpty || trimmedRight.trimLeft().startsWith('#')) {
      continue;
    }

    final indent = rawLine.length - rawLine.trimLeft().length;
    final trimmed = trimmedRight.trim();

    if (indent == 0) {
      inComponents = trimmed == 'components:';
      inSchemas = false;
      currentSchema = null;
      currentSection = null;
      continue;
    }
    if (!inComponents) continue;

    if (indent == 2) {
      inSchemas = trimmed == 'schemas:';
      currentSchema = null;
      currentSection = null;
      continue;
    }
    if (!inSchemas) continue;

    if (indent == 4 && trimmed.endsWith(':')) {
      currentSchema = trimmed.substring(0, trimmed.length - 1);
      schemas[currentSchema] = _OpenApiSchemaDef();
      currentSection = null;
      continue;
    }
    if (currentSchema == null) continue;

    if (indent == 6) {
      if (trimmed == 'properties:') {
        currentSection = 'properties';
      } else if (trimmed == 'required:') {
        currentSection = 'required';
      } else if (trimmed == 'enum:') {
        currentSection = 'enum';
      } else {
        currentSection = null;
      }
      continue;
    }

    if (indent == 8) {
      final def = schemas[currentSchema]!;
      if (currentSection == 'properties' && trimmed.endsWith(':')) {
        def.properties.add(trimmed.substring(0, trimmed.length - 1));
      } else if (currentSection == 'required' && trimmed.startsWith('- ')) {
        def.required.add(trimmed.substring(2).trim());
      } else if (currentSection == 'enum' && trimmed.startsWith('- ')) {
        def.enumValues.add(trimmed.substring(2).trim());
      }
    }
  }

  return schemas;
}
