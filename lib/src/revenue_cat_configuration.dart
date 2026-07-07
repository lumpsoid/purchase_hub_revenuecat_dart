/// {@template revenue_cat_configuration}
/// Configuration for the RevenueCat adapter.
///
/// This is a deliberate, SDK-free mirror of RevenueCat's
/// `PurchasesConfiguration`. It lets consumers configure the adapter without
/// taking a direct dependency on `purchases_flutter`, keeping the RevenueCat
/// SDK fully encapsulated behind this package.
/// {@endtemplate}
final class RevenueCatConfiguration {
  /// {@macro revenue_cat_configuration}
  const RevenueCatConfiguration({
    required this.apiKey,
    this.appUserId,
    this.store,
    this.preferredUILocaleOverride,
    this.userDefaultsSuiteName,
    this.storeKitVersion,
    this.purchaseCompletion,
    this.logLevel,
    this.entitlementVerificationMode =
        RevenueCatEntitlementVerificationMode.disabled,
    this.shouldShowInAppMessagesAutomatically = true,
    this.pendingTransactionsForPrepaidPlansEnabled = false,
    this.automaticDeviceIdentifierCollectionEnabled = true,
    this.diagnosticsEnabled = false,
  });

  /// RevenueCat API key.
  final String apiKey;

  /// Optional unique id used to identify the user.
  final String? appUserId;

  /// The store backing this configuration.
  ///
  /// Only [RevenueCatStore.amazon] changes SDK behavior (it is required for the
  /// Amazon Appstore); the other values are detected automatically and are
  /// provided for clarity.
  final RevenueCatStore? store;

  /// Optional locale identifier overriding the device locale for purchases and
  /// offerings (e.g. `"es-ES"` or `"es_ES"`). Defaults to the device locale.
  final String? preferredUILocaleOverride;

  /// iOS-only. Name of the `NSUserDefaults` suite the SDK stores preferences
  /// in. `null` uses `standardUserDefaults`.
  final String? userDefaultsSuiteName;

  /// iOS-only. Which StoreKit version the SDK should use. `null` lets
  /// RevenueCat decide.
  final RevenueCatStoreKitVersion? storeKitVersion;

  /// Who finalizes purchases. `null` defaults to RevenueCat completing them.
  final RevenueCatPurchaseCompletion? purchaseCompletion;

  /// Verbosity of the RevenueCat SDK's own logging. `null` leaves the SDK
  /// default in place (the adapter does not touch the log level).
  final RevenueCatLogLevel? logLevel;

  /// Entitlement verification strictness. Defaults to
  /// [RevenueCatEntitlementVerificationMode.disabled].
  final RevenueCatEntitlementVerificationMode entitlementVerificationMode;

  /// Whether store in-app messages (e.g. billing issues) are shown
  /// automatically. Defaults to `true`.
  final bool shouldShowInAppMessagesAutomatically;

  /// Allow pending purchases for prepaid subscriptions (Google Play only).
  /// Defaults to `false`.
  final bool pendingTransactionsForPrepaidPlansEnabled;

  /// Allow collecting device identifiers when setting an attribution network
  /// id. Defaults to `true`.
  final bool automaticDeviceIdentifierCollectionEnabled;

  /// Send performance/debugging diagnostics to RevenueCat. Defaults to `false`.
  final bool diagnosticsEnabled;
}

/// Mirror of RevenueCat's `Store` for configuration purposes.
enum RevenueCatStore {
  /// Apple App Store.
  appStore,

  /// Google Play Store.
  playStore,

  /// Amazon Appstore. Required to run against the Amazon Appstore.
  amazon,
}

/// Mirror of RevenueCat's `StoreKitVersion` (iOS-only).
enum RevenueCatStoreKitVersion {
  /// Always use StoreKit 1.
  storeKit1,

  /// Always use StoreKit 2 (falls back to StoreKit 1 when unavailable).
  storeKit2,

  /// Let RevenueCat pick the most appropriate StoreKit version.
  defaultVersion,
}

/// Mirror of RevenueCat's `LogLevel`, ordered from most to least verbose.
enum RevenueCatLogLevel {
  /// Everything, including internal SDK details.
  verbose,

  /// Debug messages and above.
  debug,

  /// Informational messages and above.
  info,

  /// Warnings and errors only.
  warn,

  /// Errors only.
  error,
}

/// Mirror of RevenueCat's `EntitlementVerificationMode`.
enum RevenueCatEntitlementVerificationMode {
  /// No entitlement verification is performed.
  disabled,

  /// Verification is performed; failures are reported but still grant access.
  informational,
}

/// Who is responsible for finalizing purchases.
///
/// Mirror of RevenueCat's `PurchasesAreCompletedBy`.
sealed class RevenueCatPurchaseCompletion {
  /// {@macro revenue_cat_purchase_completion}
  const RevenueCatPurchaseCompletion();

  /// RevenueCat finalizes purchases (the default behavior).
  const factory RevenueCatPurchaseCompletion.revenueCat() =
      RevenueCatCompletedByRevenueCat;

  /// Your own IAP implementation finalizes purchases; RevenueCat is used as a
  /// backend only. Requires a [storeKitVersion].
  const factory RevenueCatPurchaseCompletion.myApp({
    required RevenueCatStoreKitVersion storeKitVersion,
  }) = RevenueCatCompletedByMyApp;
}

/// Purchases are finalized by RevenueCat.
final class RevenueCatCompletedByRevenueCat
    extends RevenueCatPurchaseCompletion {
  /// Creates a [RevenueCatCompletedByRevenueCat].
  const RevenueCatCompletedByRevenueCat();
}

/// Purchases are finalized by your own IAP implementation.
final class RevenueCatCompletedByMyApp extends RevenueCatPurchaseCompletion {
  /// Creates a [RevenueCatCompletedByMyApp].
  const RevenueCatCompletedByMyApp({required this.storeKitVersion});

  /// StoreKit version your IAP implementation uses.
  final RevenueCatStoreKitVersion storeKitVersion;
}
