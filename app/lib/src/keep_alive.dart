import 'package:flutter/services.dart';

import 'diagnostics.dart';

/// A foreground service with a notification while manuals download: Android
/// stops (or cuts the network of) apps in the background after a few
/// seconds on many phones, which paused downloads when the user switched to
/// WhatsApp.
class KeepAlive {
  static const _channel = MethodChannel('mymanual/keepalive');

  static Future<void> start(String text) async {
    try {
      await _channel.invokeMethod<void>('start', {'text': text});
    } on MissingPluginException {
      // Tests and platforms without the service.
    } catch (e) {
      Diagnostics.log('keepalive start: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Tests and platforms without the service.
    } catch (e) {
      Diagnostics.log('keepalive stop: $e');
    }
  }
}
