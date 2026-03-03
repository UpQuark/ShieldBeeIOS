//
//  DeepBreathOverlay.swift
//  ShieldBug
//
//  Full-screen countdown gate shown when the app comes to foreground.
//  Cannot be dismissed — onComplete fires once the timer reaches zero.
//

import SwiftUI

struct DeepBreathOverlay: View {
    let duration: Int
    let onComplete: () -> Void

    @State private var remaining: Int
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(duration: Int, onComplete: @escaping () -> Void) {
        self.duration = duration
        self.onComplete = onComplete
        _remaining = State(initialValue: duration)
    }

    private var progress: CGFloat {
        CGFloat(duration - remaining) / CGFloat(max(duration, 1))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.93)
                .ignoresSafeArea()

            VStack(spacing: 44) {
                VStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.sbOrange)
                    Text("Take a breath")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Pause before making changes")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.sbOrange,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    VStack(spacing: 2) {
                        Text("\(remaining)")
                            .font(.system(size: 64, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                        Text("sec")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 210, height: 210)
            }
            .padding(40)
        }
        .onReceive(ticker) { _ in
            guard remaining > 0 else { return }
            withAnimation { remaining -= 1 }
            if remaining == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onComplete() }
            }
        }
    }
}
