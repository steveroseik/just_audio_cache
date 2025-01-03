import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_cache/src/io_client.dart';
import 'package:just_audio_cache/src/parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

extension AudioPlayerExtension on AudioPlayer {
  static SharedPreferences? _sp;

  /// Check if the file corresponds the url exists in local
  Future<bool> existedInLocal({required String url}) async {
    if (_sp == null) _sp = await SharedPreferences.getInstance();

    return _sp!.getString(url) != null;
  }

  /// Get audio file cache path
  Future<String?> getCachedPath({required String url}) async {
    if (_sp == null) _sp = await SharedPreferences.getInstance();

    return _sp!.getString(getUrlSuffix(url));
  }

  /// Get audio from local if exist, otherwise download from network
  /// [url] is your audio source, a unique key that represents the stored file path,
  /// [path] the storage path you want to save your cache
  /// [pushIfNotExisted] if true, when the file not exists, would download the file and push in cache
  /// [excludeCallback] a callback function where you can specify which file you don't want to be cached,
  ///  (return `true` if we want to exclude the specific source)
  Future<Duration?> dynamicSet({
    required String url,
    String? path,
    bool pushIfNotExisted = true,
    bool excludeCallback(url)?,
    bool preload = true,
  }) async {
    if (_sp == null) _sp = await SharedPreferences.getInstance();

    if (excludeCallback != null) {
      pushIfNotExisted = excludeCallback(url);
    }

    final dirPath = path ?? (await _openDir()).path;
    // File check
    if (await existedInLocal(url: url)) {
      // existed, play from local file
      final localPath = await _buildPath(url, path);
      try {
        return await setFilePath(localPath, preload: preload);
      } catch (e) {
        print(e);
      }
    }

    final duration = await setUrl(url, preload: preload);

    // download to cache after setUrl in order to show the audio buffer state
    if (pushIfNotExisted) {
      final localPath = await _buildPath(url, path);
      IoClient.download(url: url, path: localPath).then((storedPath) {
        if (storedPath != null) {
          _sp!.setString(url, storedPath);
        }
      });
    }

    return duration;
  }

  Future<String> _buildPath(String url, String? path) async {
    final key = getUrlSuffix(url);
    final dirPath = path ?? (await _openDir()).path;
    return dirPath + '/' + key;
  }

  /// Cache a collection of audio source
  /// [sources] target sources for your playlist
  /// [path] The dir path where sources store
  /// [excluded] the sources you don't want to save in storage
  Future<List<Duration?>> dynamicSetAll(
    List<String> sources, [
    String? path,
    List<String>? excluded,
  ]) async {
    var durations = <Duration?>[];
    for (final url in sources) {
      durations.add(
        await dynamicSet(
          url: url,
          path: path,
          excludeCallback: (url) => excluded != null && excluded.contains(url),
        ),
      );
    }
    return durations;
  }

  Future<void> cacheFile({required String url, String? path}) async {
    final localPath = await _buildPath(url, path);
    final storedPath = await IoClient.download(url: url, path: localPath);
    if (storedPath != null) {
      _sp!.setString(url, storedPath);
    }
  }

  /// Clear all the cache in the app directory
  Future<void> clearCache({String? path}) async {
    try {
      // Get the directory
      final dir = path != null ? Directory(path) : (await _openDir());

      // Check if the directory exists
      if (await dir.exists()) {
        // Delete all contents of the directory recursively
        await for (var entity in dir.list(recursive: false)) {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        }

        // Delete the directory itself
        await dir.delete();
      }
      print('Cache cleared successfully.');
    } catch (e, s) {
      print('Error clearing cache: $e');
      print(s);
    }
  }

  Future<void> playFromFile({required String filePath}) async {
    await setFilePath(filePath);
    return await play();
  }

  /*Future<bool> _isKeyExisted(String key) async {
    if (_sp == null) _sp = await SharedPreferences.getInstance();

    return _sp!.getString(key) != null;
  }*/

  Future<Directory> _openDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final Directory targetDir = Directory(dir.path + '/audio_cache');
    if (!targetDir.existsSync()) {
      targetDir.createSync();
    }
    return targetDir;
  }
}
