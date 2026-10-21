package com.codesyncr.sigma.flutter

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import space.nimbusgo.sigma.SigmaException
import space.nimbusgo.sigma.SigmaFormat
import space.nimbusgo.sigma.SigmaHeader
import space.nimbusgo.sigma.SigmaSession
import space.nimbusgo.sigma.SigmaSheetView
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Dart answered a link request with a failure: its message, kept so the error can name it. */
private class LinkFailed(message: String) : Exception(message)

/**
 * One SigmaSheetView and its SigmaSession, talking to its SigmaSheet widget
 * over "sigma/sheet_<id>": the native side asks Dart for links and
 * reports the phase, save state, title and saves; Dart sends commands.
 */
internal class SheetPlatformView(private val context: Context, messenger: BinaryMessenger, id: Int, private val params: Map<*, *>?) :
    PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "sigma/sheet_$id")
    private val container = FrameLayout(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var session: SigmaSession? = null
    private var sheet: SigmaSheetView? = null
    /** The last link request ended in a failure from Dart, not the server. */
    @Volatile private var linkFailure: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Dart listens first, then starts the sheet, so the first link request has an answerer.
            "start" -> { start(); result.success(null) }
            "save" -> run(result) { it.save(); null }
            "export" -> run(result) { s ->
                val f = s.export(call.argument<String>("format")?.let { SigmaFormat.of(it) })
                mapOf("bytes" to f.data, "filename" to f.filename, "format" to f.format.value, "mimeType" to f.format.mimeType)
            }
            "undo" -> { sheet?.controller?.undo(); result.success(null) }
            "redo" -> { sheet?.controller?.redo(); result.success(null) }
            "reload" -> run(result) { it.reload(); null }
            "rename" -> run(result) { it.rename(call.argument<String>("title") ?: ""); null }
            else -> result.notImplemented()
        }
    }

    private fun start() {
        if (session != null) return
        val s = SigmaSession(context) {
            try {
                askDart().also { linkFailure = null }
            } catch (e: LinkFailed) {
                linkFailure = e.message
                throw SigmaException.Network(e.message ?: "The link could not be fetched.")
            }
        }
        session = s
        val v = SigmaSheetView(context)
        v.header = SigmaHeader(
            visible = params?.get("header") as? Boolean ?: true,
            back = params?.get("back") as? Boolean ?: true,
            logo = params?.get("logo") as? Boolean ?: true,
        )
        // Dart decides what back means: its onBack, or popping the route.
        v.onBack = { channel.invokeMethod("back", null) }
        v.open(s)
        sheet = v
        container.addView(v, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        watch(s)
    }

    /** Asks the widget's `link` function, on the main thread, for a signed link. */
    private suspend fun askDart(): String = withContext(Dispatchers.Main) {
        withTimeout(120_000) {
            suspendCancellableCoroutine { cont ->
                channel.invokeMethod("link", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val url = result as? String
                        if (url.isNullOrEmpty()) cont.resumeWithException(LinkFailed("Your link function returned no link."))
                        else cont.resume(url)
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        cont.resumeWithException(LinkFailed(message ?: "Your link function failed."))
                    }
                    override fun notImplemented() {
                        cont.resumeWithException(LinkFailed("The sheet is not on screen."))
                    }
                })
            }
        }
    }

    private fun watch(s: SigmaSession) {
        scope.launch {
            s.phase.collect { p ->
                when (p) {
                    SigmaSession.Phase.Loading -> send("phase", mapOf("phase" to "loading"))
                    SigmaSession.Phase.Ready -> send("phase", mapOf("phase" to "ready", "document" to s.document.value?.let { d ->
                        mapOf("id" to d.id, "title" to d.title, "filename" to d.filename, "format" to d.format.value, "mode" to d.mode.value, "test" to d.test)
                    }))
                    is SigmaSession.Phase.Failed -> send("phase", mapOf("phase" to "failed", "error" to error(p.error, linkFailure)))
                }
            }
        }
        scope.launch {
            s.saveState.collect { st ->
                when (st) {
                    SigmaSession.SaveState.Saved -> send("saveState", mapOf("state" to "saved"))
                    SigmaSession.SaveState.Unsaved -> send("saveState", mapOf("state" to "unsaved"))
                    SigmaSession.SaveState.Saving -> send("saveState", mapOf("state" to "saving"))
                    is SigmaSession.SaveState.Failed -> send("saveState", mapOf("state" to "failed", "error" to error(st.error, null)))
                }
            }
        }
        // The title is empty until the sheet opens; only a real one is news.
        scope.launch { s.title.collect { t -> if (t.isNotEmpty() || s.phase.value == SigmaSession.Phase.Ready) send("title", mapOf("title" to t)) } }
        scope.launch { s.lastSaved.collect { at -> if (at != null) send("saved", mapOf("at" to at)) } }
    }

    private fun send(method: String, body: Map<String, Any?>) = channel.invokeMethod(method, body)

    private fun run(result: MethodChannel.Result, block: suspend (SigmaSession) -> Any?) {
        val s = session ?: return result.error("not_ready", "The sheet is still opening.", null)
        scope.launch {
            try {
                result.success(block(s))
            } catch (e: SigmaException) {
                result.error(code(e, null), e.message, if (e is SigmaException.Server) mapOf("status" to e.status) else null)
            } catch (e: Exception) {
                result.error("server", e.message ?: "Sigma could not complete the request.", null)
            }
        }
    }

    /** Saves what was typed last, then stops the engine. */
    override fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
        val s = session ?: return
        session = null
        CoroutineScope(Dispatchers.Main).launch {
            withContext(NonCancellable) { runCatching { s.save() } }
            s.close()
        }
    }

    private companion object {
        /** The Dart error code for a SigmaException. */
        fun code(e: SigmaException, linkFailure: String?): String = when (e) {
            is SigmaException.Unauthorized -> "unauthorized"
            is SigmaException.QuotaExceeded -> "quota_exceeded"
            is SigmaException.NotFound -> "not_found"
            is SigmaException.LinkExpired -> "link_expired"
            is SigmaException.LinkInvalid -> "link_invalid"
            is SigmaException.Engine -> "engine"
            is SigmaException.NotReady -> "not_ready"
            is SigmaException.Editor -> "editor"
            is SigmaException.Server -> "server"
            is SigmaException.Network -> if (linkFailure != null && e.message == linkFailure) "link_failed" else "network"
        }

        fun error(e: SigmaException, linkFailure: String?): Map<String, Any?> = buildMap {
            put("code", code(e, linkFailure))
            put("message", e.message ?: "")
            if (e is SigmaException.Server) put("status", e.status)
        }
    }
}
