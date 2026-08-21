package com.xunkal1.xuncode

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TOR_CHANNEL = "com.xunkal1.xuncode/tor"
    private val TERMINAL_CHANNEL = "com.xunkal1.xuncode/terminal"
    private val TERMINAL_EVENTS = "com.xunkal1.xuncode/terminal/events"
    private val STORAGE_CHANNEL = "com.xunkal1.xuncode/storage"
    private val UPDATE_CHANNEL = "com.xunkal1.xuncode/update"

    private lateinit var terminalService: TerminalService
    private val sinks = mutableMapOf<String, EventChannel.EventSink>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        terminalService = TerminalService(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTor" -> {
                    runCatching {
                        val intent = android.content.Intent("org.torproject.android.intent.action.START")
                        intent.setPackage("org.torproject.android")
                        sendBroadcast(intent)
                    }
                    result.success(true)
                }
                "stopTor" -> {
                    runCatching {
                        val intent = android.content.Intent("org.torproject.android.intent.action.STOP")
                        intent.setPackage("org.torproject.android")
                        sendBroadcast(intent)
                    }
                    result.success(true)
                }
                "isRunning" -> result.success(false)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TERMINAL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAlpineInstalled" -> result.success(terminalService.isInstalled())
                "rootfsPath" -> result.success(terminalService.rootfsDir().absolutePath)
                "markAlpineInstalled" -> {
                    terminalService.markInstalled()
                    result.success(true)
                }
                "prootBinaryExists" -> {
                    val f = terminalService.prootBinary()
                    result.success(f.exists() && f.length() > 0)
                }
                "getNativeLibraryDir" -> {
                    result.success(applicationInfo.nativeLibraryDir)
                }
                "createUnsandboxed" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val sink = sinks[id]
                    if (sink == null) {
                        result.error("NO_SINK", "subscribe to events for id=$id first", null)
                    } else {
                        result.success(terminalService.startUnsandboxed(id, sink))
                    }
                }
                "create" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val cols = call.argument<Int>("cols") ?: 80
                    val rows = call.argument<Int>("rows") ?: 24
                    val sink = sinks[id]
                    if (sink == null) {
                        result.error("NO_SINK", "subscribe to events for id=$id first", null)
                    } else {
                        val msg = terminalService.create(id, cols, rows, sink)
                        result.success(msg)
                    }
                }
                "write" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val data = call.argument<String>("data") ?: ""
                    result.success(terminalService.write(id, data))
                }
                "resize" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    val cols = call.argument<Int>("cols") ?: 80
                    val rows = call.argument<Int>("rows") ?: 24
                    result.success(terminalService.resize(id, cols, rows))
                }
                "kill" -> {
                    val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("ARG", "missing id", null)
                    result.success(terminalService.kill(id))
                }
                "killAll" -> {
                    terminalService.killAll()
                    result.success(true)
                }
                "clearRootfs" -> {
                    runCatching { terminalService.clearRootfs() }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TERMINAL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val id = (arguments as? Map<*, *>)?.get("id") as? String
                        ?: (arguments as? String)
                        ?: return events.error("ARG", "missing id", null)
                    sinks[id] = events
                }
                override fun onCancel(arguments: Any?) {
                    val id = (arguments as? Map<*, *>)?.get("id") as? String
                        ?: (arguments as? String)
                        ?: return
                    sinks.remove(id)
                    terminalService.kill(id)
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallSource" -> {
                    val installer = runCatching {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                            packageManager.getInstallSourceInfo(packageName).installingPackageName
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getInstallerPackageName(packageName)
                        }
                    }.getOrNull()
                    result.success(installer)
                }
                "getAppVersion" -> {
                    val version = runCatching {
                        packageManager.getPackageInfo(packageName, 0).versionName
                    }.getOrNull()
                    if (version != null) result.success(version) else result.error("NO_VERSION", "versionName is null", null)
                }
                "openRustoreAppPage" -> {
                    val uri = android.net.Uri.parse("https://www.rustore.ru/catalog/app/$packageName")
                    val inStore = android.content.Intent(android.content.Intent.ACTION_VIEW, uri).apply {
                        setPackage("ru.vk.store")
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    val fallback = android.content.Intent(android.content.Intent.ACTION_VIEW, uri).apply {
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    var ok = runCatching { startActivity(inStore); true }.getOrDefault(false)
                    if (!ok) ok = runCatching { startActivity(fallback); true }.getOrDefault(false)
                    result.success(ok)
                }
                "openPath" -> {
                    // Открыть папку в системном файловом менеджере.
                    // file:// через url_launcher на Android 8+ не работает
                    // (FileUriExposedException), нужен SAF document URI.
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "missing path", null)
                    } else {
                        result.success(runCatching {
                            val dir = java.io.File(path)
                            if (!dir.exists()) dir.mkdirs()
                            val rel = dir.absolutePath
                                .removePrefix("/storage/emulated/0/")
                                .removePrefix("/")
                            val docUri = android.provider.DocumentsContract.buildDocumentUri(
                                "com.android.externalstorage.documents", "primary:$rel")
                            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                                .setDataAndType(docUri, "vnd.android.document/directory")
                                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            true
                        }.getOrDefault(false))
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "appDataDir" -> result.success(terminalService.appDataDir().absolutePath)
                "sharedDir" -> result.success(terminalService.sharedDir().absolutePath)
                "hasAllFilesAccess" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        result.success(android.os.Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "requestAllFilesAccess" -> {
                    runCatching {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                            val intent = android.content.Intent(
                                android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                android.net.Uri.parse("package:" + packageName),
                            )
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                }
                "ensureLayout" -> {
                    runCatching {
                        val app = terminalService.appDataDir()
                        listOf("plugins", "cache", "rootfs", "proot", "prefs", "database", "logs", "tmp")
                            .forEach { java.io.File(app, it).mkdirs() }
                        val shared = terminalService.sharedDir()
                        listOf("Projects", "Downloads", "Backups", "Exports", "Languages")
                            .forEach { java.io.File(shared, it).mkdirs() }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        runCatching { terminalService.killAll() }
        super.onDestroy()
    }
}
