import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/consent_service.dart';
import '../services/premium_service.dart';

// Real ad units from the AdMob console (both platforms registered under
// the same publisher, ca-app-pub-7276238684080299).
String get _bannerAdUnitId {
  if (Platform.isAndroid) return 'ca-app-pub-7276238684080299/2221530698';
  return 'ca-app-pub-7276238684080299/9635438129'; // iOS
}

/// A top-anchored adaptive banner ad, sized to the available width. Renders
/// nothing while loading, on unsupported platforms, if the ad fails to
/// load, or for premium accounts, so it never leaves a visible gap.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _hasRequestedAd = false;

  @override
  void initState() {
    super.initState();
    // Debug-only premium status can flip at runtime (Settings' downgrade
    // button); react immediately instead of waiting on an unrelated
    // rebuild. In release builds this never fires since the flag never
    // changes.
    premiumStatus.addListener(_onPremiumChanged);
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    _maybeLoadAd();
    setState(() {});
  }

  void _maybeLoadAd() {
    if (_hasRequestedAd || premiumStatus.value) return;
    _hasRequestedAd = true;
    _loadAd();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoadAd();
  }

  Future<void> _loadAd() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    // Gathers GDPR/UK (UMP) and iOS tracking (ATT) consent, and only then
    // initializes the Mobile Ads SDK — must happen before the first ad is
    // ever requested.
    await consentService.ensureReady();
    if (!mounted) return;

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
        onAdFailedToLoad: (ad, error) {
          if (kDebugMode) debugPrint('AdBanner failed to load: $error');
          ad.dispose();
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    premiumStatus.removeListener(_onPremiumChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (premiumStatus.value) return const SizedBox.shrink();
    final ad = _bannerAd;
    if (ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
