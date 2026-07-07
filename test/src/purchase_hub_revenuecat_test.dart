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
  rc.Store store = rc.Store.appStore,
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
  when(() => mock.store).thenReturn(store);
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

/// A valid single-package offering, used as the default `getOfferings` stub so
/// any flow that reaches `getAvailableProducts` has something to map.
MockOfferings _makeOfferings({
  String packageId = 'com.app.pro.monthly',
  rc.PackageType packageType = rc.PackageType.monthly,
}) {
  final product = MockStoreProduct();
  when(() => product.identifier).thenReturn(packageId);
  when(() => product.title).thenReturn('Pro Monthly');
  when(() => product.description).thenReturn('Full access');
  when(() => product.priceString).thenReturn(r'$4.99');
  when(() => product.price).thenReturn(4.99);
  when(() => product.currencyCode).thenReturn('USD');
  when(() => product.subscriptionPeriod).thenReturn('P1M');
  when(() => product.introductoryPrice).thenReturn(null);

  final pkg = MockPackage();
  when(() => pkg.identifier).thenReturn(packageId);
  when(() => pkg.storeProduct).thenReturn(product);
  when(() => pkg.packageType).thenReturn(packageType);

  final offering = MockOffering();
  when(() => offering.availablePackages).thenReturn([pkg]);
  final offerings = MockOfferings();
  when(() => offerings.current).thenReturn(offering);
  return offerings;
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
  late RevenueCatConfiguration configuration;
  late RevenueCatPurchaseAdapter adapter;

  setUpAll(() {
    registerFallbackValue(MockPurchasesConfiguration());
    registerFallbackValue(FakePurchaseParams());
    registerFallbackValue(rc.LogLevel.debug);
  });

  setUp(() {
    client = MockRCClient();
    configuration = const RevenueCatConfiguration(apiKey: 'test_api_key');
    adapter = RevenueCatPurchaseAdapter(configuration, client: client);

    // Default offering so flows that reach getAvailableProducts have data.
    // Individual tests re-stub getOfferings where they need different data.
    final offerings = _makeOfferings();
    when(() => client.getOfferings()).thenAnswer((_) async => offerings);
  });

  tearDown(() async => adapter.dispose());

  // initialize

  group('initialize', () {
    test('configures RC with the mapped configuration', () async {
      when(() => client.configure(any())).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);

      await adapter.initialize();

      final captured =
          verify(() => client.configure(captureAny())).captured.single
              as rc.PurchasesConfiguration;
      expect(captured.apiKey, 'test_api_key');
    });

    test('does not set a log level when none is configured', () async {
      when(() => client.configure(any())).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);

      await adapter.initialize();

      verifyNever(() => client.setLogLevel(any()));
    });

    test('sets the configured log level before configuring', () async {
      final loggingAdapter = RevenueCatPurchaseAdapter(
        const RevenueCatConfiguration(
          apiKey: 'test_api_key',
          logLevel: RevenueCatLogLevel.debug,
        ),
        client: client,
      );
      when(() => client.setLogLevel(any())).thenAnswer((_) async {});
      when(() => client.configure(any())).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);

      await loggingAdapter.initialize();

      verifyInOrder([
        () => client.setLogLevel(rc.LogLevel.debug),
        () => client.configure(any()),
      ]);
      await loggingAdapter.dispose();
    });

    test('registers a customer info update listener', () async {
      when(() => client.configure(any())).thenAnswer((_) async {});
      when(() => client.addCustomerInfoUpdateListener(any())).thenReturn(null);

      await adapter.initialize();

      verify(() => client.addCustomerInfoUpdateListener(any())).called(1);
    });

    test('listener pipes mapped subscription into the stream', () async {
      when(() => client.configure(any())).thenAnswer((_) async {});

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
      when(() => client.configure(any())).thenAnswer((_) async {});
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
      final customerInfo = _makeCustomerInfo();
      when(
        () => client.getCustomerInfo(),
      ).thenAnswer((_) async => customerInfo);

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
      when(() => pkg.identifier).thenReturn(identifier);
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
      final offerings = offeringsFrom([makePackage()]);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);

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

      final offerings = offeringsFrom([makePackage(introductoryPrice: intro)]);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);

      final products = await adapter.getAvailableProducts();

      expect(products.first.introductoryOffer, isNotNull);
      expect(products.first.introductoryOffer!.isTrial, isTrue);
      expect(products.first.introductoryOffer!.periodNumberOfUnits, 7);
    });

    test('maps lifetime package type', () async {
      final offerings = offeringsFrom([
        makePackage(
          packageType: rc.PackageType.lifetime,
          subscriptionPeriod: null,
        ),
      ]);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);

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
      final offerings = offeringsFrom([]);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);

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
      when(() => pkg.identifier).thenReturn(id);
      when(() => pkg.storeProduct).thenReturn(product);
      when(() => pkg.packageType).thenReturn(rc.PackageType.monthly);
      final offering = MockOffering();
      when(() => offering.availablePackages).thenReturn([pkg]);
      final offerings = MockOfferings();
      when(() => offerings.current).thenReturn(offering);
      return offerings;
    }

    rc.PurchaseResult purchaseResult() {
      final customerInfo = _makeCustomerInfo();
      final result = MockPurchaseResult();
      when(() => result.customerInfo).thenReturn(customerInfo);
      return result;
    }

    test('purchases via package when product is in current offering', () async {
      final offerings = offeringsWithProduct(productId);
      final purchaseRes = purchaseResult();
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);
      when(() => client.purchase(any())).thenAnswer((_) async => purchaseRes);

      final result = await adapter.purchase(productId);

      expect(result.isNewPurchase, isTrue);
      expect(result.subscription!.productId, productId);

      // Verify the params were built with a package (not a bare product).
      final captured = verify(() => client.purchase(captureAny())).captured;
      expect(
        (captured.single as rc.PurchaseParams).package,
        isNotNull,
      );
    });

    test(
      'throws ProductNotFoundFailure when product not in offering',
      () async {
        // Offering contains a different product than the one requested.
        final offerings = offeringsWithProduct('com.app.pro.annual');
        when(() => client.getOfferings()).thenAnswer((_) async => offerings);

        await expectLater(
          adapter.purchase(productId),
          throwsA(isA<ProductNotFoundFailure>()),
        );
        verifyNever(() => client.purchase(any()));
      },
    );

    test('throws PurchaseCancelledFailure when user cancels', () {
      final offerings = offeringsWithProduct(productId);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.purchaseCancelledError),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<PurchaseCancelledFailure>()),
      );
    });

    test('throws AlreadySubscribedFailure when already purchased', () {
      final offerings = offeringsWithProduct(productId);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.productAlreadyPurchasedError),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<AlreadySubscribedFailure>()),
      );
    });

    test('throws PurchasesNotAllowedFailure', () {
      final offerings = offeringsWithProduct(productId);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.purchaseNotAllowedError),
      );

      expect(
        adapter.purchase(productId),
        throwsA(isA<PurchasesNotAllowedFailure>()),
      );
    });

    test('throws ProductNotFoundFailure', () {
      final offerings = offeringsWithProduct(productId);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);
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
      final offerings = offeringsWithProduct(productId);
      when(() => client.getOfferings()).thenAnswer((_) async => offerings);
      when(() => client.purchase(any())).thenThrow(
        _platformException(rc.PurchasesErrorCode.configurationError),
      );

      expect(adapter.purchase(productId), throwsA(isA<StoreFailure>()));
    });
  });

  // restorePurchases

  group('restorePurchases', () {
    test('returns subscription on successful restore', () async {
      final customerInfo = _makeCustomerInfo();
      when(
        () => client.restorePurchases(),
      ).thenAnswer((_) async => customerInfo);

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
      final customerInfo = _makeCustomerInfo();
      final loginResult = MockLogInResult();
      when(() => loginResult.customerInfo).thenReturn(customerInfo);
      when(() => loginResult.created).thenReturn(false);
      when(() => client.logIn('user-123')).thenAnswer((_) async => loginResult);

      await adapter.setUserId('user-123');

      verify(() => client.logIn('user-123')).called(1);
      verifyNever(() => client.logOut());
    });

    test('calls logOut when userId is null', () async {
      final customerInfo = _makeCustomerInfo();
      when(() => client.logOut()).thenAnswer((_) async => customerInfo);

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

        final customerInfo = _makeCustomerInfo(
          activeEntitlements: [earlier, later],
        );
        when(
          () => client.getCustomerInfo(),
        ).thenAnswer((_) async => customerInfo);

        final result = await adapter.getCurrentSubscription();

        expect(result.productId, 'com.app.pro.annual');
      },
    );

    test('maps isTrial=true when periodType is trial', () async {
      final customerInfo = _makeCustomerInfo(
        activeEntitlements: [
          _makeEntitlement(periodType: rc.PeriodType.trial),
        ],
      );
      when(
        () => client.getCustomerInfo(),
      ).thenAnswer((_) async => customerInfo);

      expect((await adapter.getCurrentSubscription()).isTrial, isTrue);
    });

    test(
      'maps status to gracePeriod when billingIssueDetectedAt is set',
      () async {
        final customerInfo = _makeCustomerInfo(
          activeEntitlements: [
            _makeEntitlement(billingIssueDetectedAt: '2026-04-01T00:00:00Z'),
          ],
        );
        when(
          () => client.getCustomerInfo(),
        ).thenAnswer((_) async => customerInfo);

        expect(
          (await adapter.getCurrentSubscription()).status,
          SubscriptionStatus.gracePeriod,
        );
      },
    );

    test(
      'maps status to cancelled when unsubscribeDetectedAt is set',
      () async {
        final customerInfo = _makeCustomerInfo(
          activeEntitlements: [
            _makeEntitlement(unsubscribeDetectedAt: '2026-04-01T00:00:00Z'),
          ],
        );
        when(
          () => client.getCustomerInfo(),
        ).thenAnswer((_) async => customerInfo);

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

      final customerInfo = _makeCustomerInfo(activeEntitlements: [e1, e2]);
      when(
        () => client.getCustomerInfo(),
      ).thenAnswer((_) async => customerInfo);

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
