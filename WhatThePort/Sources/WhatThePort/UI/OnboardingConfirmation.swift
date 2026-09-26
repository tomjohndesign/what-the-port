import FlickerDot
import SwiftUI

/// Preserve the approved Paper palette in dark mode and adapt it for light mode.
enum OnboardingStyle {
    static let secondary = Theme.adaptive(light: 0x64646C, dark: 0xA5A5AD)
    static let success = Theme.adaptive(light: 0x37704A, dark: 0x9BC6AA)
    static let surface = Theme.adaptive(light: 0xEBEBED, dark: 0x28282B)
    static let divider = Theme.adaptive(light: 0xD4D4D7, dark: 0x38383B)
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
    /// How many frames of the checkmark are drawn.
    @State private var drawn = 0

    var body: some View {
        ZStack {
            if state.isLoading {
                DotSpinner(color: OnboardingStyle.secondary)
                    .transition(.opacity)
            } else if state.isSuccess {
                // Same unlit dots as the loader, so only the lit dots change.
                DotSpinner(frames: [DotGlyph.checkStrokes[max(drawn, 1) - 1]], color: OnboardingStyle.success,
                           unlitColor: OnboardingStyle.secondary.opacity(0.12))
                    .transition(.opacity)
            } else {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(OnboardingStyle.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: state.isLoading)
        .onAppear { drawn = state.isSuccess ? DotGlyph.checkStrokes.count : 0 }
        .onChange(of: state.isSuccess) { _, success in
            drawn = success ? (reduceMotion ? DotGlyph.checkStrokes.count : 1) : 0
        }
        .onChange(of: reduceMotion) { _, _ in drawn = state.isSuccess ? DotGlyph.checkStrokes.count : 0 }
        // Draw the next dot every half Flicker frame until the mark is complete.
        .task(id: drawn) {
            guard (1..<DotGlyph.checkStrokes.count).contains(drawn) else { return }
            try? await Task.sleep(for: .seconds(Flicker.frameInterval / 2))
            if !Task.isCancelled { drawn += 1 }
        }
        .accessibilityLabel(state.isLoading ? state.label : state.isSuccess ? "Confirmed" : state.label)
    }
}
