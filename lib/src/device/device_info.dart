/// Human-readable metadata about the current device, sent to the server on
/// activate/heartbeat so each seat is identifiable in the vendor's dashboard.
///
/// These map directly onto the WPLM `machines` columns. Put hardware details
/// the server has no dedicated column for (model, serial, …) into [platform] or
/// [name] so they remain visible, e.g. `platform: 'Windows 11 · Surface Pro 9'`.
class WplmDeviceInfo {
  const WplmDeviceInfo({
    this.name,
    this.hostname,
    this.platform,
    this.appVersion,
  });

  /// A friendly device name (e.g. the computer name or "Jane's iPhone").
  final String? name;

  /// The OS hostname.
  final String? hostname;

  /// OS + version, optionally with the hardware model appended.
  final String? platform;

  /// The host application's version string.
  final String? appVersion;
}

/// Supplies [WplmDeviceInfo] for the current device. Implement this with a
/// platform package (e.g. `device_info_plus`) in the app layer; the core SDK
/// stays pure-Dart and depends only on this interface.
abstract class DeviceInfoProvider {
  /// Return the current device's metadata.
  Future<WplmDeviceInfo> get();
}
