import SwiftUI

// MARK: - Backward-compatibility helpers
//
// The app targets iOS 15.0 so it installs on every TrollStore-supported device
// (iOS 14.0 – 16.6.1 / 17.0 betas, and iOS 15 users too). A few nicer-looking
// modifiers only exist on iOS 16+, so we route them through these helpers
// instead of raising the deployment target.

extension View {
    /// `View.tint(_:)` is iOS 16+; on iOS 15 we fall back to `accentColor(_:)`.
    @ViewBuilder
    func utatarTint(_ color: Color) -> some View {
        if #available(iOS 16.0, *) {
            self.tint(color)
        } else {
            self.accentColor(color)
        }
    }
}
