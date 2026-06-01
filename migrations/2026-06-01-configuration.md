# Migration: `RevenueCatConfiguration`

The adapter no longer accepts RevenueCat's `PurchasesConfiguration` directly.
Both `RevenueCatPurchaseAdapter` and `RevenueCatInitializer` now take a
`RevenueCatConfiguration` — an SDK-free value object owned by this package.

**Why:** the point of this package is to hide RevenueCat behind
`purchase_hub_core`. Exposing `PurchasesConfiguration` was the one remaining
leak, forcing consumers to depend on `purchases_flutter` directly and coupling
them to the SDK's evolving config surface. `RevenueCatConfiguration` removes
that dependency entirely — the `purchases_flutter` config object is now built
internally and never crosses the package boundary.

This is a **breaking change**.

## Before

```dart
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchase_hub_revenuecat/purchase_hub_revenuecat.dart';

final initializer = RevenueCatInitializer(
  PurchasesConfiguration('your_api_key')
    ..appUserID = 'user-123'
    ..storeKitVersion = StoreKitVersion.storeKit2
    ..diagnosticsEnabled = true,
);
```

## After

```dart
// No purchases_flutter import needed.
import 'package:purchase_hub_revenuecat/purchase_hub_revenuecat.dart';

final initializer = RevenueCatInitializer(
  const RevenueCatConfiguration(
    apiKey: 'your_api_key',
    appUserId: 'user-123',
    storeKitVersion: RevenueCatStoreKitVersion.storeKit2,
    diagnosticsEnabled: true,
  ),
);
```

The same applies when constructing the adapter directly:

```dart
// Before
RevenueCatPurchaseAdapter(PurchasesConfiguration('your_api_key'));

// After
RevenueCatPurchaseAdapter(
  const RevenueCatConfiguration(apiKey: 'your_api_key'),
);
```

You can now drop `purchases_flutter` from your app's `dependencies` if it was
only there to build the configuration.

## Field mapping

`PurchasesConfiguration` was a mutable object configured via field assignment.
`RevenueCatConfiguration` is immutable and configured via named constructor
parameters.

| `PurchasesConfiguration`                     | `RevenueCatConfiguration`                    |
| -------------------------------------------- | -------------------------------------------- |
| `PurchasesConfiguration(apiKey)`             | `apiKey:` (required)                         |
| `appUserID`                                  | `appUserId`                                  |
| `store`                                      | `store` (`RevenueCatStore`)                  |
| `preferredUILocaleOverride`                  | `preferredUILocaleOverride`                  |
| `userDefaultsSuiteName`                      | `userDefaultsSuiteName`                      |
| `storeKitVersion`                            | `storeKitVersion` (`RevenueCatStoreKitVersion`) |
| `purchasesAreCompletedBy`                    | `purchaseCompletion` (`RevenueCatPurchaseCompletion`) |
| `entitlementVerificationMode`                | `entitlementVerificationMode` (`RevenueCatEntitlementVerificationMode`) |
| `shouldShowInAppMessagesAutomatically`       | `shouldShowInAppMessagesAutomatically`       |
| `pendingTransactionsForPrepaidPlansEnabled`  | `pendingTransactionsForPrepaidPlansEnabled`  |
| `automaticDeviceIdentifierCollectionEnabled` | `automaticDeviceIdentifierCollectionEnabled` |
| `diagnosticsEnabled`                         | `diagnosticsEnabled`                         |

### Enum mapping

| RevenueCat SDK                            | This package                                    |
| ----------------------------------------- | ----------------------------------------------- |
| `Store.appStore`                          | `RevenueCatStore.appStore`                      |
| `Store.playStore`                         | `RevenueCatStore.playStore`                     |
| `Store.amazon`                            | `RevenueCatStore.amazon`                        |
| `StoreKitVersion.storeKit1`               | `RevenueCatStoreKitVersion.storeKit1`           |
| `StoreKitVersion.storeKit2`               | `RevenueCatStoreKitVersion.storeKit2`           |
| `StoreKitVersion.defaultVersion`          | `RevenueCatStoreKitVersion.defaultVersion`      |
| `EntitlementVerificationMode.disabled`    | `RevenueCatEntitlementVerificationMode.disabled` |
| `EntitlementVerificationMode.informational` | `RevenueCatEntitlementVerificationMode.informational` |

> Only `RevenueCatStore.amazon` changes SDK behavior (it is required for the
> Amazon Appstore). The other store values are detected automatically and are
> provided for clarity.

### Amazon Appstore

```dart
// Before
RevenueCatInitializer(AmazonConfiguration('your_api_key'));

// After
RevenueCatInitializer(
  const RevenueCatConfiguration(
    apiKey: 'your_api_key',
    store: RevenueCatStore.amazon,
  ),
);
```

### Purchases completed by your own IAP code

`PurchasesAreCompletedBy` maps to the sealed `RevenueCatPurchaseCompletion`:

```dart
// Before
PurchasesConfiguration('your_api_key')
  ..purchasesAreCompletedBy = PurchasesAreCompletedByMyApp(
    storeKitVersion: StoreKitVersion.storeKit2,
  );

// After
const RevenueCatConfiguration(
  apiKey: 'your_api_key',
  purchaseCompletion: RevenueCatPurchaseCompletion.myApp(
    storeKitVersion: RevenueCatStoreKitVersion.storeKit2,
  ),
);
```

`PurchasesAreCompletedByRevenueCat` is the default; pass
`RevenueCatPurchaseCompletion.revenueCat()` to set it explicitly, or leave
`purchaseCompletion` as `null`.
