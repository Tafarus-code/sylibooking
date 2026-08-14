# Flutter's engine is reached through JNI, so the shrinker cannot see the
# references and would strip the classes that make the app start at all.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter's engine references Play Core's deferred-component classes, which
# are only on the classpath for apps that actually split themselves into
# downloadable features. This one does not, so R8 finds the references
# dangling and refuses to finish.
#
# Ignored rather than adding the dependency: pulling in a library so that a
# code path we never take can typecheck is a megabyte of download for every
# merchant, to fix a warning.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# Line numbers, so a stack trace from a released build names a line rather
# than a bytecode offset. Crash reports are worth having only if they can be
# read — see shared_client/crash_reporting.dart.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
