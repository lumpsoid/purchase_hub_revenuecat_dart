// test/revenue_cat_purchase_adapter_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:purchase_hub_core/purchase_hub_core.dart';
import 'package:purchase_hub_revenuecat/purchase_hub_revenuecat.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../mocks.dart';

// Helpers

MockEntitlementInfo _makeEntitlement({
  String identifier = 'pro',
  String productIdentifier = 'com.app.pro.monthly',
  bool isActive = true,
  bool willRenew = true,
  String? expirationDate = '2099-12-31T00:00:00Z',
  String latestPurchaseDate = '2026-01-01T00:00:00Z',
  String? billingIssueDetectedAt,
  String? unsubscribeDetectedAt,
  rc.PeriodType periodType = rc.PeriodType.normal,
}) {
  final mock = MockEntitlementInfo();
  when(() => mock.identifier).thenReturn(identifier);
  when(() => mock.productIdentifier).thenReturn(productIdentifier);
  when(() => mock.isActive).thenReturn(isActive);
  when(() => mock.willRenew).thenReturn(willRenew);
  when(() => mock.expirationDate).thenReturn(expirationDate);
  when(() => mock.latestPurchaseDate).thenReturn(latestPurchaseDate);
  when(() => mock.billingIssueDetectedAt).thenReturn(billingIssueDetectedAt);
  when(() => mock.unsubscribeDetectedAt).thenReturn(unsubscribeDetectedAt);
  when(() => mock.periodType).thenReturn(periodType);
  return mock;
}

MockCustomerInfo _makeCustomerInfo({
  List<MockEntitlementInfo>? activeEntitlements,
}) {
  final entitlementList = activeEntitlements ?? [_makeEntitlement()];
  final entitlementMap = {for (final e in entitlementList) e.identifier: e};

  final mockEntitlements = MockEntitlements();
  when(() => mockEntitlements.active).thenReturn(entitlementMap);

  final mockInfo = MockCustomerInfo();
  when(() => mockInfo.entitlements).thenReturn(mockEntitlements);
  return mockInfo;
}

PlatformException _platformException(
  rc.PurchasesErrorCode code, {
  String? message,
}) => PlatformException(
  code: code.index.toString(),
  message: message ?? code.name,
  details: {'code': code.index},
);

// Tests

void main() {
  late MockRCClient client;
  late MockPurchasesConfiguration configuration;
  late RevenueCatPurchaseAdapter adapter;

  setUp(() {
    client = MockRCClient();
    configuration = MockPurchasesConfiguration();
    adapter = RevenueCatPurchaseAdapter(configuration, client: client);
  });

  tearDown(() async => adapter.dispose());

  // initialize

  group('initialize', () {
    test('configures RC with the provided configuration', () async {
      when(() => client.configure(configuration)).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);

      await adapter.initialize();

      verify(() => client.configure(configuration)).called(1);
    });

    test('registers a customer info update listener', () async {
      when(() => client.configure(configuration)).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);

      await adapter.initialize();

      verify(() => client.addCustomerInfoUpdateListener(any())).called(1);
    });

    test('listener pipes mapped subscription into the stream', () async {
      when(() => client.configure(configuration)).thenAnswer((_) async {});

      rc.CustomerInfoUpdateListener? captured;
      when(() => client.addCustomerInfoUpdateListener(any())).thenAnswer((inv) {
        captured =
            inv.positionalArguments.first as rc.CustomerInfoUpdateListener;
      });

      await adapter.initialize();

      final future = adapter.subscriptionUpdates.first;
      captured!(_makeCustomerInfo());

      final sub = await future;
      expect(sub.productId, 'com.app.pro.monthly');
      expect(sub.status, SubscriptionStatus.active);
    });
  });

  // dispose

  group('dispose', () {
    test('closes the subscription stream', () async {
      when(() => client.configure(configuration)).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);
      await adapter.initialize();

      final done = adapter.subscriptionUpdates.toList();
      await adapter.dispose();

      await expectLater(done, completes);
    });
  });

  // getCurrentSubscription

  group('getCurrentSubscription', () {
    test('returns mapped subscription for active entitlements', () async {
      when(
        () => client.getCustomerInfo(),
      ).thenAnswer((_) async => _makeCustomerInfo());

      final result = await adapter.getCurrentSubscription();

      expect(result.productId, 'com.app.pro.monthly');
      expect(result.status, SubscriptionStatus.active);
      expect(result.willRenew, isTrue);
      expect(result.isTrial, isFalse);
      expect(result.expiresAt, isNotNull);
    });

    test('returns Subscription.none when no active entitlements', () async {
      final mockEntitlements = MockEntitlements();
      when(() => mockEntitlements.active).thenReturn({});
      final mockInfo = MockCustomerInfo();
      when(() => mockInfo.entitlements).thenReturn(mockEntitlements);

      when(() => client.getCustomerInfo()).thenAnswer((_) async => mockInfo);

      expect(await adapter.getCurrentSubscription(), equals(Subscription.none));
    });

    test('throws NetworkFailure on networkError', () {
      when(() => client.getCustomerInfo()).thenThrow(
        _platformException(rc.PurchasesErrorCode.networkError),
      );

      expect(
        adapter.getCurrentSubscription(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('throws UnknownPurchaseFailure on unknown error', () {
      when(() => client.getCustomerInfo()).thenThrow(
        _platformException(rc.PurchasesErrorCode.unknownError),
      );

      expect(
        adapter.getCurrentSubscription(),
        throwsA(isA<UnknownPurchaseFailure>()),
      );
    });
  });

  // getAvailableProducts

  group('getAvailableProducts', () {
    MockPackage makePackage({
      String identifier = 'com.app.pro.monthly',
      String title = 'Pro Monthly',
      String description = 'Full access',
      String priceString = r'$4.99',
      double price = 4.99,
      String currencyCode = 'USD',
      String? subscriptionPeriod = 'P1M',
      rc.PackageType packageType = rc.PackageType.monthly,
      rc.IntroductoryPrice? introductoryPrice,
    }) {
      final product = MockStoreProduct();
      when(() => product.identifier).thenReturn(identifier);
      when(() => product.title).thenReturn(title);
      when(() => product.description).thenReturn(description);
      when(() => product.priceString).thenReturn(priceString);
      when(() => product.price).thenReturn(price);
      when(() => product.currencyCode).thenReturn(currencyCode);
      when(() => product.subscriptionPeriod).thenReturn(subscriptionPeriod);
      when(() => product.introductoryPrice).thenReturn(introductoryPrice);

      final pkg = MockPackage();
      when(() => pkg.storeProduct).thenReturn(product);
      when(() => pkg.packageType).thenReturn(packageType);
      return pkg;
    }

    MockOfferings offeringsFrom(List<MockPackage> packages) {
      final offering = MockOffering();
      when(() => offering.availablePackages).thenReturn(packages);
      final offerings = MockOfferings();
      when(() => offerings.current).thenReturn(offering);
      return offerings;
    }

    test('maps packages to PurchaseProduct list', () async {
      when(() => client.getOfferings()).thenAnswer(
        (_) async => offeringsFrom([makePackage()]),
      );

      final products = await adapter.getAvailableProducts();

      expect(products, hasLength(1));
      expect(products.first.id, 'com.app.pro.monthly');
      expect(products.first.period, SubscriptionPeriod.monthly);
      expect(products.first.introductoryOffer, isNull);
    });

    test('maps introductory trial offer', () async {
      final intro = MockIntroductoryPrice();
      when(() => intro.priceString).thenReturn(r'$0.00');
      when(() => intro.price).thenReturn(0);
      when(() => intro.periodNumberOfUnits).thenReturn(7);
      when(() => intro.periodUnit).thenReturn(rc.PeriodUnit.day);

      when(() => client.getOfferings()).thenAnswer(
        (_) async => offeringsFrom([makePackage(introductoryPrice: intro)]),
      );

      final products = await adapter.getAvailableProducts();

      expect(products.first.introductoryOffer, isNotNull);
      expect(products.first.introductoryOffer!.isTrial, isTrue);
      expect(products.first.introductoryOffer!.periodNumberOfUnits, 7);
    });

    test('maps lifetime package type', () async {
      when(() => client.getOfferings()).thenAnswer(
        (_) async => offeringsFrom([
          makePackage(
            packageType: rc.PackageType.lifetime,
            subscriptionPeriod: null,
          ),
        ]),
      );

      final products = await adapter.getAvailableProducts();

      expect(products.first.period, SubscriptionPeriod.lifetime);
    });

    test('throws NoOfferingsFailure when current offering is null', () {
      final offerings = MockOfferings();
      when(() => offerings.current).thenReturn(null);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);

      expect(
        adapter.getAvailableProducts(),
        throwsA(isA<NoOfferingsFailure>()),
      );
    });

    test('throws NoOfferingsFailure when packages list is empty', () {
      when(() => client.getOfferings()).thenAnswer(
        (_) async => offeringsFrom([]),
      );

      expect(
        adapter.getAvailableProducts(),
        throwsA(isA<NoOfferingsFailure>()),
      );
    });

    test('throws NetworkFailure on network error', () {
      when(() => client.getOfferings()).thenThrow(
        _platformException(rc.PurchasesErrorCode.networkError),
      );

      expect(
        adapter.getAvailableProducts(),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // purchase

  group('purchase', () {
    const productId = 'com.app.pro.monthly';

    MockOfferings offeringsWithProduct(String id) {
      final product = MockStoreProduct();
      when(() => product.identifier).thenReturn(id);
      final pkg = MockPackage();
      when(() => pkg.storeProduct).thenReturn(product);
      when(() => pkg.packageType).thenReturn(rc.PackageType.monthly);
      final offering = MockOffering();
      when(() => offering.availablePackages).thenReturn([pkg]);
      final offerings = MockOfferings();
      when(() => offerings.current).thenReturn(offering);
      return offerings;
    }

    rc.PurchaseResult purchaseResult() {
      final result = MockPurchaseResult();
      when(() => result.customerInfo).thenReturn(_makeCustomerInfo());
      return result;
    }

    test('purchases via package when product is in current offering', () async {
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct(productId));
      when(
        () => client.purchase(any()),
      ).thenAnswer((_) async => purchaseResult());

      final result = await adapter.purchase(productId);

      expect(result.isNewPurchase, isTrue);
      expect(result.subscription.productId, productId);

      // Verify the params were built with a package (not a bare product).
      final captured = verify(() => client.purchase(captureAny())).captured;
      expect(
        (captured.single as rc.PurchaseParams).package,
        isNotNull,
      );
    });

    test('falls back to storeProduct purchase when not in offering', () async {
      // Offering contains a different product.
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct('com.app.pro.annual'));

      final fallbackProduct = MockStoreProduct();
      when(() => fallbackProduct.identifier).thenReturn(productId);
      when(
        () => client.getProducts([productId]),
      ).thenAnswer((_) async => [fallbackProduct]);
      when(
        () => client.purchase(any()),
      ).thenAnswer((_) async => purchaseResult());

      final result = await adapter.purchase(productId);

      expect(result.isNewPurchase, isTrue);

      final captured = verify(() => client.purchase(captureAny())).captured;
      expect(
        (captured.single as rc.PurchaseParams).product,
        isNotNull,
      );
    });

    test('throws PurchaseCancelledFailure when user cancels', () {
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct(productId));
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.purchaseCancelledError),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<PurchaseCancelledFailure>()),
      );
    });

    test('throws AlreadySubscribedFailure when already purchased', () {
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct(productId));
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.productAlreadyPurchasedError),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<AlreadySubscribedFailure>()),
      );
    });

    test('throws PurchasesNotAllowedFailure', () {
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct(productId));
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.purchaseNotAllowedError),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<PurchasesNotAllowedFailure>()),
      );
    });

    test('throws ProductNotFoundFailure', () {
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct(productId));
      when(() => client.purchase(any())).thenThrow(
        _platformException(
          rc.PurchasesErrorCode.productNotAvailableForPurchaseError,
        ),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<ProductNotFoundFailure>()),
      );
    });

    test('throws StoreFailure on configuration error', () {
      when(
        () => client.getOfferings(),
      ).thenAnswer((_) async => offeringsWithProduct(productId));
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.configurationError),
      );

      expect(adapter.purchase(productId), throwsA(isA<StoreFailure>()));
    });
  });

  // restorePurchases

  group('restorePurchases', () {
    test('returns subscription on successful restore', () async {
      when(
        () => client.restorePurchases(),
      ).thenAnswer((_) async => _makeCustomerInfo());

      final result = await adapter.restorePurchases();

      expect(result.productId, 'com.app.pro.monthly');
      expect(result.status, SubscriptionStatus.active);
    });

    test('throws NoPurchasesToRestoreFailure when nothing is active', () {
      final mockEntitlements = MockEntitlements();
      when(() => mockEntitlements.active).thenReturn({});
      final mockInfo = MockCustomerInfo();
      when(() => mockInfo.entitlements).thenReturn(mockEntitlements);

      when(() => client.restorePurchases()).thenAnswer((_) async => mockInfo);

      expect(
        adapter.restorePurchases(),
        throwsA(isA<NoPurchasesToRestoreFailure>()),
      );
    });

    test('throws NetworkFailure on network error', () {
      when(() => client.restorePurchases()).thenThrow(
        _platformException(rc.PurchasesErrorCode.networkError),
      );

      expect(adapter.restorePurchases(), throwsA(isA<NetworkFailure>()));
    });
  });

  // setUserId

  group('setUserId', () {
    test('calls logIn when userId is non-null', () async {
      final loginResult = MockLogInResult();
      when(() => loginResult.customerInfo).thenReturn(_makeCustomerInfo());
      when(() => loginResult.created).thenReturn(false);
      when(() => client.logIn('user-123')).thenAnswer((_) async => loginResult);

      await adapter.setUserId('user-123');

      verify(() => client.logIn('user-123')).called(1);
      verifyNever(() => client.logOut());
    });

    test('calls logOut when userId is null', () async {
      when(() => client.logOut()).thenAnswer((_) async => _makeCustomerInfo());

      await adapter.setUserId(null);

      verify(() => client.logOut()).called(1);
      verifyNever(() => client.logIn(any()));
    });

    test('throws NetworkFailure on network error during logIn', () {
      when(() => client.logIn(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.networkError),
      );

      expect(adapter.setUserId('user-123'), throwsA(isA<NetworkFailure>()));
    });

    test('throws NetworkFailure on network error during logOut', () {
      when(() => client.logOut()).thenThrow(
        _platformException(rc.PurchasesErrorCode.networkError),
      );

      expect(adapter.setUserId(null), throwsA(isA<NetworkFailure>()));
    });
  });

  // subscription mapping

  group('subscription mapping', () {
    test(
      'picks entitlement with latest expiration when multiple active',
      () async {
        final earlier = _makeEntitlement(
          identifier: 'basic',
          productIdentifier: 'com.app.basic',
          expirationDate: '2026-06-01T00:00:00Z',
        );
        final later = _makeEntitlement(
          identifier: 'pro',
          productIdentifier: 'com.app.pro.annual',
          expirationDate: '2027-06-01T00:00:00Z',
        );

        when(() => client.getCustomerInfo()).thenAnswer(
          (_) async => _makeCustomerInfo(activeEntitlements: [earlier, later]),
        );

        final result = await adapter.getCurrentSubscription();

        expect(result.productId, 'com.app.pro.annual');
      },
    );

    test('maps isTrial=true when periodType is trial', () async {
      when(() => client.getCustomerInfo()).thenAnswer(
        (_) async => _makeCustomerInfo(
          activeEntitlements: [
            _makeEntitlement(periodType: rc.PeriodType.trial),
          ],
        ),
      );

      expect((await adapter.getCurrentSubscription()).isTrial, isTrue);
    });

    test(
      'maps status to gracePeriod when billingIssueDetectedAt is set',
      () async {
        when(() => client.getCustomerInfo()).thenAnswer(
          (_) async => _makeCustomerInfo(
            activeEntitlements: [
              _makeEntitlement(
                billingIssueDetectedAt: '2026-04-01T00:00:00Z',
              ),
            ],
          ),
        );

        expect(
          (await adapter.getCurrentSubscription()).status,
          SubscriptionStatus.gracePeriod,
        );
      },
    );

    test(
      'maps status to cancelled when unsubscribeDetectedAt is set',
      () async {
        when(() => client.getCustomerInfo()).thenAnswer(
          (_) async => _makeCustomerInfo(
            activeEntitlements: [
              _makeEntitlement(
                unsubscribeDetectedAt: '2026-04-01T00:00:00Z',
              ),
            ],
          ),
        );

        expect(
          (await adapter.getCurrentSubscription()).status,
          SubscriptionStatus.cancelled,
        );
      },
    );

    test('maps status to inactive when isActive is false', () async {
      final entitlement = _makeEntitlement(isActive: false);

      final mockEntitlements = MockEntitlements();
      when(
        () => mockEntitlements.active,
      ).thenReturn({entitlement.identifier: entitlement});
      final mockInfo = MockCustomerInfo();
      when(() => mockInfo.entitlements).thenReturn(mockEntitlements);

      when(() => client.getCustomerInfo()).thenAnswer((_) async => mockInfo);

      expect(
        (await adapter.getCurrentSubscription()).status,
        SubscriptionStatus.inactive,
      );
    });

    test('populates entitlements list from all active entitlements', () async {
      final e1 = _makeEntitlement(
        identifier: 'basic',
        productIdentifier: 'com.app.basic',
        expirationDate: '2026-06-01T00:00:00Z',
      );
      final e2 = _makeEntitlement(
        identifier: 'pro',
        productIdentifier: 'com.app.pro.monthly',
        expirationDate: '2099-12-31T00:00:00Z',
      );

      when(() => client.getCustomerInfo()).thenAnswer(
        (_) async => _makeCustomerInfo(activeEntitlements: [e1, e2]),
      );

      final result = await adapter.getCurrentSubscription();

      expect(result.entitlements, hasLength(2));
      expect(
        result.entitlements!.map((e) => e.id),
        containsAll(['basic', 'pro']),
      );
    });
  });

  // RevenueCatInitializer
  group('RevenueCatInitializer', () {
    test('createAdapter returns a RevenueCatPurchaseAdapter', () {
      final initializer = RevenueCatInitializer(configuration);
      expect(initializer.createAdapter(), isA<RevenueCatPurchaseAdapter>());
    });

    test('exposes the provided configuration', () {
      final initializer = RevenueCatInitializer(configuration);
      expect(initializer.configuration, same(configuration));
    });
  });
}
