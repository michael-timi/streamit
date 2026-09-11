class AppAssets {
  AppAssets._();

  static const String _basePath = 'assets';
  static const String _iconsPath = '$_basePath/icons';

  // SVGs
  static const String googleIcon = '$_iconsPath/google.svg';
  static const String facebookIcon = '$_iconsPath/facebook.svg';
  static const String appleIcon = '$_iconsPath/apple.svg';

  /// Vector logo (UI, sharp on all densities).
  static const String streamitLogoSvg = '$_iconsPath/streamit_logo.svg';
  /// PNG raster of [streamitLogoSvg] for flutter_native_splash (native splash requires PNG).
  static const String streamitLogo = '$_iconsPath/streamit_logo.png';
  /// 512×512, opaque, brand background `#0B1220` (store listings, etc.).
  static const String streamitLogo512 = '$_iconsPath/streamit_logo_512.png';

  // You can add more categories here as well, such as:
  // static const String _imagesPath = '$_basePath/images';
  // static const String logo = '$_imagesPath/logo.png';
}
