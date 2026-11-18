import SwiftUI

struct ProfileDetailScreen: View {
    @Environment(HanaServices.self) private var services
    @Environment(HanaSiteProfileManager.self) private var siteProfiles
    @State private var isCredentialLoginPresented = false

    var body: some View {
        content
            .navigationTitle("Profile")
            .sheet(isPresented: $isCredentialLoginPresented) {
                SiteCredentialLoginSheet()
            }
            .onChange(of: services.siteSession.lastCookieSyncAt) { _, newValue in
                if let newValue, let profileID = siteProfiles.activeProfile?.id {
                    siteProfiles.setLoginMetadata(profileID, state: services.siteSession.isLoggedIn ? .loggedIn : .syncing, lastSync: newValue)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        macOSContent
#else
        mobileContent
#endif
    }

    private var mobileContent: some View {
        List {
            Section {
                profileHeader
            }

            siteSection

            accountSection
        }
    }

#if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeader

                Divider()

                Form {
                    siteSection

                    accountSection
                }
                .formStyle(.grouped)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollContentBackground(.visible)
    }
#endif

    private var profileHeader: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(url: avatarURL)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(accountStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var siteSection: some View {
        Section("Site") {
            ProfileMetadataLine(
                systemImage: "link",
                text: services.siteSession.baseURL.absoluteString
            )
            if let userID = services.siteSession.userID, services.siteSession.isLoggedIn {
                ProfileMetadataLine(
                    systemImage: "person.text.rectangle",
                    text: userID
                )
            }
            if let date = services.siteSession.lastCookieSyncAt {
                LabeledContent("Cookie Sync", value: date.hanaChineseDateTimeText)
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if services.siteSession.isLoggedIn {
                Button(role: .destructive) {
                    Task {
                        await services.logout()
                        if let profileID = siteProfiles.activeProfile?.id {
                            siteProfiles.clearAccountCredential(profileID: profileID)
                            siteProfiles.setLoginMetadata(profileID, state: .loggedOut)
                        }
                    }
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    services.siteSession.requestLogin()
                } label: {
                    Label("Log In", systemImage: "person.crop.circle")
                }

                Button {
                    isCredentialLoginPresented = true
                } label: {
                    Label("Account Login", systemImage: "key")
                }
            }
        }
    }

    private var displayName: String {
        services.siteSession.isLoggedIn ? services.siteSession.displayName : "Not Logged In"
    }

    private var accountStatusText: String {
        if services.siteSession.isLoggedIn {
            return services.siteSession.userID == nil ? "Syncing account..." : "Logged In"
        }
        return "Log in to sync subscriptions & favorites"
    }

    private var avatarURL: URL? {
        services.siteSession.avatarURLString.flatMap(URL.init(string:))
    }
}
