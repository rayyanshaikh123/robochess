package com.example.robochess_mobile

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val audioChannelName = "com.example.robochess_mobile/audio_input"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInputDevices" -> result.success(getInputDevices())
                    "selectInputDevice" -> {
                        val id = call.argument<Int>("id")
                        result.success(id?.let { selectInputDevice(it) } ?: false)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun audioManager(): AudioManager {
        return getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private fun getInputDevices(): List<Map<String, Any>> {
        val selectedId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager().communicationDevice?.id
        } else {
            null
        }

        return audioManager()
            .getDevices(AudioManager.GET_DEVICES_INPUTS)
            .map { device ->
                mapOf(
                    "id" to device.id,
                    "name" to (device.productName?.toString()?.takeIf { it.isNotBlank() }
                        ?: typeName(device.type)),
                    "type" to typeName(device.type),
                    "isSelected" to (selectedId == device.id)
                )
            }
    }

    private fun selectInputDevice(deviceId: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return false
        }

        val device = audioManager()
            .availableCommunicationDevices
            .firstOrNull { it.id == deviceId }
            ?: audioManager()
                .getDevices(AudioManager.GET_DEVICES_INPUTS)
                .firstOrNull { it.id == deviceId }
            ?: return false

        return audioManager().setCommunicationDevice(device)
    }

    private fun typeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in mic"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth mic"
            AudioDeviceInfo.TYPE_BLE_HEADSET -> "Bluetooth LE headset"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
            AudioDeviceInfo.TYPE_TELEPHONY -> "Telephony"
            else -> "Audio input"
        }
    }
}
