/// Where this installation keeps its local data, and which key opens it (Phase 9 Slice 2,
/// D-346).
///
/// Three environments, decided by the build and nothing a person using the application can
/// change:
///
/// | | Folder | Database key |
/// |---|---|---|
/// | **production** | Windows: `%APPDATA%\Krishna Imperial\Krishna Imperial MIS Production`; Android: the production application's private storage | `krishna_mis.db_key.prod.v1`, on Windows in its own DPAPI file in that folder |
/// | **non-production** (dev, staging) | the platform default: on Windows `%APPDATA%\Krishna Imperial\Krishna Imperial MIS` | `krishna_mis.db_key.v1` in the platform store |
/// | **acceptance** | the folder the acceptance harness passes (D-246) | `krishna_mis.acceptance.db_key.v1` (D-249) |
///
/// The Windows production folder is built from the Windows roaming application-data
/// location and two fixed names; it is never derived from the folder the executable's
/// version resource names, because that is the legacy folder — the D-247 installation on
/// the project lead's workstation. A production build never calls
/// `getApplicationSupportDirectory()` on Windows, never reads or writes the shared
/// secure-storage plugin there, and copies nothing from the legacy folder. Production
/// starts empty and downloads what its signed-in person may receive.
///
/// This file is the only place in `lib/` that asks `path_provider` for the application
/// support folder; `test/release/release_build_guard_test.dart` holds that.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/protected_file_secret_storage.dart';
import 'package:krishna_mis/data/local/session_secret_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

enum StorageEnvironment { production, nonProduction, acceptance }

/// The fixed Windows folder names under the roaming application-data folder.
abstract final class WindowsDataFolders {
  /// `CompanyName` in `windows/runner/Runner.rc`.
  static const String company = 'Krishna Imperial';

  /// `ProductName` in `windows/runner/Runner.rc`: the folder every non-production build
  /// uses, and the D-247 installation's folder. Production must never resolve to it.
  static const String legacy = 'Krishna Imperial MIS';

  /// Production's own folder, approved by the project lead (D-346).
  static const String production = 'Krishna Imperial MIS Production';
}

/// Raised when a production location would land on the legacy folder. Unreachable by
/// construction; it exists so the impossible case stops rather than proceeds.
class ProductionStorageRefused implements Exception {
  const ProductionStorageRefused();

  @override
  String toString() =>
      'ProductionStorageRefused: the production data folder resolved to the folder '
      'other builds use';
}

/// A resolved location.
final class LocalStorageLocation {
  const LocalStorageLocation._({
    required this.environment,
    required this.directory,
    required this.keyName,
    this.keyStorage,
  });

  final StorageEnvironment environment;

  /// The folder, or null for non-production, which keeps the platform default exactly as
  /// before (and with it D-246's one-time session move, which only that case performs).
  final Directory? directory;

  /// Which stored key opens the database.
  final String keyName;

  /// Where that key is stored, or null for the platform plugin.
  final FlutterSecureStorage? keyStorage;

  /// The manager for this location's key.
  DatabaseKeyManager keyManager() =>
      DatabaseKeyManager(storage: keyStorage, keyName: keyName);

  /// The folder itself, resolving the platform default for non-production.
  Future<Directory> root() async =>
      directory ?? await platformApplicationSupportDirectory();

  /// Where staged bills are kept: inside this location, never anywhere else.
  Future<Directory> attachmentStagingDirectory() async {
    final staging = Directory(p.join((await root()).path, 'attachments'));
    await staging.create(recursive: true);
    return staging;
  }
}

/// The platform's application support folder: on Windows the folder the executable's
/// version resource names, which is the legacy, non-production folder.
///
/// The only call to `path_provider` for it in `lib/`. Production never reaches this on
/// Windows; on Android it is the production application's own private folder.
Future<Directory> platformApplicationSupportDirectory() =>
    getApplicationSupportDirectory();

/// Which environment's storage a build uses. An acceptance folder always wins, so a test
/// run can never reach a production or a development installation.
StorageEnvironment storageEnvironmentFor({
  required bool production,
  Directory? acceptanceDirectory,
}) => acceptanceDirectory != null
    ? StorageEnvironment.acceptance
    : production
    ? StorageEnvironment.production
    : StorageEnvironment.nonProduction;

/// The Windows production folder under [roamingAppData]: a pure function, so a host test
/// can assert it without either platform.
String windowsProductionDataPath(String roamingAppData) => p.join(
  roamingAppData,
  WindowsDataFolders.company,
  WindowsDataFolders.production,
);

/// The legacy (non-production, D-247) Windows folder under [roamingAppData].
String windowsLegacyDataPath(String roamingAppData) => p.join(
  roamingAppData,
  WindowsDataFolders.company,
  WindowsDataFolders.legacy,
);

/// Resolves the location for this build.
///
/// The seams exist for host tests; the application passes only [production] and, from the
/// acceptance harness alone, [acceptanceDirectory].
Future<LocalStorageLocation> resolveLocalStorage({
  required bool production,
  Directory? acceptanceDirectory,
  String? operatingSystem,
  Future<String> Function()? roamingAppData,
  Future<Directory> Function()? platformSupportDirectory,
  DataProtector protector = const DpapiDataProtector(),
}) async {
  final environment = storageEnvironmentFor(
    production: production,
    acceptanceDirectory: acceptanceDirectory,
  );
  final keyName = databaseKeyNameFor(
    appDataDirectory: acceptanceDirectory,
    production: production,
  );
  switch (environment) {
    case StorageEnvironment.acceptance:
      return LocalStorageLocation._(
        environment: environment,
        directory: acceptanceDirectory,
        keyName: keyName,
      );
    case StorageEnvironment.nonProduction:
      return LocalStorageLocation._(
        environment: environment,
        directory: null,
        keyName: keyName,
      );
    case StorageEnvironment.production:
      final os = operatingSystem ?? Platform.operatingSystem;
      if (os == 'windows') {
        final base = await (roamingAppData ?? windowsRoamingAppData)();
        final folder = windowsProductionDataPath(base);
        if (p.equals(folder, windowsLegacyDataPath(base)) ||
            p.basename(folder) != WindowsDataFolders.production) {
          throw const ProductionStorageRefused();
        }
        final directory = Directory(folder);
        return LocalStorageLocation._(
          environment: environment,
          directory: directory,
          keyName: keyName,
          keyStorage: ProtectedFileSecretStorage(
            directory: directory,
            protector: protector,
          ),
        );
      }
      // Android: the application's own private storage, which for the production
      // application id holds nothing any other build wrote.
      return LocalStorageLocation._(
        environment: environment,
        directory:
            await (platformSupportDirectory ??
                platformApplicationSupportDirectory)(),
        keyName: keyName,
      );
  }
}

/// `FOLDERID_RoamingAppData`, as `path_provider_windows` itself locates it, without the
/// application subfolder it appends and creates.
Future<String> windowsRoamingAppData() async {
  final folder = GUIDFromString(FOLDERID_RoamingAppData);
  final result = calloc<Pointer<Utf16>>();
  try {
    final hr = SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, NULL, result);
    if (FAILED(hr)) {
      throw const FileSystemException(
        'the Windows application data folder could not be located',
      );
    }
    try {
      return result.value.toDartString();
    } finally {
      CoTaskMemFree(result.value);
    }
  } finally {
    calloc.free(folder);
    calloc.free(result);
  }
}
