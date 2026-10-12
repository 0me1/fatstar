import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppVersion {
  const AppVersion(this.version, this.build);
  final String version, build;
  String get label => 'Calorie Diary $version ($build)';
}

const appVersionChannel = MethodChannel('com.fatstar.calorie_diary/app_info');
Future<AppVersion> readAppVersion() async {
  final info = await appVersionChannel.invokeMapMethod<String, dynamic>(
    'version',
  );
  final version = info?['version'], build = info?['build'];
  if (version is! String ||
      version.isEmpty ||
      build is! String ||
      build.isEmpty) {
    throw StateError('Версия приложения недоступна');
  }
  return AppVersion(version, build);
}

final appVersionProvider = FutureProvider<AppVersion>(
  (ref) => readAppVersion(),
);
