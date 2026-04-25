
# RevenueCat Purchase Adapter

A robust Flutter/Dart package providing a domain-agnostic implementation of in-app purchase functionality using RevenueCat. Designed with clean architecture principles, this adapter translates RevenueCat's native API into a universal purchase domain model.

## Quick Start

```dart
import 'package:purchase_hub_core/purchase_hub_core.dart';
import 'package:purchase_hub_revenuecat/purchase_hub_revenuecat.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

final adapter = RevenueCatPurchaseAdapter(
  rc.PurchasesConfiguration(
    apiKey: 'your_revenuecat_api_key',
    appUserID: null, // Optional: for identified users
  ),
);

// 1. Initialize
await adapter.initialize();

// 2. Listen to subscription updates
adapter.subscriptionUpdates.listen((subscription) {
  print('Subscription status: ${subscription.status}');
});

// 3. Get current subscription
final current = await adapter.getCurrentSubscription();

// 4. Fetch available products
final products = await adapter.getAvailableProducts();

// 5. Purchase a product
final result = await adapter.purchase('premium_monthly');

// 6. Restore purchases
final restored = await adapter.restorePurchases();

// 7. Set user ID (optional)
await adapter.setUserId('user_123');
```

## API Reference

### `RevenueCatPurchaseAdapter`

Main adapter class implementing the `PurchaseAdapter` interface.

#### Constructor

```dart
RevenueCatPurchaseAdapter(
  rc.PurchasesConfiguration configuration,
)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `configuration` | `rc.PurchasesConfiguration` | RevenueCat configuration object |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `initialize()` | `Future<void>` | Configures RevenueCat and starts listening for updates |
| `dispose()` | `Future<void>` | Closes internal streams and releases resources |
| `subscriptionUpdates` | `Stream<Subscription>` | Live stream of subscription status changes |
| `getCurrentSubscription()` | `Future<Subscription>` | Fetches the user's current subscription |
| `getAvailableProducts()` | `Future<List<PurchaseProduct>>` | Retrieves all available products from the current offering |
| `purchase(String productId)` | `Future<PurchaseResult>` | Initiates purchase flow for specified product |
| `restorePurchases()` | `Future<Subscription>` | Restores previous purchases across devices |
| `setUserId(String? userId)` | `Future<void>` | Logs in (non-null) or logs out (null) the user |

### Domain Models

#### `Subscription`

Represents a user's subscription status.

```dart
final class Subscription {
  final String productId;
  final SubscriptionPeriod period;
  final SubscriptionStatus status;
  final SubscriptionScope scope;
  final bool willRenew;
  final bool isTrial;
  final DateTime? expiresAt;
  final DateTime? purchasedAt;
  final List<Entitlement> entitlements;
}
```

#### `PurchaseProduct`

Represents an available product for purchase.

```dart
final class PurchaseProduct {
  final String id;
  final String title;
  final String description;
  final String priceString;
  final double price;
  final String currencyCode;
  final SubscriptionPeriod period;
  final SubscriptionScope scope;
  final IntroductoryOffer? introductoryOffer;
}
```

#### `PurchaseResult`

Result of a purchase operation.

```dart
final class PurchaseResult {
  final Subscription subscription;
  final bool isNewPurchase;
}
```

### Error Handling

All adapter methods throw typed `PurchaseFailure` exceptions:

| Failure | When Thrown |
|---------|-------------|
| `PurchaseCancelledFailure` | User cancels purchase dialog |
| `AlreadySubscribedFailure` | Product already owned (non-upgradable) |
| `NetworkFailure` | Connectivity issues during API call |
| `ProductNotFoundFailure` | Requested product ID doesn't exist |
| `NoOfferingsFailure` | No products configured in RevenueCat |
| `NoPurchasesToRestoreFailure` | No previous purchases found on restore |
| `StoreFailure` | Underlying store (App Store/Play) error |
| `UnknownPurchaseFailure` | Unhandled RevenueCat error |

**Example error handling**:

```dart
try {
  final result = await adapter.purchase('premium_monthly');
  // Handle success
} on PurchaseCancelledFailure {
  // User cancelled - maybe show a message
} on AlreadySubscribedFailure {
  // Already purchased - navigate to existing subscription
} on PurchaseFailure catch (e) {
  // Generic error handling
  logError('Purchase failed: $e');
}
```

## License

MIT
