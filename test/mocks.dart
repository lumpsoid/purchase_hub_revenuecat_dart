import 'package:mocktail/mocktail.dart';
import 'package:purchase_hub_revenuecat/src/rc_client.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

// Our seam — the only mock that matters for the adapter tests
class MockRCClient extends Mock implements RCClient {}

// RC value-object mocks
class MockPurchasesConfiguration extends Mock
    implements rc.PurchasesConfiguration {}

class MockCustomerInfo extends Mock implements rc.CustomerInfo {}

class MockEntitlements extends Mock implements rc.EntitlementInfos {}

class MockEntitlementInfo extends Mock implements rc.EntitlementInfo {}

class MockOfferings extends Mock implements rc.Offerings {}

class MockOffering extends Mock implements rc.Offering {}

class MockPackage extends Mock implements rc.Package {}

class MockStoreProduct extends Mock implements rc.StoreProduct {}

class MockIntroductoryPrice extends Mock implements rc.IntroductoryPrice {}

class MockPurchaseResult extends Mock implements rc.PurchaseResult {}

class MockLogInResult extends Mock implements rc.LogInResult {}
