package com.mutualwatch.app

import android.location.Location
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

internal data class MapCoordinate(
    val latitude: Double,
    val longitude: Double
)

internal fun Collection<Location>.bestAvailableLocation(): Location? {
    var best: Location? = null
    for (location in this) {
        if (location.isBetterThan(best)) {
            best = location
        }
    }
    return best
}

internal fun Location.isBetterThan(currentBest: Location?): Boolean {
    if (!hasUsableCoordinate()) return false
    if (currentBest == null || !currentBest.hasUsableCoordinate()) return true

    val timeDelta = time - currentBest.time
    val significantlyNewer = timeDelta > SIGNIFICANT_LOCATION_TIME_DELTA_MS
    val significantlyOlder = timeDelta < -SIGNIFICANT_LOCATION_TIME_DELTA_MS
    val newer = timeDelta > 0

    if (significantlyNewer) return true
    if (significantlyOlder) return false

    val accuracyDelta = accuracyScore() - currentBest.accuracyScore()
    val moreAccurate = accuracyDelta < 0f
    val lessAccurate = accuracyDelta > 0f
    val significantlyLessAccurate = accuracyDelta > SIGNIFICANT_ACCURACY_DELTA_METERS
    val sameProvider = provider == currentBest.provider

    return moreAccurate ||
        (newer && !lessAccurate) ||
        (newer && !significantlyLessAccurate && sameProvider)
}

internal fun Location.toAmapCoordinate(): MapCoordinate =
    wgs84ToGcj02(latitude, longitude)

private fun Location.hasUsableCoordinate(): Boolean =
    latitude in -90.0..90.0 &&
        longitude in -180.0..180.0 &&
        !(abs(latitude) < 0.000001 && abs(longitude) < 0.000001)

private fun Location.accuracyScore(): Float =
    if (hasAccuracy()) accuracy else Float.MAX_VALUE

private fun wgs84ToGcj02(latitude: Double, longitude: Double): MapCoordinate {
    if (isOutsideChina(latitude, longitude)) {
        return MapCoordinate(latitude, longitude)
    }

    var dLat = transformLatitude(longitude - 105.0, latitude - 35.0)
    var dLon = transformLongitude(longitude - 105.0, latitude - 35.0)
    val radLat = latitude / 180.0 * PI
    var magic = sin(radLat)
    magic = 1 - GCJ_EE * magic * magic
    val sqrtMagic = sqrt(magic)
    dLat = (dLat * 180.0) / ((GCJ_AXIS * (1 - GCJ_EE)) / (magic * sqrtMagic) * PI)
    dLon = (dLon * 180.0) / (GCJ_AXIS / sqrtMagic * cos(radLat) * PI)
    return MapCoordinate(latitude + dLat, longitude + dLon)
}

private fun isOutsideChina(latitude: Double, longitude: Double): Boolean =
    longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271

private fun transformLatitude(x: Double, y: Double): Double {
    var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
    result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
    result += (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0
    result += (160.0 * sin(y / 12.0 * PI) + 320.0 * sin(y * PI / 30.0)) * 2.0 / 3.0
    return result
}

private fun transformLongitude(x: Double, y: Double): Double {
    var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
    result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
    result += (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0
    result += (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0
    return result
}

private const val PI = 3.14159265358979324
private const val GCJ_AXIS = 6378245.0
private const val GCJ_EE = 0.00669342162296594323
private const val SIGNIFICANT_LOCATION_TIME_DELTA_MS = 2 * 60 * 1000L
private const val SIGNIFICANT_ACCURACY_DELTA_METERS = 100f
