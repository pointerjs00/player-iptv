package pt.playeriptv.player_iptv

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pedidoPermissao: (() -> Unit)? = null
    private var falhaPermissao: (() -> Unit)? = null
    private var reprodutorExo: ReprodutorExo? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // A textura do vídeo (SurfaceProducer do media_kit_video) passa a SurfaceTexture também no
        // API 29+. O ImageReader que o Flutter usaria lá não aplica o recorte que o MediaCodec põe em
        // cada imagem (handlesCropAndRotation() = false): mostrava o buffer inteiro do descodificador,
        // com as linhas de alinhamento a zeros (verde) no fundo, em canais 720p/576 (e HEVC). Na
        // SurfaceTexture o recorte vai na matriz da textura. Só com o Impeller em OpenGL ES (manifesto).
        // Tem de ser antes do super.onCreate: o motor e os plugins arrancam lá.
        FlutterRenderer.debugForceSurfaceProducerGlTextures = true
        super.onCreate(savedInstanceState)
    }

    // Motor ExoPlayer: o vídeo desenha-se num SurfaceView por baixo da interface. Para se ver, a
    // FlutterView é sempre transparente: o FlutterSurfaceView fica com formato TRANSPARENT e
    // setZOrderOnTop(true) (por cima da janela), e o SurfaceView do vídeo, com a ordem normal, fica
    // por trás da janela. A transparência só se escolhe ao criar a FlutterView, por isso é fixa;
    // a app pinta o seu fundo opaco em Flutter. O fundo da janela (tema) não muda.
    override fun getRenderMode(): RenderMode = RenderMode.surface

    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onPause() {
        // em ecrã dividido/PiP a app continua à vista: não pausa
        if (!(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInMultiWindowMode)) reprodutorExo?.aoPausar()
        super.onPause()
    }

    override fun onStop() {
        reprodutorExo?.aoPausar()
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        reprodutorExo?.aoRetomar()
    }

    override fun onDestroy() {
        reprodutorExo?.destruir()
        reprodutorExo = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Motor ExoPlayer (Media3): canais player_iptv/exo e player_iptv/exo/eventos
        reprodutorExo?.destruir()
        reprodutorExo = ReprodutorExo(this, flutterEngine.dartExecutor.binaryMessenger)
        // "eTv": Android TV (leanback) ou sem ecrã tátil -> o realce do foco fica sempre ligado
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "player_iptv/tv").setMethodCallHandler { call, result ->
            if (call.method == "eTv") {
                val pm = packageManager
                result.success(
                    pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                        !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
                )
            } else {
                result.notImplemented()
            }
        }
        // Taxa de atualização do ecrã (Android TV / Fire TV): o player pede o modo que combina com
        // o fps do canal (50 fps -> 50 Hz) e repõe-no ao sair. Usa preferredDisplayModeId (API 23+),
        // que muda mesmo de modo; o Surface.setFrameRate (API 30+) só pede trocas sem corte, e
        // 60 -> 50 Hz quase nunca o é numa TV, por isso não serviria.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "player_iptv/ecra").setMethodCallHandler { call, result ->
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                result.success(null)
                return@setMethodCallHandler
            }
            val ecra = ecraAtual()
            if (ecra == null) {
                result.success(null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "taxas" -> {
                    val atual = ecra.mode
                    result.success(
                        mapOf(
                            "atual" to atual.refreshRate.toDouble(),
                            "suportadas" to modosMesmaResolucao(ecra).map { it.refreshRate.toDouble() }.distinct()
                        )
                    )
                }
                "pedir" -> {
                    val hz = call.argument<Double>("hz") ?: 0.0
                    val modo = modosMesmaResolucao(ecra).minByOrNull { Math.abs(it.refreshRate - hz) }
                    if (modo == null || Math.abs(modo.refreshRate - hz) > 0.05) {
                        result.success(false)
                    } else {
                        window.attributes = window.attributes.apply { preferredDisplayModeId = modo.modeId }
                        result.success(true)
                    }
                }
                "repor" -> {
                    window.attributes = window.attributes.apply { preferredDisplayModeId = 0 }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // Guardar em Transferências (telemóvel e TV): MediaStore no Android 10+, pasta pública no 9-
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "player_iptv/ficheiros").setMethodCallHandler { call, result ->
            when (call.method) {
                "existentes" -> comPermissao(result) {
                    try {
                        result.success(listarExistentes())
                    } catch (e: Exception) {
                        result.error("io", e.message, null)
                    }
                }
                "guardar" -> {
                    val nome = call.argument<String>("nome")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    if (nome == null || bytes == null) {
                        result.error("io", "Pedido inválido", null)
                    } else {
                        comPermissao(result) {
                            try {
                                result.success(guardar(nome, bytes, mime))
                            } catch (e: Exception) {
                                result.error("io", e.message ?: e.javaClass.simpleName, null)
                            }
                        }
                    }
                }
                // o espaço livre (bytes) no disco da pasta, para o direto gravado (não precisa de permissão)
                "espacoLivre" -> {
                    val pasta = call.argument<String>("pasta")
                    if (pasta == null) {
                        result.error("io", "Pedido inválido", null)
                    } else {
                        try {
                            result.success(StatFs(pasta).availableBytes)
                        } catch (e: Exception) {
                            result.error("io", e.javaClass.simpleName, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ecraAtual(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
        else @Suppress("DEPRECATION") (windowManager.defaultDisplay)

    /** Os modos com a resolução atual (só muda a taxa, nunca a resolução). */
    private fun modosMesmaResolucao(ecra: Display): List<Display.Mode> {
        val atual = ecra.mode
        return ecra.supportedModes.filter {
            it.physicalWidth == atual.physicalWidth && it.physicalHeight == atual.physicalHeight
        }
    }

    /** Android 10+ não precisa de permissão; no 9- pede WRITE_EXTERNAL_STORAGE em tempo de execução. */
    private fun comPermissao(result: MethodChannel.Result, acao: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) {
            acao()
            return
        }
        pedidoPermissao = acao
        falhaPermissao = { result.error("permissao", "Permissão de armazenamento negada", null) }
        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4711)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        if (code != 4711) return
        val ok = res.isNotEmpty() && res[0] == PackageManager.PERMISSION_GRANTED
        val acao = pedidoPermissao
        val falha = falhaPermissao
        pedidoPermissao = null
        falhaPermissao = null
        if (ok) acao?.invoke() else falha?.invoke()
    }

    private fun listarExistentes(): List<String> {
        val nomes = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                arrayOf("${Environment.DIRECTORY_DOWNLOADS}/%"),
                null
            )?.use { c -> while (c.moveToNext()) nomes.add(c.getString(0)) }
        } else {
            @Suppress("DEPRECATION")
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).list()?.let { nomes.addAll(it) }
        }
        return nomes
    }

    private fun guardar(nome: String, bytes: ByteArray, mime: String): String {
        var nomeReal = nome
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val valores = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, nome)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, valores)
                ?: throw IllegalStateException("O Android recusou criar o ficheiro")
            try {
                (contentResolver.openOutputStream(uri) ?: throw IllegalStateException("Não foi possível abrir o ficheiro"))
                    .use { it.write(bytes) }
                contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                // o MediaStore pode ter renomeado (ficheiro de outra app com o mesmo nome)
                contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) nomeReal = c.getString(0) ?: nome
                }
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
        } else {
            @Suppress("DEPRECATION")
            val pasta = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            pasta.mkdirs()
            File(pasta, nome).writeBytes(bytes)
        }
        return nomeReal
    }
}
