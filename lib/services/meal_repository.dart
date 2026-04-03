import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diet_goal.dart';
import '../models/meal_entry.dart';
import 'auth_service.dart';

class AppStateSnapshot {
  const AppStateSnapshot({
    required this.entries,
    required this.dietGoal,
    required this.miraMessages,
  });

  final List<MealEntry> entries;
  final DietGoal? dietGoal;
  final List<Map<String, dynamic>> miraMessages;
}

class MealRepository {
  MealRepository({
    http.Client? client,
    String? syncApiBaseUrl,
    AuthService? authService,
  })  : _client = client ?? http.Client(),
        _authService = authService ?? AuthService.instance,
        _syncApiBaseUrl = syncApiBaseUrl ??
            const String.fromEnvironment(
              'MEAL_MIRROR_SYNC_API_BASE_URL',
              defaultValue: '',
            );

  static const _storageKey = 'meal_entries_v3';
  static const _dietGoalKey = 'diet_goal_v1';
  static const _miraMessagesKey = 'mira_messages_v1';
  static const _deviceIdKey = 'sync_device_id_v1';
  static const _snapshotUpdatedAtKey = 'sync_snapshot_updated_at_v1';

  final http.Client _client;
  final AuthService _authService;
  final String _syncApiBaseUrl;
  Future<void> _syncQueue = Future<void>.value();

  Future<AppStateSnapshot> loadAppState() async {
    final preferences = await SharedPreferences.getInstance();
    final localSnapshot = _readLocalSnapshot(preferences);
    final localNormalized = await _normalizeSnapshotImagePaths(localSnapshot);
    if (localNormalized.changed) {
      await _writeLocalSnapshot(
        preferences,
        localNormalized.snapshot,
        _parseTimestamp(preferences.getString(_snapshotUpdatedAtKey)),
      );
    }

    final merged = await _syncOnLoad(preferences, localNormalized.snapshot);
    final mergedNormalized = await _normalizeSnapshotImagePaths(merged);
    if (mergedNormalized.changed) {
      await _writeLocalSnapshot(
        preferences,
        mergedNormalized.snapshot,
        _parseTimestamp(preferences.getString(_snapshotUpdatedAtKey)),
      );
    }

    return mergedNormalized.snapshot;
  }

  Future<List<MealEntry>> loadEntries() async {
    return (await loadAppState()).entries;
  }

  Future<void> saveEntries(List<MealEntry> entries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, MealEntry.encodeList(entries));
    await _markSnapshotUpdated(preferences);
    await _enqueueSync(preferences);
  }

  Future<DietGoal?> loadDietGoal() async {
    return (await loadAppState()).dietGoal;
  }

  Future<void> saveDietGoal(DietGoal goal) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_dietGoalKey, goal.encode());
    await _markSnapshotUpdated(preferences);
    await _enqueueSync(preferences);
  }

  Future<void> clearDietGoal() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_dietGoalKey);
    await _markSnapshotUpdated(preferences);
    await _enqueueSync(preferences);
  }

  Future<List<Map<String, dynamic>>> loadMiraMessages() async {
    return (await loadAppState()).miraMessages;
  }

  Future<void> saveMiraMessages(List<Map<String, dynamic>> messages) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_miraMessagesKey, jsonEncode(messages));
    await _markSnapshotUpdated(preferences);
    await _enqueueSync(preferences);
  }

  Future<void> clearMiraMessages() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_miraMessagesKey);
    await _markSnapshotUpdated(preferences);
    await _enqueueSync(preferences);
  }

  Future<String?> persistPickedImage(XFile? file) async {
    if (file == null) {
      return null;
    }

    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final storedFile = File('${directory.path}/$fileName');
    final copiedFile = await File(file.path).copy(storedFile.path);
    return copiedFile.path;
  }

  Future<List<String>> persistPickedImages(List<XFile> files) async {
    final paths = <String>[];
    for (final file in files) {
      final path = await persistPickedImage(file);
      if (path != null) {
        paths.add(path);
      }
    }
    return paths;
  }

  static File fileFromStoredPath(String path) => _fileFromStoredPath(path);

  AppStateSnapshot _readLocalSnapshot(SharedPreferences preferences) {
    final rawEntries = preferences.getString(_storageKey);
    final rawDietGoal = preferences.getString(_dietGoalKey);
    final rawMessages = preferences.getString(_miraMessagesKey);

    return AppStateSnapshot(
      entries: rawEntries == null || rawEntries.isEmpty
          ? _readLegacyEntries(preferences)
          : MealEntry.decodeList(rawEntries),
      dietGoal: rawDietGoal == null || rawDietGoal.isEmpty
          ? null
          : DietGoal.fromRaw(rawDietGoal),
      miraMessages: rawMessages == null || rawMessages.isEmpty
          ? const []
          : (jsonDecode(rawMessages) as List<dynamic>)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
    );
  }

  List<MealEntry> _readLegacyEntries(SharedPreferences preferences) {
    final legacy = preferences.getString('meal_entries_v2');
    if (legacy == null || legacy.isEmpty) {
      return const [];
    }
    return MealEntry.decodeList(legacy);
  }

  Future<AppStateSnapshot> _syncOnLoad(
    SharedPreferences preferences,
    AppStateSnapshot local,
  ) async {
    if (_syncApiBaseUrl.isEmpty) {
      return local;
    }

    try {
      if (_authService.isAuthenticated) {
        final remotePayload = await _fetchAuthenticatedSnapshot();
        final remoteUpdatedAt = _parseTimestamp(remotePayload?['updatedAt']);
        final localUpdatedAt = _parseTimestamp(
          preferences.getString(_snapshotUpdatedAtKey),
        );

        if (remotePayload == null) {
          if (_snapshotHasContent(local)) {
            await _pushSnapshot(preferences, local);
          }
          return local;
        }

        final remoteSnapshot = await _snapshotFromRemotePayload(remotePayload);
        final remoteIsNewer = remoteUpdatedAt.isAfter(localUpdatedAt);

        if (!_snapshotHasContent(local) || remoteIsNewer) {
          await _writeLocalSnapshot(
            preferences,
            remoteSnapshot,
            remoteUpdatedAt,
          );
          return remoteSnapshot;
        }

        if (_snapshotHasContent(local) &&
            localUpdatedAt.isAfter(remoteUpdatedAt)) {
          await _pushSnapshot(preferences, local);
        }

        return local;
      }

      final deviceId = await _deviceId(preferences);
      final remotePayload = await _fetchRemoteSnapshot(deviceId);
      final remoteUpdatedAt = _parseTimestamp(remotePayload?['updatedAt']);
      final localUpdatedAt = _parseTimestamp(
        preferences.getString(_snapshotUpdatedAtKey),
      );

      if (remotePayload == null) {
        if (_snapshotHasContent(local)) {
          await _pushSnapshot(preferences, local);
        }
        return local;
      }

      final remoteSnapshot = await _snapshotFromRemotePayload(remotePayload);
      final remoteIsNewer = remoteUpdatedAt.isAfter(localUpdatedAt);

      if (!_snapshotHasContent(local) || remoteIsNewer) {
        await _writeLocalSnapshot(
          preferences,
          remoteSnapshot,
          remoteUpdatedAt,
        );
        return remoteSnapshot;
      }

      if (_snapshotHasContent(local) &&
          localUpdatedAt.isAfter(remoteUpdatedAt)) {
        await _pushSnapshot(preferences, local);
      }
    } catch (_) {
      // Keep the app usable offline or during backend issues.
    }

    return local;
  }

  Future<void> _enqueueSync(SharedPreferences preferences) {
    if (_syncApiBaseUrl.isEmpty) {
      return Future<void>.value();
    }

    _syncQueue = _syncQueue.then((_) async {
      try {
        await _pushSnapshot(preferences, _readLocalSnapshot(preferences));
      } catch (_) {
        // Local saves should still succeed if sync fails.
      }
    });

    return _syncQueue;
  }

  Future<void> _pushSnapshot(
    SharedPreferences preferences,
    AppStateSnapshot snapshot,
  ) async {
    final updatedAt = DateTime.now().toUtc();
    final remoteEntries = await _prepareEntriesForUpload(
      snapshot.entries,
      await _uploadOwnerKey(preferences),
    );

    if (_authService.isAuthenticated) {
      final response = await _client.post(
        Uri.parse('$_syncApiBaseUrl/app-state'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_authService.authToken}',
        },
        body: jsonEncode({
          'snapshot': {
            'updatedAt': updatedAt.toIso8601String(),
            'entries': remoteEntries,
            'dietGoal': snapshot.dietGoal?.toMap(),
            'miraMessages': snapshot.miraMessages,
          },
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Sync failed with status ${response.statusCode}');
      }

      await preferences.setString(
        _snapshotUpdatedAtKey,
        updatedAt.toIso8601String(),
      );
      return;
    }

    final response = await _client.post(
      Uri.parse('$_syncApiBaseUrl/sync-state'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': await _deviceId(preferences),
        'snapshot': {
          'updatedAt': updatedAt.toIso8601String(),
          'entries': remoteEntries,
          'dietGoal': snapshot.dietGoal?.toMap(),
          'miraMessages': snapshot.miraMessages,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Sync failed with status ${response.statusCode}');
    }

    await preferences.setString(
      _snapshotUpdatedAtKey,
      updatedAt.toIso8601String(),
    );
  }

  Future<List<Map<String, dynamic>>> _prepareEntriesForUpload(
    List<MealEntry> entries,
    String uploadOwnerKey,
  ) async {
    final remoteEntries = <Map<String, dynamic>>[];

    for (final entry in entries) {
      final map = entry.toMap();
      map['imagePaths'] =
          await _uploadImagePaths(entry.imagePaths, uploadOwnerKey);
      remoteEntries.add(map);
    }

    return remoteEntries;
  }

  Future<List<String>> _uploadImagePaths(
    List<String> imagePaths,
    String uploadOwnerKey,
  ) async {
    final uploaded = <String>[];

    for (final path in imagePaths) {
      if (_isRemotePath(path)) {
        uploaded.add(path);
        continue;
      }

      final file = _fileFromStoredPath(path);
      if (!await file.exists()) {
        continue;
      }

      final bytes = await file.readAsBytes();
      final response = await _client.post(
        Uri.parse('$_syncApiBaseUrl/upload-image'),
        headers: {
          'Content-Type': 'application/json',
          if (_authService.isAuthenticated)
            'Authorization': 'Bearer ${_authService.authToken}',
        },
        body: jsonEncode({
          'deviceId': uploadOwnerKey,
          'fileName': file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'meal-photo.jpg',
          'mimeType': _guessMimeType(file.path),
          'base64': base64Encode(bytes),
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'Image upload failed with status ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      uploaded.add(decoded['url'] as String);
    }

    return uploaded;
  }

  Future<Map<String, dynamic>?> _fetchRemoteSnapshot(String deviceId) async {
    final response = await _client.get(
      Uri.parse('$_syncApiBaseUrl/sync-state?deviceId=$deviceId'),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Remote snapshot fetch failed with status ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['snapshot'] as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> _fetchAuthenticatedSnapshot() async {
    final response = await _client.get(
      Uri.parse('$_syncApiBaseUrl/app-state'),
      headers: {
        'Authorization': 'Bearer ${_authService.authToken}',
      },
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Remote snapshot fetch failed with status ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['snapshot'] as Map<String, dynamic>?;
  }

  Future<AppStateSnapshot> _snapshotFromRemotePayload(
    Map<String, dynamic> payload,
  ) async {
    final remoteEntries = (payload['entries'] as List<dynamic>? ?? const [])
        .map(
            (item) => MealEntry.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList();

    final localizedEntries = <MealEntry>[];
    for (final entry in remoteEntries) {
      localizedEntries.add(
        entry.copyWith(
          imagePaths: await _localizeRemoteImages(entry.imagePaths),
        ),
      );
    }

    final rawDietGoal = payload['dietGoal'];
    final rawMessages = payload['miraMessages'] as List<dynamic>? ?? const [];

    return AppStateSnapshot(
      entries: localizedEntries,
      dietGoal: rawDietGoal is Map<String, dynamic>
          ? DietGoal.fromMap(rawDietGoal)
          : rawDietGoal is Map
              ? DietGoal.fromMap(Map<String, dynamic>.from(rawDietGoal))
              : null,
      miraMessages: rawMessages
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }

  Future<List<String>> _localizeRemoteImages(List<String> imagePaths) async {
    final localized = <String>[];
    final docsDir = await getApplicationDocumentsDirectory();
    final syncDir = Directory('${docsDir.path}/synced_images');
    if (!await syncDir.exists()) {
      await syncDir.create(recursive: true);
    }

    for (final path in imagePaths) {
      if (!_isRemotePath(path)) {
        localized.add(path);
        continue;
      }

      final localFile = File(
        '${syncDir.path}/${_stablePathToken(path)}${_extensionForRemotePath(path)}',
      );

      if (!await localFile.exists()) {
        final response = await _client.get(Uri.parse(path));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await localFile.writeAsBytes(response.bodyBytes);
        } else {
          continue;
        }
      }

      localized.add(localFile.path);
    }

    return localized;
  }

  Future<void> _writeLocalSnapshot(
    SharedPreferences preferences,
    AppStateSnapshot snapshot,
    DateTime updatedAt,
  ) async {
    await preferences.setString(
      _storageKey,
      MealEntry.encodeList(snapshot.entries),
    );

    if (snapshot.dietGoal == null) {
      await preferences.remove(_dietGoalKey);
    } else {
      await preferences.setString(_dietGoalKey, snapshot.dietGoal!.encode());
    }

    await preferences.setString(
      _miraMessagesKey,
      jsonEncode(snapshot.miraMessages),
    );
    await preferences.setString(
      _snapshotUpdatedAtKey,
      updatedAt.toIso8601String(),
    );
  }

  Future<void> _markSnapshotUpdated(SharedPreferences preferences) {
    return preferences.setString(
      _snapshotUpdatedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<({AppStateSnapshot snapshot, bool changed})>
      _normalizeSnapshotImagePaths(
    AppStateSnapshot snapshot,
  ) async {
    var changed = false;
    final normalizedEntries = <MealEntry>[];

    for (final entry in snapshot.entries) {
      final normalizedPaths = <String>[];
      var entryChanged = false;

      for (final path in entry.imagePaths) {
        final normalizedPath = await _normalizeStoredImagePath(path);
        normalizedPaths.add(normalizedPath);
        if (normalizedPath != path) {
          entryChanged = true;
        }
      }

      normalizedEntries.add(
        entryChanged ? entry.copyWith(imagePaths: normalizedPaths) : entry,
      );
      changed = changed || entryChanged;
    }

    if (!changed) {
      return (snapshot: snapshot, changed: false);
    }

    return (
      snapshot: AppStateSnapshot(
        entries: normalizedEntries,
        dietGoal: snapshot.dietGoal,
        miraMessages: snapshot.miraMessages,
      ),
      changed: true,
    );
  }

  Future<String> _normalizeStoredImagePath(String path) async {
    if (_isRemotePath(path)) {
      return path;
    }

    final directFile = _fileFromStoredPath(path);
    if (await directFile.exists()) {
      return directFile.path;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final repairedPath =
        _repairPathInDocumentsDirectory(path, documentsDirectory.path);
    if (repairedPath != null) {
      return repairedPath;
    }

    return path;
  }

  Future<String> _deviceId(SharedPreferences preferences) async {
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final deviceId =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await preferences.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  Future<String> _uploadOwnerKey(SharedPreferences preferences) async {
    if (_authService.isAuthenticated) {
      final userId = _authService.session?.userId ?? 'user';
      return 'user_$userId';
    }
    return _deviceId(preferences);
  }

  bool _snapshotHasContent(AppStateSnapshot snapshot) {
    return snapshot.entries.isNotEmpty ||
        snapshot.dietGoal != null ||
        snapshot.miraMessages.isNotEmpty;
  }

  DateTime _parseTimestamp(String? raw) {
    return DateTime.tryParse(raw ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  bool _isRemotePath(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  String _stablePathToken(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  String _extensionForRemotePath(String path) {
    final uri = Uri.tryParse(path);
    final lastSegment =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex == -1) {
      return '.jpg';
    }
    return lastSegment.substring(dotIndex);
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.heic')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }
}

File _fileFromStoredPath(String path) {
  if (path.startsWith('file://')) {
    return File(Uri.parse(path).toFilePath());
  }

  final directFile = File(path);
  if (directFile.existsSync()) {
    return directFile;
  }

  for (final candidate in _candidateFilesForStalePath(path)) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }

  return directFile;
}

String? _repairPathInDocumentsDirectory(
    String path, String documentsDirectoryPath) {
  for (final candidate
      in _candidatePathsForStalePath(path, documentsDirectoryPath)) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

Iterable<File> _candidateFilesForStalePath(String path) sync* {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return;
  }

  yield* _candidatePathsForStalePath(path, '$home/Documents').map(File.new);
}

Iterable<String> _candidatePathsForStalePath(
  String path,
  String documentsDirectoryPath,
) sync* {
  const documentsMarker = '/Documents/';
  final documentsIndex = path.indexOf(documentsMarker);
  if (documentsIndex != -1) {
    final suffix = path.substring(documentsIndex + documentsMarker.length);
    if (suffix.isNotEmpty) {
      yield '$documentsDirectoryPath/$suffix';
    }
  }

  final fileName = _fileNameFromPath(path);
  if (fileName == null || fileName.isEmpty) {
    return;
  }

  yield '$documentsDirectoryPath/$fileName';
  yield '$documentsDirectoryPath/synced_images/$fileName';
}

String? _fileNameFromPath(String path) {
  final sanitized =
      path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
  final segments = sanitized.split('/');
  if (segments.isEmpty) {
    return null;
  }
  return segments.lastWhere((segment) => segment.isNotEmpty, orElse: () => '');
}
