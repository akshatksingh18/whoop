import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Answers path_provider with one test folder.
///
/// Turning a kind off leaves the platform default, which throws
/// `UnimplementedError`, so a test can still prove what happens when that
/// directory is unavailable.
class RootPathProvider extends PathProviderPlatform {
  RootPathProvider(
    this.root, {
    this.documents = true,
    this.support = true,
    this.temporary = true,
  });

  final String root;
  final bool documents;
  final bool support;
  final bool temporary;

  @override
  Future<String?> getApplicationDocumentsPath() =>
      documents ? Future.value(root) : super.getApplicationDocumentsPath();

  @override
  Future<String?> getApplicationSupportPath() =>
      support ? Future.value(root) : super.getApplicationSupportPath();

  @override
  Future<String?> getTemporaryPath() =>
      temporary ? Future.value(root) : super.getTemporaryPath();

  @override
  Future<String?> getApplicationCachePath() async => root;

  @override
  Future<String?> getLibraryPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;

  @override
  Future<String?> getExternalStoragePath() async => root;
}
