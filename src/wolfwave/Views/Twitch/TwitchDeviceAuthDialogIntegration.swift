import SwiftUI
import Combine

/// Integration guide and example for TwitchDeviceAuthDialog
/// 
/// This file is documentation-only. The actual implementations are:
/// - DeviceCodeView: Displays the device code and verification link
/// - TwitchDeviceAuthDialog: Full dialog for reauthorization
/// - TwitchSettingsView: Integration point in the settings UI
///
/// To implement device auth integration:
/// 1. Use TwitchDeviceAuthDialog for a modal presentation
/// 2. Use DeviceCodeView for inline display in your view hierarchy
/// 3. Connect to TwitchViewModel for state management
///
/// Example:
/// ```swift
/// // In your view:
/// if case .waitingForAuth(let userCode, let verificationURI) = viewModel.authState {
///     DeviceCodeView(
///         userCode: userCode,
///         verificationURI: verificationURI,
///         onCopy: { /* handle copy */ }
///     )
/// }
/// ```

