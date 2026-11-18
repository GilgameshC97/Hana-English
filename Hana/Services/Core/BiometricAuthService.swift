import Foundation
import Combine
import LocalAuthentication
import SwiftUI

@MainActor
final class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()

    @Published var isUnlocked: Bool = false
    @Published var biometryType: LABiometryType = .none

    init() {
        checkBiometryType()
    }

    func checkBiometryType() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            self.biometryType = context.biometryType
        } else {
            self.biometryType = .none
        }
    }

    var biometryName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Passcode"
        }
    }

    var systemImageName: String {
        switch biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.fill"
        }
    }

    func authenticate(reason: String = "Unlock Hana", completion: ((Bool) -> Void)? = nil) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.isUnlocked = true
                    }
                    completion?(success)
                }
            }
        } else {
            // Biometrics not available on device (e.g. simulator) - allow access
            self.isUnlocked = true
            completion?(true)
        }
    }

    func lock() {
        self.isUnlocked = false
    }
}

struct BiometricLockOverlayView: View {
    @ObservedObject var authService = BiometricAuthService.shared
    let onUnlockRequest: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: authService.systemImageName)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: authService.isUnlocked)

                VStack(spacing: 8) {
                    Text("Hana is Locked")
                        .font(.title2.bold())

                    Text("Authenticate with \(authService.biometryName) to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    onUnlockRequest()
                } label: {
                    Label("Unlock with \(authService.biometryName)", systemImage: authService.systemImageName)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
        }
        .onAppear {
            onUnlockRequest()
        }
    }
}
