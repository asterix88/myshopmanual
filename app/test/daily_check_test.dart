import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/screens/daily_check_screen.dart';

void main() {
  test('site pages stay in the app, WhatsApp and phone links open outside', () {
    expect(staysInDailyCheck(Uri.parse(dailyCheckUrl)), isTrue);
    expect(staysInDailyCheck(Uri.parse('https://heavy-equipment-inspection.vercel.app/login')), isTrue);
    expect(staysInDailyCheck(Uri.parse('about:blank')), isTrue);
    expect(staysInDailyCheck(Uri.parse('https://wa.me/628123')), isFalse);
    expect(staysInDailyCheck(Uri.parse('tel:0812')), isFalse);
    expect(staysInDailyCheck(Uri.parse('mailto:a@b.c')), isFalse);
    expect(staysInDailyCheck(Uri.parse('intent://scan#Intent;end')), isFalse);
  });

  test('the setGood script reports back to the app instead of an alert', () {
    expect(setAllGoodJs, contains("MyManual.postMessage('good:'"));
    expect(setAllGoodJs, isNot(contains('alert(')));
    expect(setAllGoodJs, contains('button[role="combobox"]'));
    expect(watchDropdownsJs, contains("MyManual.postMessage('combo:'"));
  });
}
