# Keep Google ML Kit barcode classes (release R8/ProGuard).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class androidx.camera.core.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**

# Flutter engine + plugin registry must stay reflective
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**
# Play Console crash traces for our own service keep readable names
-keep class com.jathol.orderflow.** { *; }
