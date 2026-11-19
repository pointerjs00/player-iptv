package pt.playeriptv.player_iptv

import android.app.Activity
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Motor ExoPlayer (Media3) do Android: o vídeo vai do MediaCodec direto para um `SurfaceView` real
 * (plano de vídeo do HWC, libertação de cada imagem alinhada ao vsync, `Surface.setFrameRate`), por
 * baixo da `FlutterView` transparente (ver MainActivity.getTransparencyMode). A interface Flutter
 * deixa a zona do vídeo transparente.
 *
 * Canal `player_iptv/exo` (métodos) e `player_iptv/exo/eventos` (eventos `{id, tipo, …}`).
 * Um só ExoPlayer de cada vez: um `criar` novo liberta o anterior; pedidos com um `id` antigo
 * são ignorados.
 *
 * Segurança: nunca registar nem devolver ao Dart o URL, os cabeçalhos, tokens ou cookies (nem
 * mensagens de exceções, que os podem conter): só códigos.
 */
@OptIn(UnstableApi::class)
class ReprodutorExo(private val activity: Activity, mensageiro: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val canal = MethodChannel(mensageiro, "player_iptv/exo")
    private val canalEventos = EventChannel(mensageiro, "player_iptv/exo/eventos")
    private var eventos: EventChannel.EventSink? = null
    private val principal = Handler(Looper.getMainLooper())

    private var player: ExoPlayer? = null
    private var idAtual = 0
    // o carregamento (abrir) atual, dado pelo Dart: vai em todos os eventos, para os atrasados do
    // canal anterior (mesmo id, no zapping) serem ignorados
    private var sessaoAtual = 0L
    private var tunel = false

    // Superfícies: um FrameLayout preto por baixo da FlutterView, com o SurfaceView do vídeo dentro.
    private var caixa: FrameLayout? = null
    private var superficie: SurfaceView? = null
    private var visivel = false
    private var videoDesligado = false // vídeo desligado por mostrar(false): o MediaCodec é largado

    // Formato da imagem
    private var modoAjuste = "ajustar"
    private var proporcaoPedida: Double? = null
    private var tamanhoVideo: VideoSize = VideoSize.UNKNOWN

    // Estado de um canal aberto
    private var prontoEnviado = false
    private var primeiraImagem = false // a 1.ª imagem deste canal já foi para a Surface
    private var jaTocou = false
    private var aCarregar = false
    private var ultimaPosicao = -1L
    private var descodificadorVideo: String? = null
    private var pausadoPeloSistema = false
    private var pausadoEm = 0L

    init {
        // Os logs do próprio Media3 (ex.: "Playback error" com o stack trace e as causas) podem
        // levar o URL, linhas da playlist e tokens: desligados por completo.
        androidx.media3.common.util.Log.setLogLevel(androidx.media3.common.util.Log.LOG_LEVEL_OFF)
        androidx.media3.common.util.Log.setLogStackTraces(false)
        canal.setMethodCallHandler(this)
        canalEventos.setStreamHandler(this)
    }

    // ---------------------------------------------------------------- canal

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventos = events
    }

    override fun onCancel(arguments: Any?) {
        eventos = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "criar") {
            result.success(criar(call.argument<Boolean>("tunel") ?: false))
            return
        }
        val id = (call.argument<Any>("id") as? Number)?.toInt()
        val p = player
        if (id == null || id != idAtual || p == null) {
            // pedido de um player antigo (zapping rápido) ou já descartado: ignora
            result.success(null)
            return
        }
        try {
            when (call.method) {
                "abrir" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("argumentos", "Falta o endereço", null)
                        return
                    }
                    val cabecalhos = cabecalhosDe(call.argument<Any>("cabecalhos"))
                    if (cabecalhos == null) {
                        result.error("argumentos", "Cabeçalhos inválidos", null) // sem URL nem valores
                        return
                    }
                    abrir(
                        p,
                        url,
                        cabecalhos,
                        (call.argument<Any>("inicioMs") as? Number)?.toLong(),
                        call.argument<String>("mime"),
                        (call.argument<Any>("sessao") as? Number)?.toLong() ?: 0L,
                    )
                    result.success(null)
                }
                "play" -> {
                    pausadoPeloSistema = false
                    if (p.playbackState == Player.STATE_IDLE) p.prepare()
                    p.play()
                    result.success(null)
                }
                "pausar" -> {
                    pausadoPeloSistema = false
                    p.pause()
                    result.success(null)
                }
                "parar" -> {
                    pausadoPeloSistema = false
                    p.stop()
                    aCarregar = false
                    result.success(null)
                }
                "descartar" -> {
                    libertar(esconder = true)
                    result.success(null)
                }
                "audio" -> {
                    escolherFaixa(p, C.TRACK_TYPE_AUDIO, call.argument<Int>("grupo"), call.argument<Int>("faixa"))
                    result.success(null)
                }
                "legenda" -> {
                    escolherFaixa(
                        p,
                        C.TRACK_TYPE_TEXT,
                        call.argument<Int>("grupo"),
                        call.argument<Int>("faixa"),
                        auto = call.argument<Boolean>("auto") == true,
                    )
                    result.success(null)
                }
                "volume" -> {
                    val v = (call.argument<Any>("v") as? Number)?.toFloat() ?: 1f
                    p.volume = v.coerceIn(0f, 1f)
                    result.success(null)
                }
                "velocidade" -> {
                    val v = (call.argument<Any>("v") as? Number)?.toFloat() ?: 1f
                    p.setPlaybackSpeed(v.coerceIn(0.25f, 4f))
                    result.success(null)
                }
                "ajuste" -> {
                    modoAjuste = call.argument<String>("modo") ?: "ajustar"
                    proporcaoPedida = (call.argument<Any>("proporcao") as? Number)?.toDouble()?.takeIf { it > 0 }
                    aplicarAjuste()
                    result.success(null)
                }
                "estatisticas" -> result.success(estatisticas(p))
                "mostrar" -> {
                    mostrar(p, call.argument<Boolean>("visivel") ?: false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // sem e.message: pode trazer o endereço
            Log.w(TAG, "${call.method} falhou: ${e.javaClass.simpleName}")
            result.error("exo", "O ExoPlayer recusou o pedido (${e.javaClass.simpleName})", null)
        }
    }

    // ---------------------------------------------------------------- player

    private fun criar(comTunel: Boolean): Int {
        libertar()
        tunel = comTunel
        val renderizadores = DefaultRenderersFactory(activity)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)
        val seletor = DefaultTrackSelector(activity)
        seletor.setParameters(seletor.buildUponParameters().setTunnelingEnabled(comTunel))
        // Direto: começa depressa (1,5 s) e retoma com 2,5 s; guarda até 30 s à frente.
        val carga = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15_000, 30_000, 1_500, 2_500)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        val p = ExoPlayer.Builder(activity, renderizadores)
            .setTrackSelector(seletor)
            .setLoadControl(carga)
            .setLooper(Looper.getMainLooper())
            .build()
        // pede ao ecrã a taxa do canal só quando a troca não corta a imagem; o modo de ecrã (50/60 Hz)
        // continua a ser pedido pelo canal player_iptv/ecra
        p.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS)
        p.addListener(ouvinte)
        p.addAnalyticsListener(analise)
        idAtual += 1
        sessaoAtual = 0L
        player = p
        // o vídeo escondido (mostrar(false) ou ainda nunca mostrado) começa com a faixa de vídeo
        // desligada: sem MediaCodec até ao mostrar(true)
        videoDesligado = !visivel
        if (videoDesligado) {
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true).build()
        }
        prepararSuperficie()
        superficie?.let { p.setVideoSurfaceHolder(it.holder) }
        principal.removeCallbacks(relogio)
        principal.postDelayed(relogio, INTERVALO_POSICAO_MS)
        Log.i(TAG, "criar: id=$idAtual tunel=$comTunel")
        return idAtual
    }

    private fun abrir(
        p: ExoPlayer,
        url: String,
        cabecalhos: Map<String, String>,
        inicioMs: Long?,
        mime: String?,
        sessao: Long,
    ) {
        // antes de tudo: os eventos que este abrir já emite (aCarregar) são desta sessão
        sessaoAtual = sessao
        prontoEnviado = false
        primeiraImagem = false
        jaTocou = false
        ultimaPosicao = -1L
        tamanhoVideo = VideoSize.UNKNOWN
        pausadoPeloSistema = false
        // zapping: o mesmo player (mesmo id) abre o canal seguinte; as faixas escolhidas no canal
        // anterior não se aplicam a este (a legenda desligada e o vídeo escondido mantêm-se)
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .build()
        val agente = cabecalhos.entries.firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }?.value
        val resto = cabecalhos.filterKeys { !it.equals("User-Agent", ignoreCase = true) }
        val http = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(15_000)
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(resto)
        if (!agente.isNullOrEmpty()) http.setUserAgent(agente)

        val uri = Uri.parse(url)
        val hls = eHls(url, uri, mime)
        // TS em direto: aceitar imagens-chave sem IDR (muitos canais IPTV) e detetar as unidades de
        // acesso (H.264 sem AUD), para começar no 1.º I-frame em vez de esperar por um IDR
        val flagsTs = DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
            DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
        val fonte: MediaSource = if (hls) {
            HlsMediaSource.Factory(http)
                .setExtractorFactory(DefaultHlsExtractorFactory(flagsTs, true))
                .setAllowChunklessPreparation(true)
                .createMediaSource(MediaItem.Builder().setUri(uri).setMimeType(MimeTypes.APPLICATION_M3U8).build())
        } else {
            val extratores = DefaultExtractorsFactory().setTsExtractorFlags(flagsTs)
            ProgressiveMediaSource.Factory(http, extratores)
                .createMediaSource(MediaItem.fromUri(uri))
        }
        Log.i(TAG, "abrir: id=$idAtual ${if (hls) "hls" else "progressivo"}") // nunca o URL
        if (inicioMs != null && inicioMs > 0) p.setMediaSource(fonte, inicioMs) else p.setMediaSource(fonte)
        p.prepare()
        p.playWhenReady = true
        definirACarregar(true)
    }

    /** Os cabeçalhos têm de ser um mapa de texto para texto; `null` se vierem noutro formato. */
    private fun cabecalhosDe(valor: Any?): Map<String, String>? {
        if (valor == null) return emptyMap()
        if (valor !is Map<*, *>) return null
        val mapa = LinkedHashMap<String, String>()
        for ((k, v) in valor) {
            if (k !is String || v !is String) return null
            mapa[k] = v
        }
        return mapa
    }

    private fun eHls(url: String, uri: Uri, mime: String?): Boolean {
        if (mime != null && (mime.contains("mpegurl", ignoreCase = true) || mime.contains("m3u8", ignoreCase = true))) return true
        if (Util.inferContentType(uri) == C.CONTENT_TYPE_HLS) return true
        // Xtream e afins: ".../canal.m3u8?token=…", "…&output=m3u8", "…?extension=m3u8"
        return url.lowercase().contains("m3u8")
    }

    /** Liberta o ExoPlayer. [esconder]: também esconde o vídeo (descartar); um `criar` mantém-no. */
    private fun libertar(esconder: Boolean = false) {
        principal.removeCallbacks(relogio)
        if (esconder) {
            visivel = false
            superficie?.visibility = View.GONE
        }
        val p = player ?: return
        player = null
        p.removeListener(ouvinte)
        p.removeAnalyticsListener(analise)
        p.clearVideoSurface()
        p.release()
        aCarregar = false
        descodificadorVideo = null
        videoDesligado = false
        pausadoPeloSistema = false
        Log.i(TAG, "libertar: id=$idAtual")
    }

    /** Sem grupo: o áudio (e a legenda com `auto`) volta à escolha automática do ExoPlayer; a
     *  legenda sem `auto` desliga-se. */
    private fun escolherFaixa(p: ExoPlayer, tipo: Int, grupo: Int?, faixa: Int?, auto: Boolean = false) {
        val construtor = p.trackSelectionParameters.buildUpon()
        if (grupo == null || faixa == null) {
            construtor.clearOverridesOfType(tipo)
            when {
                tipo == C.TRACK_TYPE_AUDIO -> Unit
                auto -> construtor.setTrackTypeDisabled(tipo, false)
                else -> construtor.setTrackTypeDisabled(tipo, true)
            }
            p.trackSelectionParameters = construtor.build()
            return
        }
        val grupos = p.currentTracks.groups
        if (grupo !in grupos.indices) return
        val g = grupos[grupo]
        if (g.type != tipo || faixa !in 0 until g.length) return
        p.trackSelectionParameters = construtor
            .setTrackTypeDisabled(tipo, false)
            .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, faixa))
            .build()
    }

    private fun estatisticas(p: ExoPlayer): Map<String, Any?> {
        val contadores = p.videoDecoderCounters
        contadores?.ensureUpdated()
        val v = p.videoFormat
        val a = p.audioFormat
        val fps = v?.frameRate?.takeIf { it != Format.NO_VALUE.toFloat() && it > 0 }?.toDouble()
        val largura = v?.width?.takeIf { it > 0 }
        val altura = v?.height?.takeIf { it > 0 }
        val bitrate = v?.let { f ->
            listOf(f.averageBitrate, f.peakBitrate, f.bitrate).firstOrNull { it > 0 }
        }
        return mapOf(
            "perdidas" to (contadores?.droppedBufferCount ?: 0),
            "renderizadas" to (contadores?.renderedOutputBufferCount ?: 0),
            "saltadas" to (contadores?.skippedOutputBufferCount ?: 0),
            "perdidasSeguidasMax" to (contadores?.maxConsecutiveDroppedBufferCount ?: 0),
            "fps" to fps,
            "codec" to (v?.codecs ?: v?.sampleMimeType),
            "mime" to v?.sampleMimeType,
            "descodificador" to descodificadorVideo,
            "largura" to largura,
            "altura" to altura,
            "resolucao" to if (largura != null && altura != null) "${largura}x$altura" else null,
            "bitrate" to bitrate,
            "audioCodec" to (a?.codecs ?: a?.sampleMimeType),
            "bufferMs" to p.totalBufferedDuration,
            "tunel" to tunel,
            "visivel" to visivel,
        )
    }

    // ---------------------------------------------------------------- eventos

    private fun enviar(tipo: String, dados: Map<String, Any?> = emptyMap()) {
        val sink = eventos ?: return
        sink.success(HashMap<String, Any?>(dados).apply {
            put("id", idAtual)
            put("sessao", sessaoAtual)
            put("tipo", tipo)
        })
    }

    private fun definirACarregar(valor: Boolean) {
        if (aCarregar == valor) return
        aCarregar = valor
        enviar("aCarregar", mapOf("valor" to valor, "percentagem" to if (valor) percentagemCarga() else 100.0))
    }

    /** Quanto do buffer pedido para começar (1,5 s) ou retomar (2,5 s) já chegou, em %. */
    private fun percentagemCarga(): Double {
        val p = player ?: return 0.0
        val alvo = if (jaTocou) 2_500.0 else 1_500.0
        return (p.totalBufferedDuration / alvo * 100.0).coerceIn(0.0, 100.0)
    }

    /** Posição (≤ 2/s) e, enquanto carrega, a percentagem do buffer. */
    private val relogio = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (aCarregar) {
                enviar("aCarregar", mapOf("valor" to true, "percentagem" to percentagemCarga()))
            }
            if (p.isPlaying) {
                val ms = p.currentPosition
                if (ms != ultimaPosicao) {
                    ultimaPosicao = ms
                    enviar("posicao", mapOf("ms" to ms))
                }
            }
            principal.postDelayed(this, INTERVALO_POSICAO_MS)
        }
    }

    private val ouvinte = object : Player.Listener {
        override fun onPlaybackStateChanged(estado: Int) {
            when (estado) {
                Player.STATE_BUFFERING -> definirACarregar(true)
                Player.STATE_READY -> {
                    definirACarregar(false)
                    jaTocou = true
                    if (!prontoEnviado) {
                        prontoEnviado = true
                        enviar("pronto")
                    }
                }
                Player.STATE_ENDED -> {
                    definirACarregar(false)
                    enviar("fim")
                }
                Player.STATE_IDLE -> definirACarregar(false)
            }
        }

        override fun onPlayerError(erro: PlaybackException) {
            val p = player ?: return
            // direto HLS que ficou para trás da janela: volta à ponta, sem incomodar o Dart
            if (erro.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                Log.i(TAG, "atrás da janela do direto: volta à ponta")
                p.seekToDefaultPosition()
                p.prepare()
                return
            }
            definirACarregar(false)
            // a falhar a descodificar ou no AudioTrack antes de o canal começar (sem `pronto` ou, com
            // vídeo, sem a 1.ª imagem): é o aparelho que não toca este formato; depois disso é
            // passageiro (rede, dados estragados)
            val temVideo = !videoDesligado && p.currentTracks.isTypeSelected(C.TRACK_TYPE_VIDEO)
            val antesDeComecar = !prontoEnviado || (temVideo && !primeiraImagem)
            val formato = erro.errorCode in CODIGOS_FORMATO ||
                (antesDeComecar && (erro.errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED ||
                    erro.errorCode in CODIGOS_AUDIO_TRACK))
            // só o nome do código (e o código HTTP): a mensagem e a causa podem trazer o endereço
            val http = (erro.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
            val mensagem = when {
                formato -> "Formato ou descodificador não suportado neste aparelho"
                http != null -> "O servidor respondeu com o código HTTP $http"
                erro.errorCode in 2000..2999 -> "Falha de rede ao abrir o canal"
                else -> "O ExoPlayer não conseguiu tocar o canal"
            }
            Log.w(TAG, "erro: id=$idAtual ${erro.errorCodeName}${if (http != null) " HTTP $http" else ""} causa=${erro.cause?.javaClass?.simpleName}")
            enviar(
                "erro",
                mapOf("codigo" to erro.errorCodeName, "numero" to erro.errorCode, "mensagem" to mensagem, "formato" to formato),
            )
        }

        override fun onRenderedFirstFrame() {
            primeiraImagem = true
        }

        override fun onVideoSizeChanged(tamanho: VideoSize) {
            if (tamanho.width <= 0 || tamanho.height <= 0) return
            tamanhoVideo = tamanho
            aplicarAjuste()
            enviar(
                "tamanho",
                mapOf(
                    "largura" to tamanho.width,
                    "altura" to tamanho.height,
                    "proporcaoPixel" to tamanho.pixelWidthHeightRatio.toDouble(),
                ),
            )
        }

        override fun onTracksChanged(faixas: Tracks) {
            val p = player ?: return
            if (faixas.isEmpty) return
            // áudio ou vídeo que o aparelho não descodifica: o Dart passa ao mpv
            for ((tipo, nome) in listOf(C.TRACK_TYPE_VIDEO to "video", C.TRACK_TYPE_AUDIO to "audio")) {
                if (faixas.containsType(tipo) && !faixas.isTypeSupported(tipo, true)) {
                    Log.w(TAG, "sem descodificador de $nome: id=$idAtual")
                    p.stop()
                    definirACarregar(false)
                    enviar(
                        "erro",
                        mapOf(
                            "codigo" to "SEM_DESCODIFICADOR_${nome.uppercase()}",
                            "numero" to 0,
                            "mensagem" to "O aparelho não descodifica o ${if (nome == "video") "vídeo" else "áudio"} deste canal",
                            "formato" to true,
                        ),
                    )
                    return
                }
            }
            val audio = mutableListOf<Map<String, Any?>>()
            val legendas = mutableListOf<Map<String, Any?>>()
            var audioAtual: Map<String, Int>? = null
            var legendaAtual: Map<String, Int>? = null
            faixas.groups.forEachIndexed { gi, g ->
                val lista = when (g.type) {
                    C.TRACK_TYPE_AUDIO -> audio
                    C.TRACK_TYPE_TEXT -> legendas
                    else -> return@forEachIndexed
                }
                for (fi in 0 until g.length) {
                    val f = g.getTrackFormat(fi)
                    lista.add(
                        mapOf(
                            "grupo" to gi,
                            "faixa" to fi,
                            "lingua" to f.language,
                            "rotulo" to (f.label ?: rotuloDe(f)),
                            "suportada" to g.isTrackSupported(fi),
                        ),
                    )
                    if (g.isTrackSelected(fi)) {
                        val sel = mapOf("grupo" to gi, "faixa" to fi)
                        if (g.type == C.TRACK_TYPE_AUDIO) audioAtual = sel else legendaAtual = sel
                    }
                }
            }
            enviar("faixas", mapOf("audio" to audio, "legendas" to legendas))
            enviar("faixaAtual", mapOf("audio" to audioAtual, "legenda" to legendaAtual))
        }

        override fun onCues(cues: CueGroup) {
            // sem media3-ui: o texto da legenda vai para o Dart desenhar
            val texto = cues.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
            enviar("legendaTexto", mapOf("texto" to texto))
        }
    }

    private fun rotuloDe(f: Format): String? {
        val partes = mutableListOf<String>()
        f.sampleMimeType?.let { partes.add(it.substringAfter('/')) }
        if (f.channelCount > 0) partes.add("${f.channelCount} canais")
        return partes.joinToString(" · ").ifEmpty { null }
    }

    private val analise = object : AnalyticsListener {
        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) {
            descodificadorVideo = decoderName
            Log.i(TAG, "descodificador de vídeo: $decoderName (${initializationDurationMs} ms)")
        }
    }

    // ---------------------------------------------------------------- superfícies

    /**
     * Põe (uma vez) a caixa preta com o `SurfaceView` no FrameLayout do conteúdo, no índice 0, por
     * baixo da FlutterView. O `SurfaceView` do vídeo fica com a ordem em Z normal (por trás da janela,
     * que lhe abre um "buraco"); o `FlutterSurfaceView` transparente tem `setZOrderOnTop(true)` (fica
     * por cima da janela). Ordem: vídeo < janela (caixa preta com o buraco) < Flutter.
     */
    private fun prepararSuperficie() {
        if (caixa != null) return
        val conteudo = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val sv = SurfaceView(activity).apply {
            visibility = if (visivel) View.VISIBLE else View.GONE
            // nunca tapar a interface: nada de setZOrderOnTop / setZOrderMediaOverlay aqui
        }
        val c = FrameLayout(activity).apply {
            setBackgroundColor(Color.BLACK)
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(sv, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER,
            ))
            addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or_, ob ->
                if (r - l != or_ - ol || b - t != ob - ot) principal.post { aplicarAjuste() }
            }
        }
        conteudo.addView(c, 0, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        caixa = c
        superficie = sv
    }

    private fun mostrar(p: ExoPlayer, sim: Boolean) {
        prepararSuperficie()
        visivel = sim
        superficie?.visibility = if (sim) View.VISIBLE else View.GONE
        // escondido: desliga o vídeo para o MediaCodec ser largado (sem Surface o ExoPlayer
        // continuaria a descodificar para uma Surface de reserva); volta ao mostrar
        if (!sim && !videoDesligado) {
            videoDesligado = true
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true).build()
        } else if (sim && videoDesligado) {
            videoDesligado = false
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false).build()
        }
        if (sim) aplicarAjuste()
    }

    /** Tamanho do `SurfaceView` dentro da caixa: ajustar (barras), preencher (corta) ou esticar. */
    private fun aplicarAjuste() {
        val c = caixa ?: return
        val sv = superficie ?: return
        val cw = c.width
        val ch = c.height
        if (cw <= 0 || ch <= 0) return
        val v = tamanhoVideo
        val proporcao = proporcaoPedida
            ?: if (v.width > 0 && v.height > 0) v.width * v.pixelWidthHeightRatio.toDouble() / v.height else null
        var w = ViewGroup.LayoutParams.MATCH_PARENT
        var h = ViewGroup.LayoutParams.MATCH_PARENT
        if (proporcao != null && modoAjuste != "esticar") {
            val ecra = cw.toDouble() / ch
            val pelaAltura = if (modoAjuste == "preencher") ecra < proporcao else ecra > proporcao
            if (pelaAltura) {
                h = ch
                w = Math.round(ch * proporcao).toInt()
            } else {
                w = cw
                h = Math.round(cw / proporcao).toInt()
            }
        }
        val lp = sv.layoutParams as FrameLayout.LayoutParams
        if (lp.width != w || lp.height != h) {
            lp.width = w
            lp.height = h
            lp.gravity = Gravity.CENTER
            sv.layoutParams = lp
        }
    }

    // ---------------------------------------------------------------- ciclo de vida da Activity

    /** onPause/onStop: pausa (a Surface é largada pelo próprio SurfaceView ao esconder a janela). */
    fun aoPausar() {
        val p = player ?: return
        if (p.playWhenReady) {
            pausadoPeloSistema = true
            pausadoEm = SystemClock.elapsedRealtime()
            p.pause()
        }
    }

    /**
     * onResume: retoma o que o sistema pausou. Num direto parado há mais de 10 s volta à ponta
     * (o buffer guardado já está velho); a primeira imagem nova vai para a Surface recriada.
     */
    fun aoRetomar() {
        val p = player ?: return
        if (!pausadoPeloSistema) return
        pausadoPeloSistema = false
        val direto = p.isCurrentMediaItemLive || !p.isCurrentMediaItemSeekable
        if (direto && SystemClock.elapsedRealtime() - pausadoEm > 10_000) {
            p.seekToDefaultPosition()
            if (p.playbackState == Player.STATE_IDLE) p.prepare()
        }
        p.play()
    }

    /** onDestroy: liberta tudo. */
    fun destruir() {
        libertar(esconder = true)
        canal.setMethodCallHandler(null)
        canalEventos.setStreamHandler(null)
        eventos = null
        caixa?.let { (it.parent as? ViewGroup)?.removeView(it) }
        caixa = null
        superficie = null
    }

    companion object {
        private const val TAG = "ReprodutorExo"
        private const val INTERVALO_POSICAO_MS = 500L

        /**
         * Erros de descodificador/formato: o Dart pode passar ao mpv. O resto (rede, HTTP…) não, exceto
         * DECODING_FAILED e os do AudioTrack antes de o canal começar (ver onPlayerError).
         */
        private val CODIGOS_FORMATO = setOf(
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
        )

        /** Erros do AudioTrack (5000–5999: abrir, escrever, offload): formato só antes de o canal começar. */
        private val CODIGOS_AUDIO_TRACK = 5000..5999
    }
}
