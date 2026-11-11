package com.jcstudiodev.rolostream

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.Locale

/// Reproductores Media3/ExoPlayer dibujados en una textura de Flutter. Dart pone los controles.
@OptIn(UnstableApi::class)
class NativeVideoPlayer(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val players = HashMap<Long, Entry>()
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, "com.rolostream/exo").setMethodCallHandler(this)
        EventChannel(messenger, "com.rolostream/exo/events").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(id: Long, type: String, data: Map<String, Any?> = emptyMap()) {
        events?.success(HashMap<String, Any?>(data).apply {
            put("id", id)
            put("type", type)
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "create") {
            val entry = Entry(textures.createSurfaceProducer())
            players[entry.id] = entry
            result.success(entry.id)
            return
        }
        val entry = players[call.argument<Number>("id")?.toLong() ?: -1L]
        if (entry == null) {
            result.success(null)
            return
        }
        when (call.method) {
            "open" -> entry.open(
                call.argument<String>("url")!!,
                call.argument<Map<String, String>>("headers") ?: emptyMap(),
                call.argument<Number>("startMs")?.toLong() ?: 0L,
                call.argument<String>("format"),
            )
            "play" -> entry.player.play()
            "pause" -> entry.player.pause()
            "stop" -> entry.player.stop()
            "seek" -> entry.seek(call.argument<Number>("ms")!!.toLong())
            "volume" -> entry.player.volume = call.argument<Number>("value")!!.toFloat()
            "speed" -> entry.player.setPlaybackSpeed(call.argument<Number>("value")!!.toFloat())
            "audio" -> entry.selectAudio(call.argument<Number>("index")!!.toInt())
            "quality" -> entry.selectQuality(call.argument<Number>("index")!!.toInt())
            "dispose" -> {
                entry.release()
                players.remove(entry.id)
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    fun disposeAll() {
        players.values.forEach { it.release() }
        players.clear()
    }

    private inner class Entry(private val producer: TextureRegistry.SurfaceProducer) : Player.Listener {
        val id = producer.id()
        val player: ExoPlayer
        private var audioGroups = listOf<Tracks.Group>()
        private var videoGroup: Tracks.Group? = null
        private var videoFormats = listOf<Int>()
        private var headers: Map<String, String> = emptyMap()

        private val ticker = object : Runnable {
            override fun run() {
                sendPosition()
                main.postDelayed(this, 250)
            }
        }

        init {
            // Arranca con poco búfer para que la imagen salga pronto, y acumula hasta 50 s después.
            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(15_000, 50_000, 1_000, 2_000)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
            val renderers = DefaultRenderersFactory(context).setEnableDecoderFallback(true)
            val http = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15_000)
                .setReadTimeoutMs(20_000)
            player = ExoPlayer.Builder(context, renderers)
                .setLoadControl(loadControl)
                .setMediaSourceFactory(DefaultMediaSourceFactory {
                    http.setDefaultRequestProperties(headers).createDataSource()
                })
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .build(),
                    true,
                )
                .setHandleAudioBecomingNoisy(true)
                .setWakeMode(C.WAKE_MODE_NETWORK)
                .setSeekBackIncrementMs(10_000)
                .setSeekForwardIncrementMs(10_000)
                .build()
            // Salta al fotograma clave más cercano: el salto es instantáneo en vez de decodificar
            // desde el anterior hasta el punto exacto.
            player.setSeekParameters(SeekParameters.CLOSEST_SYNC)
            player.addListener(this)
            player.setVideoSurface(producer.surface)
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    player.setVideoSurface(producer.surface)
                }

                override fun onSurfaceCleanup() {
                    player.setVideoSurface(null)
                }
            })
            main.post(ticker)
        }

        fun open(url: String, headers: Map<String, String>, startMs: Long, format: String?) {
            this.headers = headers
            val item = MediaItem.Builder().setUri(url)
            when (format) {
                "hls" -> item.setMimeType(MimeTypes.APPLICATION_M3U8)
                "dash" -> item.setMimeType(MimeTypes.APPLICATION_MPD)
            }
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .clearOverrides()
                .build()
            player.setMediaItem(item.build(), startMs)
            player.prepare()
            player.playWhenReady = true
        }

        fun seek(ms: Long) {
            player.seekTo(ms)
            sendPosition()
        }

        fun selectAudio(index: Int) {
            val group = audioGroups.getOrNull(index) ?: return
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
                .build()
        }

        /// -1 vuelve a la calidad automática.
        fun selectQuality(index: Int) {
            val group = videoGroup ?: return
            val builder = player.trackSelectionParameters.buildUpon()
            val track = videoFormats.getOrNull(index)
            if (track == null) {
                builder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)
            } else {
                builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, track))
            }
            player.trackSelectionParameters = builder.build()
        }

        private fun sendPosition() {
            val duration = player.duration
            emit(id, "position", mapOf(
                "position" to player.currentPosition,
                "buffered" to player.bufferedPosition,
                "duration" to if (duration == C.TIME_UNSET) 0L else duration,
            ))
        }

        override fun onPlaybackStateChanged(state: Int) {
            emit(id, "state", mapOf(
                "buffering" to (state == Player.STATE_BUFFERING),
                "ended" to (state == Player.STATE_ENDED),
            ))
            sendPosition()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emit(id, "playing", mapOf("value" to isPlaying))
        }

        override fun onPlayerError(error: PlaybackException) {
            emit(id, "error", mapOf("message" to "ExoPlayer ${error.errorCodeName}: ${error.message}"))
        }

        override fun onVideoSizeChanged(size: VideoSize) {
            if (size.width == 0 || size.height == 0) return
            producer.setSize(size.width, size.height)
            emit(id, "size", mapOf(
                "aspect" to size.width * size.pixelWidthHeightRatio.toDouble() / size.height,
            ))
        }

        override fun onRenderedFirstFrame() {
            emit(id, "firstFrame")
        }

        override fun onTracksChanged(tracks: Tracks) {
            audioGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO && it.isSupported }
            val audio = audioGroups.mapIndexed { i, g -> audioLabel(g.getTrackFormat(0), i) }
            val selectedAudio = audioGroups.indexOfFirst { it.isSelected }

            videoGroup = tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_VIDEO && it.isSupported }
            val group = videoGroup
            val heights = mutableListOf<Int>()
            val labels = mutableListOf<String>()
            if (group != null) {
                (0 until group.length)
                    .filter { group.isTrackSupported(it) && group.getTrackFormat(it).height > 0 }
                    .sortedByDescending { group.getTrackFormat(it).height }
                    .distinctBy { group.getTrackFormat(it).height }
                    .forEach {
                        heights.add(it)
                        labels.add("${group.getTrackFormat(it).height}p")
                    }
            }
            videoFormats = heights
            val selectedQuality = if (group != null && group.isAdaptiveSupported && player.trackSelectionParameters.overrides.isEmpty()) {
                -1
            } else {
                heights.indexOfFirst { group?.isTrackSelected(it) == true }
            }
            emit(id, "tracks", mapOf(
                "audio" to audio,
                "audioSelected" to selectedAudio,
                "qualities" to labels,
                "qualitySelected" to selectedQuality,
            ))
        }

        private fun audioLabel(format: Format, index: Int): String {
            format.label?.takeIf { it.isNotBlank() }?.let { return it }
            val language = format.language
            if (language != null && language != C.LANGUAGE_UNDETERMINED) {
                val name = Locale.forLanguageTag(language).getDisplayLanguage(Locale("es"))
                if (name.isNotBlank()) return name.replaceFirstChar { it.uppercase() }
            }
            return "Pista ${index + 1}"
        }

        fun release() {
            main.removeCallbacks(ticker)
            player.removeListener(this)
            player.release()
            producer.release()
        }
    }
}
