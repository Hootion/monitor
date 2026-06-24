package com.mutualwatch.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object EventLogStore {
    private const val PREFS = "mutual_watch_events"
    private const val KEY_EVENTS = "events"

    fun record(context: Context, type: String, details: Map<String, Any?> = emptyMap()) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val events = JSONArray(prefs.getString(KEY_EVENTS, "[]"))
        val json = JSONObject()
            .put("clientEventId", UUID.randomUUID().toString())
            .put("type", type)
            .put("occurredAt", isoNow())
            .put("platform", "android")
            .put("details", JSONObject(details))
        events.put(json)
        val trimmed = JSONArray()
        val start = maxOf(0, events.length() - 300)
        for (index in start until events.length()) {
            trimmed.put(events.getJSONObject(index))
        }
        prefs.edit().putString(KEY_EVENTS, trimmed.toString()).apply()
    }

    fun recent(context: Context, limit: Int = 100): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val events = JSONArray(prefs.getString(KEY_EVENTS, "[]"))
        val list = mutableListOf<Map<String, Any?>>()
        val start = maxOf(0, events.length() - limit)
        for (index in events.length() - 1 downTo start) {
            val json = events.getJSONObject(index)
            list.add(json.toMap())
        }
        return list
    }

    private fun JSONObject.toMap(): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val keys = keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = get(key)
            result[key] = when (value) {
                is JSONObject -> value.toMap()
                JSONObject.NULL -> null
                else -> value
            }
        }
        return result
    }
}

