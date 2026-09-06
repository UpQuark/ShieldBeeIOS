//
//  PINEntryView.swift
//  ShieldBee
//
//  The app-lock gate. Supports two input styles, chosen by `UserPreferences.lockType`:
//    .pin      → digits only, on the custom numpad below
//    .password → any characters, on the system keyboard in a masked field
//
//  Internal state machine (unlimited length, either style):
//    .verify      → check against Keychain
//    .setNew      → enter a new secret
//    .confirmNew  → re-enter to confirm, then save
//
//  "Forgot?" resets the Keychain entry and forces a new secret to be set immediately.
//

import SwiftUI
import LocalAuthentication

struct PINEntryView: View {

    enum Mode: Equatable {
        case gate                      // app foreground lock — verify (or set if none exists)
        case setup                     // settings "Set PIN" — go straight to setNew
        case change                    // settings "Change PIN" — verify current, then setNew
        case changeType(to: LockType)  // settings type switch — verify current, then set in the new style
    }

    private enum Phase: Equatable {
        case verify
        case setNew
        case confirmNew(first: String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.verify, .verify), (.setNew, .setNew): return true
            case let (.confirmNew(a), .confirmNew(b)):   return a == b
            default: return false
            }
        }
    }

    let mode: Mode
    let onComplete: () -> Void

    @ObservedObject private var store = ShieldBeeStore.shared
    @State private var phase: Phase
    @State private var entered = ""
    @State private var errorMessage: String? = nil
    @State private var showForgotAlert = false
    @FocusState private var passwordFieldFocused: Bool

    init(mode: Mode, onComplete: @escaping () -> Void) {
        self.mode = mode
        self.onComplete = onComplete
        switch mode {
        case .gate, .changeType: _phase = State(initialValue: KeychainManager.hasPin ? .verify : .setNew)
        case .setup:             _phase = State(initialValue: .setNew)
        case .change:            _phase = State(initialValue: .verify)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon + title
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.sbOrange)
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Group {
                        if let error = errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                        } else {
                            Text(subtitle)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .font(.subheadline)
                    .animation(.easeInOut(duration: 0.2), value: errorMessage)
                }
                .padding(.bottom, 44)

                if activeLockType == .pin {
                    pinInput
                } else {
                    passwordInput
                }

                // Forgot — deemphasised, gate mode only
                if phase == .verify && mode == .gate {
                    Button("Forgot \(activeLockType.displayName)?") { showForgotAlert = true }
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.28))
                }

                Spacer()
            }
        }
        .alert("Reset \(activeLockType.displayName)?", isPresented: $showForgotAlert) {
            Button("Reset and set new", role: .destructive) {
                KeychainManager.clearPin()
                entered = ""
                errorMessage = nil
                withAnimation { phase = .setNew }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current \(activeLockType.displayName.lowercased()) will be cleared. You must create a new one immediately.")
        }
        .onAppear {
            // Offer biometrics automatically when verifying at the gate
            if phase == .verify && mode == .gate { tryBiometric() }
            if activeLockType == .password { passwordFieldFocused = true }
        }
        .onChange(of: phase) { _, _ in
            if activeLockType == .password { passwordFieldFocused = true }
        }
    }

    // MARK: - PIN input (numpad)

    private var pinInput: some View {
        VStack(spacing: 0) {
            // Dot indicators — up to 12 shown, then a count
            Group {
                if entered.count <= 12 {
                    HStack(spacing: 10) {
                        ForEach(0..<max(entered.count, 1), id: \.self) { i in
                            Circle()
                                .fill(i < entered.count ? Color.sbOrange : Color.white.opacity(0.22))
                                .frame(width: 12, height: 12)
                                .animation(.spring(response: 0.2), value: entered.count)
                        }
                    }
                } else {
                    Text("\(entered.count) digits entered")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.sbOrange)
                }
            }
            .frame(height: 20)
            .padding(.bottom, 52)

            // Numpad
            VStack(spacing: 18) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(row, id: \.self) { digit in
                            PINButton(label: "\(digit)") { append("\(digit)") }
                        }
                    }
                }
                HStack(spacing: 20) {
                    // Biometric when verify + nothing typed; confirm (✓) otherwise
                    if phase == .verify && entered.isEmpty && biometricAvailable {
                        PINButton(systemImage: biometricIcon) { tryBiometric() }
                    } else {
                        PINButton(systemImage: "checkmark") { submit() }
                            .opacity(entered.isEmpty ? 0.3 : 1)
                            .disabled(entered.isEmpty)
                    }
                    PINButton(label: "0") { append("0") }
                    PINButton(systemImage: "delete.left") { backspace() }
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Password input (system keyboard)

    private var passwordInput: some View {
        VStack(spacing: 20) {
            SecureField("", text: $entered)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($passwordFieldFocused)
                .submitLabel(.go)
                .onSubmit { submit() }
                .onChange(of: entered) { _, _ in errorMessage = nil }
                .font(.title3)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
                .padding(.horizontal, 40)

            HStack(spacing: 16) {
                if phase == .verify && biometricAvailable {
                    Button { tryBiometric() } label: {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }

                Button { submit() } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.sbOrange))
                }
                .buttonStyle(.plain)
                .opacity(entered.isEmpty ? 0.3 : 1)
                .disabled(entered.isEmpty)
            }
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Computed

    /// The lock style in play for the current phase. When switching types we verify with the
    /// old style, then set the new secret in the style being switched to.
    private var activeLockType: LockType {
        if case .changeType(let target) = mode, phase != .verify { return target }
        return store.preferences.lockType
    }

    private var noun: String { activeLockType.displayName }

    private var title: String {
        switch phase {
        case .verify:     return mode == .gate ? "Unlock ShieldBee" : "Enter current \(noun.lowercased())"
        case .setNew:     return "Set a \(noun.lowercased())"
        case .confirmNew: return "Confirm \(noun.lowercased())"
        }
    }

    private var subtitle: String {
        switch phase {
        case .verify:     return "Enter your \(noun.lowercased())"
        case .setNew:     return "Choose a \(noun.lowercased())"
        case .confirmNew: return "Re-enter your new \(noun.lowercased())"
        }
    }

    private var biometricAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private var biometricIcon: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "faceid" : "touchid"
    }

    // MARK: - Input

    private func append(_ digit: String) {
        entered += digit
        errorMessage = nil
    }

    private func backspace() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        errorMessage = nil
    }

    private func submit() {
        guard !entered.isEmpty else { return }

        switch phase {
        case .verify:
            if KeychainManager.verifyPin(entered) {
                if mode == .change || isChangeType {
                    entered = ""
                    withAnimation { phase = .setNew }
                } else {
                    onComplete()
                }
            } else {
                entered = ""
                withAnimation { errorMessage = "Incorrect \(noun.lowercased()). Try again." }
            }

        case .setNew:
            let first = entered
            entered = ""
            withAnimation { phase = .confirmNew(first: first) }

        case .confirmNew(let first):
            if entered == first {
                KeychainManager.savePin(entered)
                commitLockTypeIfNeeded()
                onComplete()
            } else {
                entered = ""
                withAnimation {
                    errorMessage = "\(noun)s don't match. Try again."
                    phase = .setNew
                }
            }
        }
    }

    private var isChangeType: Bool {
        if case .changeType = mode { return true }
        return false
    }

    /// Only persist the new lock type once the new secret is actually saved, so an abandoned
    /// switch leaves the user on their original style with their original secret intact.
    private func commitLockTypeIfNeeded() {
        guard case .changeType(let target) = mode else { return }
        var prefs = store.preferences
        prefs.lockType = target
        store.updatePreferences(prefs)
    }

    private func tryBiometric() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Unlock ShieldBee") { success, _ in
            if success { DispatchQueue.main.async { onComplete() } }
        }
    }
}

// MARK: - PINButton

private struct PINButton: View {
    var label: String?
    var systemImage: String?
    let action: () -> Void

    init(label: String, action: @escaping () -> Void) {
        self.label = label; self.action = action
    }
    init(systemImage: String, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 78, height: 78)
                if let label = label {
                    Text(label)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                } else if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
