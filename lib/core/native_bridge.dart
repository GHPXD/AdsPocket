import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('app.adspocket/native');
  static Future<List<String>> pendingShares() async =>
      (await channel.invokeListMethod<String>('pendingShares')) ?? [];
  static Future<String?> importBackup() =>
      channel.invokeMethod<String>('importBackup');
  static Future<bool> exportBackup(String json) async =>
      await channel.invokeMethod<bool>('exportBackup', json) ?? false;
  static Future<String?> pickImage() =>
      channel.invokeMethod<String>('pickImage');
  static Future<String?> imagePath(String file) =>
      channel.invokeMethod<String>('imagePath', file);
  static Future<bool> openBrowser(Uri uri) async =>
      await channel.invokeMethod<bool>('openBrowser', uri.toString()) ?? false;
  static Future<void> deleteImage(String file) =>
      channel.invokeMethod<void>('deleteImage', file);
}
