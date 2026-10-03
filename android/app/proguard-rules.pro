# R8 rules for release builds (Phase 9 Slice 2, D-346).
#
# Shrinking and obfuscation stay on (build.gradle.kts: isMinifyEnabled, isShrinkResources).
# This file adds only what the measured release build needed; it is not a place to switch
# R8 off. The Flutter Gradle plugin already supplies the engine's own keep rules, and each
# plugin (flutter_secure_storage, file_selector, image_picker, printing, path_provider,
# supabase/app_links) ships its consumer rules inside its AAR.
#
# The Dart code — drift, JSON, the finance domain — is compiled to native code by the
# Dart AOT compiler and is not seen by R8 at all; only the Java/Kotlin plugin layer is.
#
# Every rule below names the build finding it answers. Add nothing without one.
