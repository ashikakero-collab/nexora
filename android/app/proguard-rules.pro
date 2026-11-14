# NEXORA release R8 rules.

# Flutter embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
# Flutter references Play Core (deferred components) which we don't ship.
-dontwarn com.google.android.play.core.**

# LiveKit / flutter_webrtc: native code calls into these via JNI, so names must survive.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class io.livekit.** { *; }
-dontwarn io.livekit.**
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn com.cloudwebrtc.webrtc.**
-keepclasseswithmembernames class * { native <methods>; }

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# Supabase / ktor-free plugins, permission_handler, image_picker, shared_preferences (platform channels)
-keep class com.baseflow.permissionhandler.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep annotations / generic signatures used by reflection-based serializers
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
