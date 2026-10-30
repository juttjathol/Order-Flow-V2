# Play advisory: R8 optimise/obfuscate/shrink rates were all ~49% because the
# broad keeps below pinned whole libraries (ML Kit bundled model + CameraX are
# tens of thousands of classes). Plugin AARs ship their own consumer ProGuard
# rules, so we keep ONLY our API entry points and let R8 work.
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn androidx.camera.**

# Flutter engine + plugin registry must stay reflective
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**
# Play Console crash traces for our own service keep readable names
-keep class com.jathol.orderflow.** { *; }

# More optimisation headroom for non-reflective code.
-allowaccessmodification
