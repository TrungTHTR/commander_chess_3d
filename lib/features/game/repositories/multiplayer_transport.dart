import 'dart:async';

import '../../../core/result/app_failure.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../models/multiplayer_dto.dart';

/// Client transport contract aligned with `openapi/commander_chess_v1.yaml`.
abstract interface class MultiplayerTransport {
  /// Opens a match synchronization session using bearer [authToken].
  Future<Result<void>> connect({
    required String matchId,
    required String authToken,
  });

  /// Submits a candidate move payload with optimistic turn check and idempotency.
  Future<Result<void>> submitMove(MoveSubmissionDto dto);

  /// Broadcast stream of server-to-client [MatchSyncEventDto] frames.
  Stream<MatchSyncEventDto> get events;

  /// Closes the active match synchronization session.
  Future<void> disconnect();

  /// Releases stream resources and permanently closes the transport.
  void dispose();
}

/// Local offline stub implementing [MultiplayerTransport] lifecycle, DTO
/// validation, and [MatchSyncEventDto] emission without live server networking.
final class StubMultiplayerTransport implements MultiplayerTransport {
  StubMultiplayerTransport({
    this.clock = const SystemClock(),
  });

  final Clock clock;
  final StreamController<MatchSyncEventDto> _eventsController =
      StreamController<MatchSyncEventDto>.broadcast();
  final Set<String> _processedRequestIds = <String>{};

  bool _isConnected = false;
  bool _isDisposed = false;
  String? _activeMatchId;
  int _sequenceNumber = 0;

  /// Whether this local stub currently holds an active match session.
  bool get isConnected => _isConnected && !_isDisposed;

  /// Match identifier currently bound to the stub session, if connected.
  String? get activeMatchId => _activeMatchId;

  @override
  Stream<MatchSyncEventDto> get events => _eventsController.stream;

  @override
  Future<Result<void>> connect({
    required String matchId,
    required String authToken,
  }) async {
    if (_isDisposed) {
      return const Err<void>(
        ValidationAppFailure(
          'MultiplayerTransport has been disposed.',
          code: 'TRANSPORT_DISPOSED',
        ),
      );
    }

    final normalizedMatchId = matchId.trim();
    if (normalizedMatchId.isEmpty) {
      return const Err<void>(
        ValidationAppFailure(
          'matchId must not be empty.',
          code: 'INVALID_MATCH_ID',
          fieldErrors: <String, String>{'matchId': 'Must not be empty.'},
        ),
      );
    }

    if (authToken.trim().isEmpty) {
      return const Err<void>(
        AuthAppFailure(
          'authToken must not be empty.',
          code: 'MISSING_AUTH_TOKEN',
        ),
      );
    }

    _isConnected = true;
    _activeMatchId = normalizedMatchId;
    _sequenceNumber = 0;
    _processedRequestIds.clear();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> submitMove(MoveSubmissionDto dto) async {
    if (_isDisposed) {
      return const Err<void>(
        ValidationAppFailure(
          'MultiplayerTransport has been disposed.',
          code: 'TRANSPORT_DISPOSED',
        ),
      );
    }

    if (!_isConnected || _activeMatchId == null) {
      return const Err<void>(
        NetworkAppFailure(
          'Cannot submit move while transport is disconnected.',
          code: 'NOT_CONNECTED',
        ),
      );
    }

    final validationFailure = _validateSubmission(dto);
    if (validationFailure != null) {
      return Err<void>(validationFailure);
    }

    final requestId = dto.clientRequestId?.trim();
    if (requestId != null &&
        requestId.isNotEmpty &&
        !_processedRequestIds.add(requestId)) {
      return const Ok<void>(null);
    }

    _sequenceNumber += 1;
    if (!_eventsController.isClosed) {
      _eventsController.add(
        MatchSyncEventDto(
          matchId: dto.matchId,
          sequenceNumber: _sequenceNumber,
          eventType: 'moveAccepted',
          occurredAtUtc: clock.nowUtc(),
          move: dto.move,
        ),
      );
    }

    return const Ok<void>(null);
  }

  ValidationAppFailure? _validateSubmission(MoveSubmissionDto dto) {
    final errors = <String, String>{};

    if (dto.matchId.trim().isEmpty) {
      errors['matchId'] = 'Must not be empty.';
    } else if (dto.matchId != _activeMatchId) {
      errors['matchId'] =
          'Does not match connected match "$_activeMatchId".';
    }

    if (dto.playerId.trim().isEmpty) {
      errors['playerId'] = 'Must not be empty.';
    }

    if (dto.expectedTurnNumber < 1) {
      errors['expectedTurnNumber'] = 'Must be at least 1.';
    }

    if (dto.move.pieceId.trim().isEmpty) {
      errors['move.pieceId'] = 'Must not be empty.';
    }

    if (!dto.move.from.isValid) {
      errors['move.from'] = 'Coordinate is out of 11x12 board bounds.';
    }

    if (!dto.move.to.isValid) {
      errors['move.to'] = 'Coordinate is out of 11x12 board bounds.';
    }

    if (dto.clientRequestId != null && dto.clientRequestId!.trim().isEmpty) {
      errors['clientRequestId'] =
          'Must not be blank when clientRequestId is provided.';
    }

    if (errors.isEmpty) {
      return null;
    }

    return ValidationAppFailure(
      'Invalid MoveSubmissionDto payload.',
      code: 'INVALID_MOVE_SUBMISSION',
      fieldErrors: Map<String, String>.unmodifiable(errors),
    );
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _activeMatchId = null;
    _processedRequestIds.clear();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isConnected = false;
    _activeMatchId = null;
    _processedRequestIds.clear();
    if (!_eventsController.isClosed) {
      unawaited(_eventsController.close());
    }
  }
}
