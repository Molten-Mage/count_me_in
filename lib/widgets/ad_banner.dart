import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// Test banner ad unit IDs (developers.google.com/admob/{android,ios}/test-ads).
// Replace with real ad unit IDs from the AdMob console before release.
String get _bannerAdUnitId {
  if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/9214589741';
  return 'ca-app-pub-3940256099942544/2435281174'; // iOS
}

/// A top-anchored adaptive banner ad, sized to the available width. Renders
/// nothing while loading, on unsupported platforms, or if the ad fails to
/// load, so it never leaves a visible gap.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _hasRequestedAd = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasRequestedAd) {
      _hasRequestedAd = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    // The non-"large" adaptive size is deprecated in favor of the large
    // one (Google's newer default, picked for better fill/revenue), but
    // it's still fully functional — used deliberately here for a shorter
    // banner instead.
    // ignore: deprecated_member_use
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width,
    );
    if (size == null || !mounted) return;

    final ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
