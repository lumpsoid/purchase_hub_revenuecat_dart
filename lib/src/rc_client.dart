// internal usage
// ignore_for_file: public_member_api_docs

import 'package:purchase_hub_revenuecat/src/purchase_hub_revenuecat.dart'
    show RevenueCatPurchaseAdapter;
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

/// Thin interface over RevenueCat's static [rc.Purchases] API.
/// This seam exists solely to make [RevenueCatPurchaseAdapter] testable.
abstract interface class RCClient {
  Future<void> configure(rc.PurchasesConfiguration configuration);

  void addCustomerInfoUpdateListener(rc.CustomerInfoUpdateListener listener);

  Future<rc.CustomerInfo> getCustomerInfo();

  Future<rc.Offerings> getOfferings();

  Future<List<rc.StoreProduct>> getProducts(List<String> productIdentifiers);

  Future<rc.PurchaseResult> purchase(rc.PurchaseParams params);

  Future<rc.CustomerInfo> restorePurchases();

  Future<rc.LogInResult> logIn(String appUserID);

  Future<rc.CustomerInfo> logOut();
}

/// {@template live_rc_client}
/// Production implementation that delegates directly to [rc.Purchases].
/// {@endtemplate}
final class LiveRCClient implements RCClient {
  /// {@macro live_rc_client}
  const LiveRCClient();

  @override
  Future<void> configure(rc.PurchasesConfiguration configuration) =>
      rc.Purchases.configure(configuration);

  @override
  void addCustomerInfoUpdateListener(rc.CustomerInfoUpdateListener listener) =>
      rc.Purchases.addCustomerInfoUpdateListener(listener);

  @override
  Future<rc.CustomerInfo> getCustomerInfo() => rc.Purchases.getCustomerInfo();

  @override
  Future<rc.Offerings> getOfferings() => rc.Purchases.getOfferings();

  @override
  Future<List<rc.StoreProduct>> getProducts(
    List<String> productIdentifiers,
  ) => rc.Purchases.getProducts(productIdentifiers);

  @override
  Future<rc.PurchaseResult> purchase(rc.PurchaseParams params) =>
      rc.Purchases.purchase(params);

  @override
  Future<rc.CustomerInfo> restorePurchases() => rc.Purchases.restorePurchases();

  @override
  Future<rc.LogInResult> logIn(String appUserID) =>
      rc.Purchases.logIn(appUserID);

  @override
  Future<rc.CustomerInfo> logOut() => rc.Purchases.logOut();
}
