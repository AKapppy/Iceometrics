import SwiftUI
import AuthenticationServices
import Security
import WidgetKit

// The signed-in Apple user identifier is stored only in Keychain.
// The credential is revalidated on each launch before the app unlocks.
// This is native Sign in with Apple; it is not a server-side login.
@MainActor
final class AppleAccountSession: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var isChecking = true
    @Published var errorMessage: String?

    private let provider = ASAuthorizationAppleIDProvider()
    private let service = "com.akappy.Iceometrics.apple-account"
    private let account = "authorized-user"
    private var revocationObserver: NSObjectProtocol?

    init() {
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.verifySavedCredential() }
        }
        verifySavedCredential()
    }

    func verifySavedCredential() {
        guard let savedID = readSavedUserID() else {
            userID = nil
            updateWidgetAccess(false)
            isChecking = false
            return
        }
        isChecking = true
        provider.getCredentialState(forUserID: savedID) { [weak self] state, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isChecking = false
                switch state {
                case .authorized:
                    self.errorMessage = nil
                    self.userID = savedID
                    self.updateWidgetAccess(true)
                case .revoked, .notFound:
                    self.deleteSavedUserID()
                    self.userID = nil
                    self.updateWidgetAccess(false)
                    self.errorMessage = "Your Apple authorization needs to be renewed."
                default:
                    // Fail closed: an unknown/unverified credential may not
                    // unlock an account. The user can sign in explicitly.
                    self.userID = nil
                    self.updateWidgetAccess(false)
                    if error != nil {
                        self.errorMessage = "Could not verify the saved Apple sign-in. Sign in again."
                    }
                }
            }
        }
    }

    func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  !credential.user.isEmpty else {
                errorMessage = "Apple did not provide an account identifier."
                return
            }
            guard saveUserID(credential.user) else {
                errorMessage = "The Mac or iPhone Keychain could not save this session."
                return
            }
            errorMessage = nil
            isChecking = false
            userID = credential.user
            updateWidgetAccess(true)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Apple sign-in was unsuccessful. Please try again."
        }
    }

    func signOut() {
        // Apple doesn't expose a global provider logout. This removes
        // Iceometrics' own remembered session, and locks every app tab.
        deleteSavedUserID()
        userID = nil
        updateWidgetAccess(false)
        errorMessage = nil
        isChecking = false
    }

    private func updateWidgetAccess(_ authorized: Bool) {
        UserDefaults(suiteName: "group.com.akappy.Iceometrics")?
            .set(authorized, forKey: "iceometrics.account.authorized")
        if !authorized,
           let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.akappy.Iceometrics"
           ) {
            try? FileManager.default.removeItem(
                at: container.appendingPathComponent("widget-snapshot.json")
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func readSavedUserID() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeAll()
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveUserID(_ id: String) -> Bool {
        guard let data = id.data(using: .utf8) else { return false }
        deleteSavedUserID()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private func deleteSavedUserID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    deinit {
        if let revocationObserver {
            NotificationCenter.default.removeObserver(revocationObserver)
        }
    }
}

struct IceometricsLoginView: View {
    @ObservedObject var session: AppleAccountSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hockey.puck.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Iceometrics")
                .font(.largeTitle.bold())
            Text("Sign in to view hockey data and save your personal settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SignInWithAppleButton(.signIn, onRequest: { request in
                // No name or email scopes: settings need only Apple's
                // stable per-app user identifier.
                request.requestedScopes = []
            }, onCompletion: { result in
                Task { @MainActor in session.complete(result) }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .accessibilityLabel("Sign in with Apple")

            if let error = session.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Text("Your preferences stay separate for each Apple sign-in. Sync across devices also requires the same iCloud account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
