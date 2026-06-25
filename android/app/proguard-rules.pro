# Flutter core
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (deferred components)
-dontwarn com.google.android.play.core.**

# Firebase backbone — App Check, Messaging, Core
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AppsFlyer SDK
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# WebView Flutter plugin
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Native JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable creators
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Strip verbose Log calls from the release build
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
