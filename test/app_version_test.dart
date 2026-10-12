import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/presentation/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appVersionChannel, null),
  );
  test('settings version reads installed package metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appVersionChannel, (call) async {
          expect(call.method, 'version');
          return {'version': '9.8.7', 'build': '654'};
        });
    expect((await readAppVersion()).label, 'Calorie Diary 9.8.7 (654)');
  });
  test('missing metadata never shows a hardcoded old version', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appVersionChannel, (_) async => null);
    await expectLater(readAppVersion(), throwsStateError);
  });
}
