# ProGuard rules for MyEyeScan Release Build

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Google Play Core (Fix para R8 missing classes)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep ONNX Runtime
-keep class ai.onnxruntime.** { *; }

# Keep TFLite
-keep class org.tensorflow.lite.** { *; }

# Keep camera classes
-keep class androidx.camera.** { *; }

# Keep audio player classes
-keep class com.ryanheise.just_audio.** { *; }

# Keep Bluetooth classes
-keep class com.pauldemarco.flutter_blue.** { *; }

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

# AndroidX
-keep class androidx.** { *; }
-keep interface androidx.** { *; }

# Suppress warnings
-dontwarn org.tensorflow.lite.**
-dontwarn ai.onnxruntime.**
-dontwarn com.google.android.play.**
