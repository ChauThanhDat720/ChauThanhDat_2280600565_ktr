package vn.edu.attendly.attendly

import android.nfc.NfcAdapter
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pending: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finishScan(null, "Hết thời gian đọc thẻ NFC.") }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.edu.attendly/nfc")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readTag" -> {
                        val adapter = NfcAdapter.getDefaultAdapter(this)
                        when {
                            adapter == null -> result.error("unavailable", "Thiết bị không hỗ trợ NFC. Hãy dùng QR hoặc vân tay.", null)
                            !adapter.isEnabled -> result.error("disabled", "Hãy bật NFC trong Cài đặt điện thoại.", null)
                            pending != null -> result.error("busy", "Một lượt đọc NFC đang hoạt động.", null)
                            else -> {
                                pending = result
                                adapter.enableReaderMode(this, { tag ->
                                    val uid = tag.id.joinToString("") { "%02X".format(it.toInt() and 0xFF) }
                                    runOnUiThread { finishScan(uid, null) }
                                }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
                                    NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
                                    NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
                                handler.postDelayed(timeout, 30000)
                            }
                        }
                    }
                    "cancelScan" -> { finishScan(null, "Đã dừng đọc NFC."); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
    private fun finishScan(uid: String?, error: String?) {
        val result = pending ?: return
        pending = null
        handler.removeCallbacks(timeout)
        NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this)
        if (error != null) result.error("scan_stopped", error, null) else result.success(uid)
    }
    override fun onPause() {
        finishScan(null, "Ứng dụng đã tạm dừng. Vui lòng quét lại thẻ.")
        super.onPause()
    }
}
