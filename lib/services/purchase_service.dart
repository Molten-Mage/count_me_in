import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'analytics_service.dart';
import 'premium_service.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('[PurchaseService] $message');
}

/// The App Store Connect / Play Console product identifier for the
/// one-time Premium unlock. Matches the Non-Consumable product created in
/// App Store Connect (Monetization → In-App Purchases). Still needs a
/// matching product created in Play Console with this same ID for Android
/// purchases to work there too.
const premiumProductId = 'premium_unlock01';

/// Wraps the `in_app_purchase` package for the app's one product: a
/// single non-consumable "Premium" unlock. [buyPremium] only reports
/// whether the purchase *flow started* (the store's native payment sheet
/// appeared) — the actual grant happens asynchronously via [init]'s
/// stream listener, which flips [premiumStatus] once the store confirms.
///
/// Cross-device sync relies entirely on the platform store's own
/// restore-purchases mechanism (see [restore]) — purchase state isn't
/// mirrored to Firestore, so a signed-in user on a second device still
/// needs to tap "Restore purchases" once. Doing better than that would
/// need server-side receipt verification (the App Store Server API, a
/// Cloud Function, since trusting the client's own write in from here
/// isn't enough on its own) — deliberately deferred as separate work.
class PurchaseService {
  PurchaseService({InAppPurchase? inAppPurchase})
    : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Starts listening for purchase updates — call once, e.g. from
  /// `main.dart` alongside the app's other service init. Safe to call
  /// more than once; only the first call actually subscribes.
  void init() {
    if (_subscription != null) return;
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object e) => _log('purchaseStream error: $e'),
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // No server-side receipt verification yet (see class doc) —
          // trusting the platform store's own status here, the same
          // trust boundary the rest of this app's client-driven data
          // already relies on.
          await premiumStatus.setPremium(true);
          await analyticsService.logPurchaseCompleted(
            restored: purchase.status == PurchaseStatus.restored,
          );
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          _log('purchase error: ${purchase.error}');
          await analyticsService.logPurchaseFailed();
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
      }
    }
  }

  Future<ProductDetails?> _queryPremiumProduct() async {
    final available = await _iap.isAvailable();
    if (!available) return null;
    final response = await _iap.queryProductDetails({premiumProductId});
    if (response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// The premium product's localized price straight from the store — null
  /// if the store isn't reachable or the product doesn't exist yet (e.g.
  /// no App Store Connect record). Callers should fall back to
  /// [PremiumService.priceLabel] in that case.
  Future<String?> premiumPriceLabel() async {
    final product = await _queryPremiumProduct();
    return product?.price;
  }

  /// Starts the purchase flow. Returns whether it actually started (the
  /// store's payment sheet was shown) — not whether the purchase itself
  /// succeeded, which arrives later via [init]'s stream listener and
  /// shows up as [premiumStatus] flipping to `true`.
  Future<bool> buyPremium() async {
    final product = await _queryPremiumProduct();
    if (product == null) return false;

    final param = PurchaseParam(productDetails: product);
    try {
      return await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _log('buyNonConsumable failed: $e');
      return false;
    }
  }

  Future<void> restore() => _iap.restorePurchases();
}

final purchaseService = PurchaseService();
