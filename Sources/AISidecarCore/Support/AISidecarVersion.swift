/// Single source of truth for the product version (packaging plan D5).
///
/// Feeds `aisidecar --version`, the CupricAspect About card, and — via the
/// release build script's `CFBundleShortVersionString` injection — the app
/// bundle's Info.plist. Distinct from schema/engine/recipe versions, which
/// track document formats, not the product.
public enum AISidecarVersion {
    public static let current = "0.1.0-beta.1"
}
