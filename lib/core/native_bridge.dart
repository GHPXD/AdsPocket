import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('app.adspocket/native');
  static Future<List<String>> pendingShares() async =>
      (await channel.invokeListMethod<String>('pendingShares')) ?? [];
  static Future<String?> importBackup() =>
      channel.invokeMethod<String>('importBackup');
  static Future<bool> exportBackup(String json) async =>
      await channel.invokeMethod<bool>('exportBackup', json) ?? false;

  /// Saves text through the Android document picker (`json` or `csv`).
  static Future<bool> exportFile(String text, String name, String mime) async =>
      await channel.invokeMethod<bool>('exportFile', {
        'text': text,
        'name': name,
        'mime': mime,
      }) ??
      false;
  static Future<String?> pickImage() =>
      channel.invokeMethod<String>('pickImage');
  static Future<String?> imagePath(String file) =>
      channel.invokeMethod<String>('imagePath', file);

  /// Validated PNG/JPEG/WebP copy into private storage; null when rejected.
  static Future<String?> saveImageBytes(Uint8List bytes) =>
      channel.invokeMethod<String>('saveImageBytes', bytes);
  static Future<bool> openBrowser(Uri uri) async =>
      await channel.invokeMethod<bool>('openBrowser', uri.toString()) ?? false;
  static Future<void> deleteImage(String file) =>
      channel.invokeMethod<void>('deleteImage', file);
}
