package app.adspocket.ads_pocket

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var bridge: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var exportText: String? = null
    private val io = Executors.newSingleThreadExecutor()
    private val queuePrefs by lazy { getSharedPreferences("incoming", MODE_PRIVATE) }
    private val maxBackup = 5 * 1024 * 1024
    private val maxImage = 15 * 1024 * 1024

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) capture(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.adspocket/native")
        bridge!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "pendingShares" -> {
                    val items = JSONArray(queuePrefs.getString("queue", "[]"))
                    val values = (0 until items.length()).map { items.getString(it) }
                    queuePrefs.edit().remove("queue").apply()
                    result.success(values)
                }
                "imagePath" -> {
                    val name = call.arguments as? String ?: ""
                    val file = File(filesDir, "references/$name")
                    result.success(if (Regex("^[a-f0-9-]{36}\\.(png|jpg|webp)$").matches(name) && file.isFile) file.absolutePath else null)
                }
                "openBrowser" -> {
                    try {
                        val uri = Uri.parse(call.arguments as? String ?: "")
                        require(uri.scheme == "https" && uri.host != null && uri.userInfo == null && (uri.port == -1 || uri.port == 443))
                        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.org/")).addCategory(Intent.CATEGORY_BROWSABLE)
                        @Suppress("DEPRECATION")
                        val defaults = packageManager.resolveActivity(probe, 65536)?.activityInfo?.packageName
                        @Suppress("DEPRECATION")
                        val packages = packageManager.queryIntentActivities(probe, 65536).map { it.activityInfo.packageName }.filter { it != packageName && it != "android" }
                        val target = if (defaults in packages) defaults else packages.firstOrNull()
                        if (target == null) result.success(false)
                        else {
                            startActivity(Intent(Intent.ACTION_VIEW,uri).setPackage(target).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(true)
                        }
                    } catch (_: Exception) { result.success(false) }
                }
                "deleteImage" -> {
                    val name = call.arguments as? String ?: ""
                    if (Regex("^[a-f0-9-]{36}\\.(png|jpg|webp)$").matches(name)) File(filesDir,"references/$name").delete()
                    result.success(null)
                }
                "importBackup", "exportBackup", "pickImage" -> {
                    if (pendingResult != null) { result.error("busy", "Um seletor já está aberto.", null); return@setMethodCallHandler }
                    pendingResult = result
                    try {
                        when (call.method) {
                            "exportBackup" -> {
                                val text = call.arguments as? String ?: throw IllegalArgumentException()
                                require(text.toByteArray(Charsets.UTF_8).size <= maxBackup)
                                exportText = text
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/json"
                                    putExtra(Intent.EXTRA_TITLE, "adspocket-backup.json")
                                }, 103)
                            }
                            "importBackup" -> startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                            }, 101)
                            "pickImage" -> startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE); type = "image/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg", "image/webp"))
                            }, 102)
                        }
                    } catch (_: Exception) {
                        pendingResult = null; exportText = null
                        result.error("file", "Não foi possível abrir o seletor de arquivos.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent); capture(intent)
    }

    @Suppress("DEPRECATION")
    private fun capture(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
            enqueue(if (text.length <= 65536) text else "invalid-shared-text")
        } else if (intent?.action == Intent.ACTION_VIEW) {
            intent.dataString?.let { enqueue(if (it.length <= 8192) it else "invalid-link") }
        } else if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("image/") == true) {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
            io.execute {
                val file = try { copyImage(uri) } catch (_: Exception) { null }
                runOnUiThread { enqueue(if (file == null) "invalid-shared-image" else "image:$file") }
            }
        }
    }

    private fun enqueue(value: String) {
        val items = JSONArray(queuePrefs.getString("queue", "[]"))
        // Bound the queue; shared text contains references only, never browser credentials.
        if (items.length() < 20) items.put(value)
        queuePrefs.edit().putString("queue", items.toString()).apply()
        bridge?.invokeMethod("sharesChanged", null)
    }

    private fun readBounded(uri: Uri, limit: Int): ByteArray {
        require(uri.scheme == "content")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input)
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count == -1) break
                require(output.size() + count <= limit)
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        }
    }

    private fun copyImage(uri: Uri): String {
        val bytes = readBounded(uri, maxImage)
        require(bytes.size >= 12)
        val extension = when {
            bytes.take(8).toByteArray().contentEquals(byteArrayOf(137.toByte(),80,78,71,13,10,26,10)) -> "png"
            bytes[0] == 255.toByte() && bytes[1] == 216.toByte() && bytes[2] == 255.toByte() -> "jpg"
            String(bytes,0,4,Charsets.US_ASCII) == "RIFF" && String(bytes,8,4,Charsets.US_ASCII) == "WEBP" -> "webp"
            else -> throw IllegalArgumentException()
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 40000000)
        val folder = File(filesDir,"references").apply { mkdirs() }
        val name = "${UUID.randomUUID()}.$extension"
        File(folder,name).writeBytes(bytes)
        return name
    }

    @Deprecated("Legacy result API used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (requestCode !in 101..103) return
        val callback = pendingResult ?: return
        val text = exportText
        pendingResult = null; exportText = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            callback.success(if (requestCode == 103) false else null); return
        }
        io.execute {
            try {
                val value: Any? = when (requestCode) {
                    101 -> readBounded(uri,maxBackup).toString(Charsets.UTF_8)
                    102 -> copyImage(uri)
                    else -> {
                        require(uri.scheme == "content")
                        contentResolver.openOutputStream(uri,"wt").use { output ->
                            requireNotNull(output); output.write(requireNotNull(text).toByteArray(Charsets.UTF_8))
                        }
                        true
                    }
                }
                runOnUiThread { callback.success(value) }
            } catch (_: Exception) {
                runOnUiThread { callback.error("file", "Arquivo inválido, indisponível ou acima do limite.", null) }
            }
        }
    }

    override fun onDestroy() {
        bridge?.setMethodCallHandler(null); bridge = null
        io.shutdown()
        super.onDestroy()
    }
}
