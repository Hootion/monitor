package com.mutualwatch.app

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

fun isoNow(): String = isoFromMillis(System.currentTimeMillis())

fun isoFromMillis(value: Long): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(Date(value))
}

