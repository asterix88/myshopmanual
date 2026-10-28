import 'package:flutter/services.dart';

const _channel = MethodChannel('mymanual/haptics');

/// Two short buzzes when a PIN or NRP is refused. Uses the phone's vibrator
/// (works with touch vibration off); Flutter's haptics where there is none.
Future<void> buzzError() async {
  try {
    await _channel.invokeMethod<void>('error');
  } on Object {
    await HapticFeedback.heavyImpact();
  }
}
