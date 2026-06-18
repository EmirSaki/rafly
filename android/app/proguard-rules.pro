-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep AndroidX classes used by plugins
-keep class androidx.core.app.** { *; }
-keep class androidx.work.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# mobile_scanner (CameraX / ML Kit)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# http package
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
