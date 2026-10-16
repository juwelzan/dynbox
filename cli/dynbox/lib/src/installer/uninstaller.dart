import 'dart:io';

/// Manages uninstallation of DynBox binaries without touching user projects or Flutter SDKs.
class DynboxUninstaller {
  final Directory? installDirOverride;

  DynboxUninstaller({this.installDirOverride});

  /// Resolves the default user installation directory.
  Directory resolveInstallDir() {
    if (installDirOverride != null) return installDirOverride!;

    final envInstallDir = Platform.environment['DYNBOX_INSTALL_DIR'];
    if (envInstallDir != null && envInstallDir.trim().isNotEmpty) {
      return Directory(envInstallDir.trim());
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory('$localAppData\\DynBox\\bin');
      }
    }

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return Directory('$home/.dynbox/bin');
  }

  /// Lists all DynBox-owned files in the installation directory.
  List<File> listDynboxFiles() {
    final dir = resolveInstallDir();
    if (!dir.existsSync()) return [];

    final files = <File>[];
    try {
      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('dynbox') || name.startsWith('.dynbox')) {
            files.add(entity);
          }
        }
      }
    } catch (_) {}
    return files;
  }

  /// Performs uninstallation, deleting ONLY DynBox-owned binaries in the install directory.
  /// Never touches user projects, configuration, or the Flutter SDK.
  Future<String> uninstall() async {
    final dir = resolveInstallDir();
    if (!dir.existsSync()) {
      return 'DynBox installation directory "${dir.path}" does not exist.';
    }

    final files = listDynboxFiles();
    if (files.isEmpty) {
      return 'No DynBox binaries found in "${dir.path}".';
    }

    var deletedCount = 0;
    for (final file in files) {
      try {
        file.deleteSync();
        deletedCount++;
      } catch (e) {
        throw FileSystemException(
          'Failed to remove DynBox binary: ${file.path}: $e',
          file.path,
        );
      }
    }

    // If the directory is now completely empty, remove it safely
    try {
      if (dir.listSync().isEmpty) {
        dir.deleteSync();
      }
      // Also clean parent directory if it's .dynbox and empty
      final parent = dir.parent;
      if (parent.existsSync() &&
          parent.path.endsWith('.dynbox') &&
          parent.listSync().isEmpty) {
        parent.deleteSync();
      }
    } catch (_) {}

    return 'Successfully removed $deletedCount DynBox file(s) from ${dir.path}.';
  }
}
