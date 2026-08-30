import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    nonisolated static let emptyPasswordMessage = String(localized: "Enter the server password.")

    var serverURLString = ""
    var password = ""
    var customHeaders: [CustomHeader] = []
    private(set) var authStatus: AuthStatusResponse?
    var errorMessage: String?
    var isWorking = false

    // A probed status describes one specific (URL, headers) pair. Keeping it after
    // the user edits either would let `isPasswordRequired` hide the password field
    // using another server's trusted-header state, and would let `connect()` skip
    // the re-probe the new server needs (#285).
    private var probedServerURLString: String?
    private var probedCustomHeaders: [CustomHeader]?
    private var probedConnectionMessage: String?

    private var isProbeCurrent: Bool {
        authStatus != nil
            && probedServerURLString == serverURLString
            && probedCustomHeaders == customHeaders
    }

    /// `authStatus`, but only while it still describes what is in the form.
    /// Everything deciding whether a password is required must read this, never
    /// the raw cache.
    var currentAuthStatus: AuthStatusResponse? {
        isProbeCurrent ? authStatus : nil
    }

    /// Suppressed once the probe goes stale — a lingering "Connection ok" next to
    /// an edited URL asserts something we no longer know.
    var connectionMessage: String? {
        isProbeCurrent ? probedConnectionMessage : nil
    }

    /// Records a freshly probed status together with the inputs it was probed
    /// against, so a later edit invalidates it.
    func applyProbedAuthStatus(_ status: AuthStatusResponse?) {
        authStatus = status
        probedServerURLString = status == nil ? nil : serverURLString
        probedCustomHeaders = status == nil ? nil : customHeaders
        if status == nil { probedConnectionMessage = nil }
    }

    init(
        savedServer: URL? = nil,
        savedHeaders: [CustomHeader] = [],
        initialErrorMessage: String? = nil
    ) {
        if let savedServer {
            serverURLString = savedServer.absoluteString
        }
        customHeaders = savedHeaders
        errorMessage = initialErrorMessage
    }

    var isPasswordRequired: Bool {
        // No auth → no password. Already signed in (trusted-header proxy) → no
        // password either. Passkey/OIDC-only → hide the field; connect()
        // surfaces the specific unsupported message instead. Unknown (nil)
        // keeps today's "show the field" default.
        let status = currentAuthStatus
        guard status?.authEnabled != false else { return false }
        guard status?.isAlreadySignedIn != true else { return false }
        return status?.passwordAuthEnabled != false
    }

    func testConnection(authManager: AuthManager) async {
        errorMessage = nil
        probedConnectionMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let status = try await authManager.testConnection(
                serverURLString: serverURLString,
                customHeaders: customHeaders
            )
            applyProbedAuthStatus(status)
            if let message = AuthManager.unsupportedSignInMessage(for: status) {
                errorMessage = message
            } else if status.isAlreadySignedIn {
                probedConnectionMessage = String(localized: "Connection ok. Already signed in by this server.")
            } else {
                probedConnectionMessage = status.authEnabled == true
                    ? String(localized: "Connection ok. Password required.")
                    : String(localized: "Connection ok. Password not required.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connect(authManager: AuthManager) async {
        errorMessage = nil
        probedConnectionMessage = nil

        if let validationMessage = Self.passwordValidationMessage(authStatus: currentAuthStatus, password: password) {
            errorMessage = validationMessage
            return
        }

        isWorking = true
        defer { isWorking = false }

        if currentAuthStatus == nil {
            do {
                applyProbedAuthStatus(try await authManager.testConnection(
                    serverURLString: serverURLString,
                    customHeaders: customHeaders
                ))
            } catch {
                errorMessage = error.localizedDescription
                return
            }

            if let validationMessage = Self.passwordValidationMessage(authStatus: currentAuthStatus, password: password) {
                errorMessage = validationMessage
                return
            }
        }

        await authManager.configure(
            serverURLString: serverURLString,
            password: password,
            customHeaders: customHeaders
        )
        errorMessage = authManager.lastErrorMessage
    }

    nonisolated static func passwordValidationMessage(authStatus: AuthStatusResponse?, password: String) -> String? {
        guard authStatus?.authEnabled == true else { return nil }
        // A server that already signed this client in (trusted-header proxy)
        // has no password to demand (#3).
        guard authStatus?.isAlreadySignedIn != true else { return nil }
        // Passkey/OIDC-only servers don't take a password either — let
        // configure() report the specific unsupported message instead of
        // demanding one here (#255, #3).
        guard authStatus?.passwordAuthEnabled != false else { return nil }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPassword.isEmpty ? emptyPasswordMessage : nil
    }
}
