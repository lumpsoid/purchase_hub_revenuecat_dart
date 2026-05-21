import 'dart:async';
import 'dart:io';

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
    _client.addCustomerInfoUpdateListener(_onCustomerUpdate);
  }

  Future<void> _onCustomerUpdate(rc.CustomerInfo customerInfo) async {
    final sub = await _mapCustomerInfoToSubscription(customerInfo);
    _controller.add(sub);
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
      final ent = _getActiveEntitlement(info);
      if (ent == null) return Subscription.none;

      final packages = await getAvailableProducts();
      final period = _extractPeriodFromPackages(packages, ent.identifier);
      final active = _mapActiveEntitlements(info.entitlements.active.values);
      return _mapEntitlementToSubscription(ent, period, active);
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
          id: pkg.identifier,
          storeId: p.identifier,
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
  Future<PurchaseResult> purchase(
    String productId, {
    PurchaseOptions? options,
  }) async {
    try {
      // Find the package in the current offering
      final offerings = await _client.getOfferings();
      rc.Package? package;
      if (offerings.current == null ||
          offerings.current!.availablePackages.isEmpty) {
        throw ProductNotFoundFailure(productId);
      }
      for (final pkg in offerings.current!.availablePackages) {
        if (pkg.identifier == productId) {
          package = pkg;
          break;
        }
      }

      if (package == null) {
        throw ProductNotFoundFailure(productId);
      }

      rc.GoogleProductChangeInfo? changeInfo;
      if (options != null && Platform.isAndroid) {
        changeInfo = rc.GoogleProductChangeInfo(
          options.currentProductId,
          prorationMode: options.replacementMode == null
              ? null
              : _mapReplacementMode(options.replacementMode!),
        );
      }

      final SubscriptionPeriod period;
      rc.PurchaseResult result;
      period = _mapPackageToPeriod(package);
      result = await _client.purchase(
        rc.PurchaseParams.package(
          package,
          googleProductChangeInfo: changeInfo,
        ),
      );

      if (package.packageType == .custom) {
        return const PurchaseResult(
          isNewPurchase: true, // RC throws if already owned or handles upgrades
        );
      }
      final ent = _getActiveEntitlement(result.customerInfo);
      if (ent == null) {
        // need to chech in which case this is possible
        // 1. in case the purchase targets non subscription
        throw ProductNotFoundFailure(productId);
      }
      final active = _mapActiveEntitlements(
        result.customerInfo.entitlements.active.values,
      );

      final subscription = _mapEntitlementToSubscription(ent, period, active);
      _controller.add(subscription);

      return PurchaseResult(
        subscription: subscription,
        isNewPurchase: true, // RC throws if already owned or handles upgrades
      );
    } on PlatformException catch (e) {
      throw _handleException(e);
    }
  }

  SubscriptionPeriod _mapPackageToPeriod(rc.Package package) {
    return switch (package.packageType) {
      rc.PackageType.unknown => .unknown,
      rc.PackageType.custom => .custom,
      rc.PackageType.lifetime => .lifetime,
      rc.PackageType.annual => .annual,
      rc.PackageType.sixMonth => .semiAnnual,
      rc.PackageType.threeMonth => .quarterly,
      rc.PackageType.twoMonth => .twoMonth,
      rc.PackageType.monthly => .monthly,
      rc.PackageType.weekly => .weekly,
    };
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
  Future<void> syncPurchases() => _client.syncPurchases();

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

  SubscriptionPeriod _extractPeriodFromPackages(
    List<PurchaseProduct> packages,
    String packageIdentifier,
  ) {
    for (var i = 0; i < packages.length; i++) {
      if (packages[i].id == packageIdentifier) {
        return packages[i].period;
      }
    }
    return SubscriptionPeriod.unknown;
  }

  rc.EntitlementInfo? _getActiveEntitlement(rc.CustomerInfo info) {
    if (info.entitlements.active.isEmpty) {
      return null;
    }

    // We take the one with the latest expiration date.
    final active = info.entitlements.active.values.toList()
      ..sort(
        (a, b) => (b.expirationDate ?? '').compareTo(a.expirationDate ?? ''),
      );

    return active.first;
  }

  List<Entitlement> _mapActiveEntitlements(
    Iterable<rc.EntitlementInfo> activeEntitlements,
  ) {
    return activeEntitlements
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
        .toList();
  }

  Future<Subscription> _mapCustomerInfoToSubscription(
    rc.CustomerInfo info,
  ) async {
    final ent = _getActiveEntitlement(info);
    if (ent == null) return Subscription.none;

    final packages = await getAvailableProducts();
    final period = _extractPeriodFromPackages(packages, ent.identifier);
    final active = _mapActiveEntitlements(info.entitlements.active.values);
    return _mapEntitlementToSubscription(ent, period, active);
  }

  Subscription _mapEntitlementToSubscription(
    rc.EntitlementInfo entitlement,
    SubscriptionPeriod subPeriod,
    Entitlements? entitlements,
  ) {
    return Subscription(
      productId: entitlement.productIdentifier,
      period: subPeriod,
      status: _mapRCStatus(entitlement),
      scope: SubscriptionScope.fromProductId(entitlement.productIdentifier),
      willRenew: entitlement.willRenew,
      isTrial: entitlement.periodType == rc.PeriodType.trial,
      expiresAt: entitlement.expirationDate != null
          ? DateTime.tryParse(entitlement.expirationDate!)
          : null,
      purchasedAt: DateTime.tryParse(entitlement.latestPurchaseDate),
      entitlements: entitlements,
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

  rc.GoogleProrationMode _mapReplacementMode(PurchaseReplacementMode mode) =>
      switch (mode) {
        PurchaseReplacementMode.immediateWithTimeProration =>
          rc.GoogleProrationMode.immediateWithTimeProration,
        PurchaseReplacementMode.immediateWithoutProration =>
          rc.GoogleProrationMode.immediateWithoutProration,
        PurchaseReplacementMode.immediateAndChargeFullPrice =>
          rc.GoogleProrationMode.immediateAndChargeFullPrice,
        PurchaseReplacementMode.immediateAndChargeProratedPrice =>
          rc.GoogleProrationMode.immediateAndChargeProratedPrice,
        PurchaseReplacementMode.deferred => rc.GoogleProrationMode.deferred,
      };
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
