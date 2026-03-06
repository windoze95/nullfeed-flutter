import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ephemeral map of video_id → download percentage (0.0–100.0).
/// Updated via WebSocket events, not persisted.
final downloadProgressProvider = StateProvider<Map<String, double>>(
  (ref) => {},
);
