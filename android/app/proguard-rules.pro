# Flutter / Dart embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_inappwebview
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**

# path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Play Core отсутствует в зависимостях (deferred components не используются),
# но классы Flutter embedding ссылаются на него — просто глушим предупреждения.
-dontwarn com.google.android.play.core.**

# Kotlin / coroutines
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

# App's own native bridge — referenced by name from Dart MethodChannels
-keep class com.xunkal1.xuncode.** { *; }

# Native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Reflection-safe attributes
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, SourceFile, LineNumberTable
