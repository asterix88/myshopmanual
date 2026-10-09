import 'dart:async';

import 'package:mymanual/src/widgets/excavator_loader.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The loading excavator loops forever, so pumpAndSettle would never return.
  ExcavatorLoader.animate = false;
  await testMain();
}
