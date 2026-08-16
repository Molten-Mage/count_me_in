import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('[ConsentService] $message');
}

/// Gathers ad-related consent before any ad is ever requested:
/// 1. Google's User Messaging Platform (UMP) - shows the GDPR/UK consent
///    form when required (EEA/UK users), no-ops elsewhere.
/// 2. iOS App Tracking Transparency - the system permission prompt for
///    cross-app tracking (`NSUserTrackingUsageDescription` is already set
///    in Info.plist). No-op on Android.
/// 3. Only then initializes the Mobile Ads SDK, and only if
///    [ConsentInformation.canRequestAds] actually says it's fine to.
///
/// [ensureReady] is idempotent - safe to call from every `AdBanner` that
/// mounts; they all await the same in-flight/completed operation.
class ConsentService {
  Future<void>? _readyFuture;

  Future<void> ensureReady() => _readyFuture ??= _prepare();

  Future<void> _prepare() async {
    _log('starting');
    _log(
      'consent status before update: '
      '${await ConsentInformation.instance.getConsentStatus()}',
    );

    await _gatherConsent();
    await _requestTrackingAuthorization();

    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    _log('canRequestAds: $canRequestAds');
    if (canRequestAds) {
      try {
        _log('calling MobileAds.instance.initialize()');
        final status = await MobileAds.instance.initialize();
        _log(
          'MobileAds initialized - adapter statuses: '
          '${status.adapterStatuses.map((k, v) => MapEntry(k, v.state))}',
        );
      } catch (e) {
        _log('MobileAds.instance.initialize() threw: $e');
      }
    } else {
      _log('skipping MobileAds init - canRequestAds() was false');
    }
  }

  Future<void> _gatherConsent() async {
    final completer = Completer<void>();
    void finish(String reason) {
      _log('consent gathering finished: $reason');
      if (!completer.isCompleted) completer.complete();
    }

    final params = ConsentRequestParameters(
      // Forces the EEA consent form to appear on debug builds regardless
      // of the device's real location, so it's actually testable.
      consentDebugSettings: kDebugMode
          ? ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea)
          : null,
    );

    _log('calling requestConsentInfoUpdate');
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        _log(
          'requestConsentInfoUpdate succeeded - status: '
          '${await ConsentInformation.instance.getConsentStatus()}, '
          'formAvailable: '
          '${await ConsentInformation.instance.isConsentFormAvailable()}',
        );
        _log('calling loadAndShowConsentFormIfRequired');
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          finish(
            error == null
                ? 'form flow dismissed with no error'
                : 'form flow dismissed with error '
                      '[${error.errorCode}] ${error.message}',
          );
        });
      },
      (error) => finish(
        'requestConsentInfoUpdate failed - '
        '[${error.errorCode}] ${error.message}',
      ),
    );

    await completer.future;
  }

  Future<void> _requestTrackingAuthorization() async {
    if (!Platform.isIOS) return;
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    _log('ATT status before request: $status');
    if (status == TrackingStatus.notDetermined) {
      final result = await AppTrackingTransparency.requestTrackingAuthorization();
      _log('ATT status after request: $result');
    }
  }
}

final consentService = ConsentService();
