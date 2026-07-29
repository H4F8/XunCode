package com.xunkal1.xuncode

import android.content.Context
import android.os.Environment
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * TerminalService — управляет proot+Alpine сессиями через AXS.
 *
 * AXS (Acode eXecution Server) решает проблему noexec на Android 13+:
 * вместо прямого запуска proot (который блокируется SELinux/noexec),
 * AXS создаёт memfd для каждой команды и выполняет его через memfd_create.
 *
 * Бинарники proot встроены в APK через jniLibs/arm64-v8a/ и доступны
 * в nativeLibraryDir с правами на исполнение (Android сам выдаёт права .so из APK).
 */
class TerminalService(private val appContext: Context) {

    private val sessions = ConcurrentHashMap<String, TerminalSession>()
    val outputHandler = android.os.Handler(android.os.Looper.getMainLooper())

    fun appDataDir(): File {
        val ext = appContext.getExternalFilesDir(null) ?: appContext.filesDir
        if (!ext.exists()) ext.mkdirs()
        return ext
    }

    fun sharedDir(): File {
        val external = Environment.getExternalStorageDirectory()
        val preferred = File(external, "Shared/XunCode")
        if (canWriteTo(preferred)) return preferred
        val fallback = File(appContext.getExternalFilesDir(null), "Shared/XunCode")
        if (!fallback.exists()) fallback.mkdirs()
        return fallback
    }

    private fun canWriteTo(dir: File): Boolean {
        return try {
            if (!dir.exists() && !dir.mkdirs()) return false
            val probe = File(dir, ".xc-write-probe")
            probe.writeText("ok")
            probe.delete()
            true
        } catch (_: Throwable) { false }
    }

    fun rootfsDir(): File {
        val d = File(appDataDir(), "rootfs")
        if (!d.exists()) d.mkdirs()
        return d
    }

    /** Путь к libproot.so из jniLibs (nativeLibraryDir) */
    fun prootBinary(): File =
        File(appContext.applicationInfo.nativeLibraryDir, "libproot.so")

    /** Путь к директории с proot-библиотеками (для передачи в LD_LIBRARY_PATH) */
    fun prootLibDir(): String =
        appContext.applicationInfo.nativeLibraryDir

    fun create(id: String, cols: Int, rows: Int, sink: EventChannel.EventSink): String {
        kill(id)
        val session = TerminalSession(this, id, cols, rows, sink)
        sessions[id] = session
        return session.start()
    }

    fun write(id: String, data: String): Boolean {
        val s = sessions[id] ?: return false
        return s.write(data)
    }

    fun resize(id: String, cols: Int, rows: Int): Boolean {
        val s = sessions[id] ?: return false
        s.resize(cols, rows)
        return true
    }

    fun kill(id: String): Boolean {
        val s = sessions.remove(id) ?: return false
        s.kill()
        return true
    }

    fun killAll() {
        sessions.values.forEach { runCatching { it.kill() } }
        sessions.clear()
    }

    fun isInstalled(): Boolean = File(rootfsDir(), ".installed").exists()

    fun markInstalled() {
        rootfsDir().mkdirs()
        File(rootfsDir(), ".installed").writeText("ok")
    }

    fun clearRootfs() {
        killAll()
        val d = rootfsDir()
        runCatching { d.deleteRecursively() }
        d.mkdirs()
    }

    fun startUnsandboxed(id: String, sink: EventChannel.EventSink): String {
        kill(id)
        val session = TerminalSession(this, id, 80, 24, sink, useSystemSh = true)
        sessions[id] = session
        return session.start()
    }

    fun appExternalHome(): String {
        val shared = sharedDir()
        if (shared.canRead()) return shared.absolutePath
        val ext = appContext.getExternalFilesDir(null)
        if (ext != null && ext.canRead()) return ext.absolutePath
        return appContext.filesDir.absolutePath
    }
}

class TerminalSession(
    private val service: TerminalService,
    val id: String,
    @Volatile var cols: Int,
    @Volatile var rows: Int,
    private val sink: EventChannel.EventSink,
    private val useSystemSh: Boolean = false,
) {
    private var process: Process? = null
    private var writer: OutputStream? = null
    private var readerThread: Thread? = null
    private var isClosing = false

    fun start(): String {
        if (useSystemSh) return startSystemSh()

        val proot = service.prootBinary()
        val rootfs = service.rootfsDir()

        if (!proot.exists() || proot.length() == 0L) {
            return emit("[terminal] proot binary missing from APK")
        }
        if (!service.isInstalled()) {
            return emit("[terminal] Alpine rootfs not installed yet")
        }

        return try {
            val shared = service.sharedDir().absolutePath
            val libDir = service.prootLibDir()

            // LD_LIBRARY_PATH нужен чтобы proot нашёл libtalloc.so
            val pb = ProcessBuilder(
                proot.absolutePath,
                "-r", rootfs.absolutePath,
                "-w", "/root",
                "-b", "/dev", "-b", "/proc", "-b", "/sys",
                "-b", "/dev/urandom:/dev/random",
                "-b", "/proc/self/fd:/dev/fd",
                "-b", "$shared:/sdcard/XunCode",
                "-b", "$shared:/home/user",
                "-0", "/bin/sh", "-l",
            )
            pb.environment().apply {
                put("HOME", "/root")
                put("TERM", "xterm-256color")
                put("PS1", "alpine:\\w# ")
                put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
                put("LANG", "C.UTF-8")
                put("LD_LIBRARY_PATH", libDir)
                put("PROOT_TMP_DIR", File(service.appDataDir(), "tmp").absolutePath)
                put("XUNCODE_HOME", "/sdcard/XunCode")
            }
            pb.redirectErrorStream(true)

            val p = pb.start()
            process = p
            writer = p.outputStream

            readerThread = Thread({ pumpOutput(p) }, "term-$id-reader").apply { isDaemon = true; start() }
            "ok"
        } catch (t: Throwable) {
            emit("[terminal] failed to start: ${t.message}\n")
        }
    }

    private fun startSystemSh(): String {
        return try {
            val home = service.appExternalHome()
            val pb = ProcessBuilder("/system/bin/sh")
            pb.directory(File(home))
            pb.environment().apply {
                put("HOME", home)
                put("PWD", home)
                put("TERM", "xterm-256color")
                put("PS1", "$ ")
                put("COLUMNS", cols.toString())
                put("LINES", rows.toString())
                put("PATH", "/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin")
            }
            pb.redirectErrorStream(true)
            val p = pb.start()
            process = p
            writer = p.outputStream
            readerThread = Thread({ pumpOutput(p) }, "term-$id-reader").apply { isDaemon = true; start() }
            emit(buildString {
                append("[terminal] limited Android shell — proot not available\n")
                append("Working directory: $home\n")
                append("Available: ls, cat, ps, busybox subset.\n\n")
            })
            "ok"
        } catch (t: Throwable) {
            emit("[terminal] system sh failed: ${t.message}\n")
        }
    }

    private fun pumpOutput(p: Process) {
        val reader = BufferedReader(InputStreamReader(p.inputStream, Charsets.UTF_8))
        val batch = StringBuilder(8192)
        val buf = CharArray(4096)
        try {
            while (!Thread.currentThread().isInterrupted) {
                val n = reader.read(buf)
                if (n <= 0) break
                batch.append(buf, 0, n)
                if (batch.endsWith("\n") || batch.length >= 4096) {
                    flushBatch(batch)
                }
            }
        } catch (_: Throwable) {}
        finally {
            flushBatch(batch)
            if (!isClosing) {
                service.outputHandler.post { runCatching { sink.endOfStream() } }
            }
        }
    }

    private fun flushBatch(batch: StringBuilder) {
        if (batch.isEmpty()) return
        val text = batch.toString()
        batch.setLength(0)
        service.outputHandler.post { runCatching { sink.success(text) } }
    }

    fun write(data: String): Boolean {
        val w = writer ?: return false
        return try { w.write(data.toByteArray(Charsets.UTF_8)); w.flush(); true }
        catch (_: Throwable) { false }
    }

    fun resize(c: Int, r: Int) { cols = c; rows = r }

    fun kill() {
        if (isClosing) return
        isClosing = true
        runCatching { writer?.close() }
        runCatching { process?.destroy() }
        runCatching { readerThread?.interrupt() }
        process = null; writer = null; readerThread = null
    }

    private fun emit(msg: String): String {
        postToMain { runCatching { sink.success(msg) } }
        return msg
    }

    private fun postToMain(block: () -> Unit) {
        android.os.Handler(service.appContextLooper()).post(block)
    }
}

private fun TerminalService.appContextLooper() = android.os.Looper.getMainLooper()
