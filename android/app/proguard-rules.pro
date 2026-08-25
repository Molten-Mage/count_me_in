# WorkManager/Room build their database implementation classes at compile
# time via annotation processing, then instantiate them at runtime by
# canonical class name (reflection), not a direct reference R8 can see.
# Without these keep rules, R8 either strips the generated *_Impl classes
# as "unreachable" or renames them, and WorkManager crashes on startup
# with "Failed to create an instance of class ...WorkDatabase.canonicalName"
# - reproduced on a clean Android 15 emulator with a release build.
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Database class * { *; }
-keep class **_Impl { *; }
-keep class androidx.work.impl.WorkDatabase { *; }
