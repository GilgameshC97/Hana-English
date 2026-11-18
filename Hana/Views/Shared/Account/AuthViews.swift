import SwiftUI

struct LoginRequiredView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    @State private var isCredentialLoginPresented = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 10) {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                }

                Button {
                    isCredentialLoginPresented = true
                } label: {
                    Label("Account Login", systemImage: "key")
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $isCredentialLoginPresented) {
            SiteCredentialLoginSheet()
        }
    }
}

struct SiteCredentialLoginSheet: View {
    @Environment(HanaServices.self) private var services
    @Environment(HanaSiteProfileManager.self) private var siteProfiles
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var alertMessage: HanaAlertMessage?

    var body: some View {
        NavigationStack {
            Form {
                Section("Site Account") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .hanaTextInputAutocapitalizationNever()
                        .hanaEmailKeyboard()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("Account Login")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "key")
                        }
                    }
                    .accessibilityLabel("Log In")
                    .disabled(isSubmitting || !canSubmit)
                }
            }
        }
        .hanaFeedbackAlert($alertMessage)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        alertMessage = nil
        defer { isSubmitting = false }

        do {
            await services.siteSession.syncDefaultWebCookies()
            let user = try await services.repository.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            services.siteSession.syncSharedHTTPCookies()
            await services.applyLoginState(user: user)
            if let profileID = siteProfiles.activeProfile?.id {
                siteProfiles.saveAccountCredential(profileID: profileID, email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                siteProfiles.setLoginMetadata(profileID, state: .loggedIn)
            }
            dismiss()
        } catch {
            if services.siteSession.handle(error) {
                dismiss()
            } else {
                alertMessage = .error(error.localizedDescription)
            }
        }
    }
}
