# Keep Google ML Kit barcode classes (release R8/ProGuard).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class androidx.camera.core.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**
