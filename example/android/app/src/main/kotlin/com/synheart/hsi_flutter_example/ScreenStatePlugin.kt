package com.synheart.hsi_flutter_example

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

class ScreenStatePlugin : FlutterPlugin, EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var screenReceiver: BroadcastReceiver? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        eventChannel = EventChannel(binding.binaryMessenger, "screen_state")
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel?.setStreamHandler(null)
        unregisterReceiver()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        registerReceiver()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        unregisterReceiver()
    }

    private fun registerReceiver() {
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_ON -> eventSink?.success("on")
                    Intent.ACTION_SCREEN_OFF -> eventSink?.success("off")
                    Intent.ACTION_USER_PRESENT -> eventSink?.success("unlocked")
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        context?.registerReceiver(screenReceiver, filter)
    }

    private fun unregisterReceiver() {
        screenReceiver?.let { context?.unregisterReceiver(it) }
        screenReceiver = null
    }
}

