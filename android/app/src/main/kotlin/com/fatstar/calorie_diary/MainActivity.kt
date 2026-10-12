package com.fatstar.calorie_diary

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.fatstar.calorie_diary/app_info").setMethodCallHandler { call, result ->
            if (call.method != "version") {
                result.notImplemented()
            } else {
                try {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                        info.longVersionCode else info.versionCode.toLong()
                    result.success(mapOf("version" to info.versionName, "build" to code.toString()))
                } catch (error: Exception) {
                    result.error("APP_INFO", "Unable to read installed package version", null)
                }
            }
        }
    }
}
