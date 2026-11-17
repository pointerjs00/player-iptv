package pt.playeriptv.player_iptv

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pedidoPermissao: (() -> Unit)? = null
    private var falhaPermissao: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
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
        return "Transferências/$nome"
    }
}
