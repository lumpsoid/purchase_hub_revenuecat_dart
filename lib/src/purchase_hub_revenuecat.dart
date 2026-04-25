import 'dart:async';

import 'package:flutter/services.dart';
import 'package:purchase_hub_core/purchase_hub_core.dart';
import 'package:purchase_hub_revenuecat/src/rc_client.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

/// {@template purchase_hub_revenuecat}
/// A [PurchaseAdapter] implementation powered by RevenueCat.
/// {@endtemplate}
final class RevenueCatPurchaseAdapter implements PurchaseAdapter {
  /// {@macro purchase_hub_revenuecat}
  RevenueCatPurchaseAdapter(
    this._configuration, {
    RCClient client = const LiveRCClient(),
  }) : _client = client;

  final rc.PurchasesConfiguration _configuration;
  final RCClient _client;
  final StreamController<Subscription> _controller =
      StreamController<Subscription>.broadcast();

  @override
  Future<void> initialize() async {
    await _client.configure(_configuration);

    // Listen for customer info updates from RC and pipe them to our domain
    _client.addCustomerInfoUpdateListener((customerInfo) {
      _controller.add(_mapCustomerInfoToSubscription(customerInfo));
    });
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Stream<Subscription> get subscriptionUpdates => _controller.stream;

  @override
  Future<Subscription> getCurrentSubscription() async {
    try {
      final info = await _client.getCustomerInfo();
      return _mapCustomerInfoToSubscription(info);
    } on PlatformException catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<List<PurchaseProduct>> getAvailableProducts() async {
    try {
      final offerings = await _client.getOfferings();
      final current = offerings.current;

      if (current == null || current.availablePackages.isEmpty) {
        throw const NoOfferingsFailure();
      }

      return current.availablePackages.map((pkg) {
        final p = pkg.storeProduct;
        return PurchaseProduct(
          id: p.identifier,
          title: p.title,
          description: p.description,
          priceString: p.priceString,
          price: p.price,
          currencyCode: p.currencyCode,
          period: _mapRCPeriodToDomain(p.subscriptionPeriod, pkg.packageType),
          scope: SubscriptionScope.fromProductId(p.identifier),
          introductoryOffer: p.introductoryPrice != null
              ? IntroductoryOffer(
                  priceString: p.introductoryPrice!.priceString,
                  price: p.introductoryPrice!.price,
                  periodNumberOfUnits: p.introductoryPrice!.periodNumberOfUnits,
                  periodUnit: p.introductoryPrice!.periodUnit.name,
                  isTrial: p.introductoryPrice!.price == 0,
                )
              : null,
        );
      }).toList();
    } on PlatformException catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<PurchaseResult> purchase(String productId) async {
    try {
      // Find the package in the current offering
      final offerings = await _client.getOfferings();
      final package = offerings.current?.availablePackages
          .where((pkg) => pkg.storeProduct.identifier == productId)
          .firstOrNull;

      rc.PurchaseResult result;
      if (package != null) {
        result = await _client.purchase(
          rc.PurchaseParams.package(package),
        );
      } else {
        // Fallback to purchasing product directly if not in offering
        result = await _client.purchase(
          rc.PurchaseParams.storeProduct(
            (await _client.getProducts([productId])).first,
          ),
        );
      }

      final subscription = _mapCustomerInfoToSubscription(result.customerInfo);
      return PurchaseResult(
        subscription: subscription,
        isNewPurchase: true, // RC throws if already owned or handles upgrades
      );
    } on PlatformException catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<Subscription> restorePurchases() async {
    try {
      final info = await _client.restorePurchases();
      if (info.entitlements.active.isEmpty) {
        throw const NoPurchasesToRestoreFailure();
      }
      return _mapCustomerInfoToSubscription(info);
    } on PlatformException catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<void> setUserId(String? userId) async {
    try {
      if (userId == null) {
        await _client.logOut();
      } else {
        await _client.logIn(userId);
      }
    } on PlatformException catch (e) {
      throw _handleException(e);
    }
  }

  Subscription _mapCustomerInfoToSubscription(rc.CustomerInfo info) {
    if (info.entitlements.active.isEmpty) {
      return Subscription.none;
    }

    // RevenueCat usually has one primary entitlement for "Pro" access.
    // We take the one with the latest expiration date.
    final active = info.entitlements.active.values.toList()
      ..sort(
        (a, b) => (b.expirationDate ?? '').compareTo(a.expirationDate ?? ''),
      );

    final entitlement = active.first;

    return Subscription(
      productId: entitlement.productIdentifier,
      period: SubscriptionPeriod.monthly, // Default, updated on product fetch
      status: _mapRCStatus(entitlement),
      scope: SubscriptionScope.fromProductId(entitlement.productIdentifier),
      willRenew: entitlement.willRenew,
      isTrial: entitlement.periodType == rc.PeriodType.trial,
      expiresAt: entitlement.expirationDate != null
          ? DateTime.tryParse(entitlement.expirationDate!)
          : null,
      purchasedAt: DateTime.tryParse(entitlement.latestPurchaseDate),
      entitlements: info.entitlements.active.values
          .map(
            (e) => Entitlement(
              id: e.identifier,
              productId: e.productIdentifier,
              willRenew: e.willRenew,
              expiresAt: e.expirationDate != null
                  ? DateTime.tryParse(e.expirationDate!)
                  : null,
            ),
          )
          .toList(),
    );
  }

  SubscriptionStatus _mapRCStatus(rc.EntitlementInfo info) {
    if (!info.isActive) return SubscriptionStatus.inactive;
    if (info.billingIssueDetectedAt != null) {
      return SubscriptionStatus.gracePeriod;
    }
    if (info.unsubscribeDetectedAt != null) return SubscriptionStatus.cancelled;
    return SubscriptionStatus.active;
  }

  SubscriptionPeriod _mapRCPeriodToDomain(
    String? isoPeriod,
    rc.PackageType type,
  ) {
    if (type == rc.PackageType.lifetime) return SubscriptionPeriod.lifetime;
    if (type == rc.PackageType.annual) return SubscriptionPeriod.annual;
    if (type == rc.PackageType.monthly) return SubscriptionPeriod.monthly;

    return switch (isoPeriod) {
      'P1Y' => SubscriptionPeriod.annual,
      'P6M' => SubscriptionPeriod.semiAnnual,
      'P3M' => SubscriptionPeriod.quarterly,
      'P1M' => SubscriptionPeriod.monthly,
      'P1W' => SubscriptionPeriod.weekly,
      _ => SubscriptionPeriod.monthly,
    };
  }

  PurchaseFailure _handleException(PlatformException e) {
    final code = rc.PurchasesErrorHelper.getErrorCode(e);
    return switch (code) {
      rc.PurchasesErrorCode.purchaseCancelledError =>
        const PurchaseCancelledFailure(),
      rc.PurchasesErrorCode.productAlreadyPurchasedError =>
        const AlreadySubscribedFailure(),
      rc.PurchasesErrorCode.networkError => NetworkFailure(e.message),
      rc.PurchasesErrorCode.purchaseNotAllowedError =>
        const PurchasesNotAllowedFailure(),
      rc.PurchasesErrorCode.productNotAvailableForPurchaseError =>
        ProductNotFoundFailure(e.toString()),
      rc.PurchasesErrorCode.configurationError => StoreFailure(
        'RC Config Error: ${e.message}',
      ),
      _ => UnknownPurchaseFailure(e.message),
    };
  }
}

/// {@template revenue_cat_initializer}
/// Initializer for RevenueCat.
/// {@endtemplate}
final class RevenueCatInitializer implements PurchaseInitializer {
  /// {@macro revenue_cat_initializer}
  const RevenueCatInitializer(this.configuration);

  /// Configuration of RevenueCat
  final rc.PurchasesConfiguration configuration;

  @override
  PurchaseAdapter createAdapter() => RevenueCatPurchaseAdapter(configuration);
}
