// Export the appropriate implementation based on platform
export 'streamable_https_io.dart' 
    if (dart.library.html) 'streamable_https_web.dart';
