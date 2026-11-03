// Transitional installed-data identifiers. Do not retire before migration-build acceptance.
// Keeping these values active preserves the current phone until build N is implemented and verified.
abstract final class LegacyNames {
  static const databaseFile = 'openstrap.db';
  static const backupDirectory = 'OpenStrap Backups';
  static const syncLog = 'openstrap_sync.log';
  static const nativeLog = 'openstrap_native.log';
  static const exitLog = 'openstrap_exits.log';
  static const processingTaskId = 'wtf.openstrap.edge.bgsync';
  static const refreshTaskId = 'wtf.openstrap.edge.refresh';
  static const bleRestoreId = 'openstrap.ble.restore';
  static const bandUuidKey = 'openstrap.ble.band_uuid';
  static const backupPrefix = 'openstrap';
  static const backupNamePattern = r'^(?:whoop|openstrap)-(\d{8}-\d{6})(-\d+)?(\.db(\.gz)?|\.osbk)$';
  static const plaintextBackupPattern = r'^(?:whoop|openstrap)-\d{8}-\d{6}(-\d+)?\.db(\.gz)?$';
}
