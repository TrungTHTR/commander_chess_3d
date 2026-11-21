import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../models/asset_manifest_model.dart';
import '../repositories/asset_manifest_loader.dart';
import '../repositories/game_repository.dart';
import '../repositories/multiplayer_transport.dart';
import '../rules/board_topology.dart';
import '../rules/commander_rules_engine.dart';
import '../rules/usecases/start_match_usecase.dart';
import '../rules/usecases/submit_move_usecase.dart';
import 'game_hud_snapshot.dart';
import 'game_session_notifier.dart';

/// Deterministic UTC clock provider (override with [FixedClock] in tests).
final clockProvider = Provider<Clock>((ref) {
  return const SystemClock();
});

/// Pure-Dart 11x12 Commander Chess board topology provider.
final boardTopologyProvider = Provider<BoardTopology>((ref) {
  return const StandardCommanderBoardTopology();
});

/// Pure-Dart Commander Chess rules engine provider.
final rulesEngineProvider = Provider<CommanderRulesEngine>((ref) {
  return StarterCommanderRulesEngine(
    topology: ref.watch(boardTopologyProvider),
  );
});

/// Match persistence and reactive snapshot repository provider.
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final repo = InMemoryGameRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Multiplayer transport client provider (offline stub in starter build).
final multiplayerTransportProvider = Provider<MultiplayerTransport>((ref) {
  final transport = StubMultiplayerTransport(
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(() {
    unawaited(transport.disconnect());
    transport.dispose();
  });
  return transport;
});

/// Blender 3D asset manifest loader provider.
final assetManifestLoaderProvider = Provider<AssetManifestLoader>((ref) {
  return const BundledAssetManifestLoader();
});

/// Asynchronous loader for the Blender `.glb` [AssetManifest].
final assetManifestProvider = FutureProvider<Result<AssetManifest>>((ref) {
  return ref.watch(assetManifestLoaderProvider).loadManifest();
});

/// Use-case provider for initializing and persisting a new match.
final startMatchUseCaseProvider = Provider<StartMatchUseCase>((ref) {
  return StartMatchUseCase(
    topology: ref.watch(boardTopologyProvider),
    rulesEngine: ref.watch(rulesEngineProvider),
    repository: ref.watch(gameRepositoryProvider),
  );
});

/// Use-case provider for validating, applying, and persisting a move.
final submitMoveUseCaseProvider = Provider<SubmitMoveUseCase>((ref) {
  return SubmitMoveUseCase(
    rulesEngine: ref.watch(rulesEngineProvider),
    repository: ref.watch(gameRepositoryProvider),
  );
});

/// Cold Riverpod 3.x notifier provider owning [GameHudSnapshot].
final gameSessionNotifierProvider =
    NotifierProvider<GameSessionNotifier, GameHudSnapshot>(
  GameSessionNotifier.new,
);
