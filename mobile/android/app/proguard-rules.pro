# AMap native libraries look up SDK classes and JNI methods by their original
# Java names. R8 obfuscation can make libAMapOpenMap.so abort with
# "JNI DETECTED ERROR IN APPLICATION: java_class == null" when the map view is
# first created, so keep the AMap SDK and the Flutter bridge unmangled.
-keep class com.amap.** { *; }
-keep class com.autonavi.** { *; }
-keep class com.loc.** { *; }
-keep class com.amap.flutter.** { *; }

-dontwarn com.amap.**
-dontwarn com.autonavi.**
-dontwarn com.loc.**
