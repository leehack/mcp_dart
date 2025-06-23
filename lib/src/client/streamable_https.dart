// Export the appropriate implementation based on platform
// Default to web version (WASM compatible), conditionally use VM version
export 'streamable_https_web.dart'
    if (dart.library.io) 'streamable_https_io.dart';
