import SwiftUI

/// Values exported from the approved Paper confirmation design.
enum OnboardingStyle {
    static let secondary = Color(red: 165 / 255, green: 165 / 255, blue: 173 / 255)
    static let success = Color(red: 155 / 255, green: 198 / 255, blue: 170 / 255)
    static let surface = Color(red: 40 / 255, green: 40 / 255, blue: 43 / 255)
    static let divider = Color(red: 56 / 255, green: 56 / 255, blue: 59 / 255)
    static let label = Font.custom("Geist-Regular", fixedSize: 12)
    static let evidence = Font.custom("GeistMono-Regular", fixedSize: 12)
}

struct OnboardingSummary: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(detail).monospacedDigit()
        }
        .font(OnboardingStyle.label)
        .foregroundStyle(OnboardingStyle.secondary)
        .padding(12)
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingConfirmation: View {
    let state: OnboardingRowState
    var monospaced = false
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if case .action(_, let button) = state {
                    Button(button, action: action)
                        .buttonStyle(PillButtonStyle())
                        .accessibilityLabel("\(button) — \(state.label)")
                } else {
                    Text(state.label)
                        .font(monospaced && state.isSuccess ? OnboardingStyle.evidence : OnboardingStyle.label)
                        .foregroundStyle(OnboardingStyle.secondary)
                }
            }
            .frame(width: 92, alignment: .trailing)
            OnboardingStatusMark(state: state)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// Only this 20pt slot animates. The label, row height and metadata lane remain
/// fixed; already-confirmed values don't replay when navigating back.
struct OnboardingStatusMark: View {
    let state: OnboardingRowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            if state.isLoading {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                    let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.85) / 0.85
                    ZStack {
                        Circle().stroke(OnboardingStyle.secondary.opacity(0.35), lineWidth: 1.35)
                        Circle().trim(from: 0, to: 0.25)
                            .stroke(OnboardingStyle.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(reduceMotion ? -90 : turns * 360))
                    }
                    .frame(width: 14, height: 14)
                }
                .transition(.opacity)
            } else if state.isSuccess {
                ZStack {
                    Circle().stroke(OnboardingStyle.success, lineWidth: 1.35)
                    ConfirmationCheck().trim(from: 0, to: revealed ? 1 : 0)
                        .stroke(OnboardingStyle.success, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 14, height: 14)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.9)
                .transition(.opacity)
            } else {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(OnboardingStyle.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: state.isLoading)
        .onAppear { revealed = state.isSuccess }
        .onChange(of: state.isSuccess) { _, success in
            if success {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { revealed = true }
            } else {
                revealed = false
            }
        }
        .onChange(of: reduceMotion) { _, _ in revealed = state.isSuccess }
        .accessibilityLabel(state.isLoading ? state.label : state.isSuccess ? "Confirmed" : state.label)
    }
}

private struct ConfirmationCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.257, y: rect.height * 0.5))
        path.addLine(to: CGPoint(x: rect.width * 0.421, y: rect.height * 0.664))
        path.addLine(to: CGPoint(x: rect.width * 0.743, y: rect.height * 0.336))
        return path
    }
}
