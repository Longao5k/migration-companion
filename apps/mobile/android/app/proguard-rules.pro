-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# OkHttp probes these optional providers reflectively and falls back to the
# Android platform TLS implementation when Conscrypt is not bundled.
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider
