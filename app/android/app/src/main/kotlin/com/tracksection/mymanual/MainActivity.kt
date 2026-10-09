package com.tracksection.mymanual

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mymanual/diagnostics").setMethodCallHandler { call, result ->
            when (call.method) {
                "exits" -> result.success(exits())
                "memory" -> result.success(memory())
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mymanual/keepalive").setMethodCallHandler { call, result ->
            // Stop goes through the service too: it arrives after start, so the
            // service always reaches startForeground before it ends.
            val intent = Intent(this, KeepAliveService::class.java)
            when (call.method) {
                "start", "stop" -> {
                    intent.putExtra("text", call.argument<String>("text"))
                    intent.putExtra("stop", call.method == "stop")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Why the app stopped the last few times (Android 11 and newer), so a
     *  force close can be told apart: out of memory, a crash, or not responding. */
    private fun exits(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.getHistoricalProcessExitReasons(packageName, 0, 8).map {
            mapOf(
                "time" to it.timestamp,
                "reason" to reasonName(it.reason),
                "description" to it.description,
                "pssKb" to it.pss,
                "rssKb" to it.rss,
                "importance" to it.importance,
            )
        }
    }

    private fun memory(): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return mapOf(
            "totalMb" to info.totalMem / 1048576,
            "availMb" to info.availMem / 1048576,
            "lowMemory" to info.lowMemory,
            "memoryClassMb" to am.memoryClass,
        )
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "UNKNOWN($reason)"
    }
}
