//
//  PINEntryView.swift
//  ShieldBug
//
//  4-digit PIN gate with an internal state machine:
//    .verify      → check against Keychain
//    .setNew      → enter a new PIN
//    .confirmNew  → re-enter to confirm, then save
//
//  "Forgot PIN?" resets the Keychain entry and forces a new PIN to be set immediately.
//

import SwiftUI
import LocalAuthentication

struct PINEntryView: View {

    enum Mode {
        case gate    // app foreground lock — verify (or set if none exists)
        case setup   // settings "Set PIN" — go straight to setNew
        case change  // settings "Change PIN" — verify current, then setNew
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

    @State private var phase: Phase
    @State private var entered = ""
    @State private var errorMessage: String? = nil
    @State private var showForgotAlert = false

    init(mode: Mode, onComplete: @escaping () -> Void) {
        self.mode = mode
        self.onComplete = onComplete
        switch mode {
        case .gate:   _phase = State(initialValue: KeychainManager.hasPin ? .verify : .setNew)
        case .setup:  _phase = State(initialValue: .setNew)
        case .change: _phase = State(initialValue: .verify)
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

                // 4 dot indicators
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? Color.sbOrange : Color.white.opacity(0.22))
                            .frame(width: 14, height: 14)
                            .animation(.spring(response: 0.2), value: entered.count)
                    }
                }
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
                        // Biometric (only on verify)
                        PINButton(systemImage: biometricIcon) { tryBiometric() }
                            .opacity(phase == .verify ? 1 : 0)
                            .disabled(phase != .verify)
                        PINButton(label: "0") { append("0") }
                        PINButton(systemImage: "delete.left") { backspace() }
                    }
                }
                .padding(.bottom, 40)

                // Forgot PIN — deemphasised, gate mode only
                if phase == .verify && mode == .gate {
                    Button("Forgot PIN?") { showForgotAlert = true }
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.28))
                }

                Spacer()
            }
        }
        .alert("Reset PIN?", isPresented: $showForgotAlert) {
            Button("Reset and set new PIN", role: .destructive) {
                KeychainManager.clearPin()
                entered = ""
                errorMessage = nil
                withAnimation { phase = .setNew }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current PIN will be cleared. You must create a new one immediately.")
        }
        .onAppear {
            // Offer biometrics automatically when verifying at the gate
            if phase == .verify && mode == .gate { tryBiometric() }
        }
    }

    // MARK: - Computed

    private var title: String {
        switch phase {
        case .verify:     return mode == .gate ? "Unlock ShieldBug" : "Enter current PIN"
        case .setNew:     return "Set a PIN"
        case .confirmNew: return "Confirm PIN"
        }
    }

    private var subtitle: String {
        switch phase {
        case .verify:     return "Enter your 4-digit PIN"
        case .setNew:     return "Choose a 4-digit PIN"
        case .confirmNew: return "Re-enter your new PIN"
        }
    }

    private var biometricIcon: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "faceid" : "touchid"
    }

    // MARK: - Input

    private func append(_ digit: String) {
        guard entered.count < 4 else { return }
        entered += digit
        errorMessage = nil
        if entered.count == 4 { submit() }
    }

    private func backspace() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        errorMessage = nil
    }

    private func submit() {
        switch phase {
        case .verify:
            if KeychainManager.verifyPin(entered) {
                if mode == .change {
                    entered = ""
                    withAnimation { phase = .setNew }
                } else {
                    onComplete()
                }
            } else {
                entered = ""
                withAnimation { errorMessage = "Incorrect PIN. Try again." }
            }

        case .setNew:
            let first = entered
            entered = ""
            withAnimation { phase = .confirmNew(first: first) }

        case .confirmNew(let first):
            if entered == first {
                KeychainManager.savePin(entered)
                onComplete()
            } else {
                entered = ""
                withAnimation {
                    errorMessage = "PINs don't match. Try again."
                    phase = .setNew
                }
            }
        }
    }

    private func tryBiometric() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Unlock ShieldBug") { success, _ in
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
