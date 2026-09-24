import SwiftUI

/// Port-colored dots; a glow marks attention and an outline marks idle.
struct ColonStatus: View {
    let status: ServerStatus
    let color: Color
    var dot: CGFloat = 4
    var gap: CGFloat = 3

    var body: some View {
        VStack(spacing: gap) {
            dotView
            dotView
        }
    }

    @ViewBuilder private var dotView: some View {
        switch status {
        case .running:
            Circle().fill(color).frame(width: dot, height: dot)
        case .attention:
            Circle().fill(color).frame(width: dot, height: dot)
                .shadow(color: color.opacity(0.7), radius: 2.5)
        case .idle:
            Circle().strokeBorder(color, lineWidth: 1.1).frame(width: dot, height: dot)
        }
    }
}

struct PortLabel: View {
    let port: Int
    let status: ServerStatus
    let color: Color
    var large = false

    var body: some View {
        HStack(spacing: large ? 6 : 5) {
            ColonStatus(status: status, color: color, dot: large ? 6 : 4, gap: large ? 6 : 3)
            Text(String(port))
                .font(large ? Theme.display : Theme.monoMedium)
                .foregroundStyle(Theme.text1)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.text1.opacity(0.7)
    var lineWidth: CGFloat = 1.25

    var body: some View {
        GeometryReader { geometry in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let range = max(high - low, high * 0.05, 1)
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geometry.size.height * (1 - CGFloat((value - low) / range)) * 0.8 + geometry.size.height * 0.1
                        index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.66))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.66))
                }
                .stroke(Theme.text2, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [2, 3]))
            }
        }
    }
}

/// Header row shared by every popover page: optional back button, centred title.
struct PageHeader: View {
    let title: String
    var back: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.bodyMedium)
                .foregroundStyle(Theme.text1)
                .lineLimit(1)
                .help(title)
                .padding(.horizontal, 28)
            if let back {
                HStack {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
                .padding(.leading, -4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
    }
}

struct SectionDivider: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 0.5)
    }
}

struct IconButton: View {
    let systemName: String
    var tint: Color = Theme.text1
    var background: Color = Theme.fill
    var size: CGFloat = 26
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .primary || kind == .destructive ? Theme.bodyMedium : Theme.body)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(background.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.ink
        case .secondary: return Theme.text1
        case .destructive: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.text1
        case .secondary: return Theme.fill
        case .destructive: return Theme.red
        }
    }
}

/// Small monochrome marks for the agent that started a server.
struct AgentGlyph: View {
    let kind: AgentKind
    var size: CGFloat = 12
    var color: Color = Theme.text1.opacity(0.75)

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 12
            switch kind {
            case .claudeCode:
                var path = Path()
                path.move(to: CGPoint(x: 6 * s, y: 1 * s)); path.addLine(to: CGPoint(x: 6 * s, y: 11 * s))
                path.move(to: CGPoint(x: 1 * s, y: 6 * s)); path.addLine(to: CGPoint(x: 11 * s, y: 6 * s))
                path.move(to: CGPoint(x: 2.5 * s, y: 2.5 * s)); path.addLine(to: CGPoint(x: 9.5 * s, y: 9.5 * s))
                path.move(to: CGPoint(x: 9.5 * s, y: 2.5 * s)); path.addLine(to: CGPoint(x: 2.5 * s, y: 9.5 * s))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
            case .codex:
                let box = Path(roundedRect: CGRect(x: 1 * s, y: 1.5 * s, width: 10 * s, height: 9 * s), cornerRadius: 2.5 * s)
                context.stroke(box, with: .color(color), lineWidth: 1.2 * s)
                var prompt = Path()
                prompt.move(to: CGPoint(x: 3.5 * s, y: 5 * s))
                prompt.addLine(to: CGPoint(x: 5 * s, y: 6.2 * s))
                prompt.addLine(to: CGPoint(x: 3.5 * s, y: 7.4 * s))
                prompt.move(to: CGPoint(x: 6.2 * s, y: 7.6 * s)); prompt.addLine(to: CGPoint(x: 8.5 * s, y: 7.6 * s))
                context.stroke(prompt, with: .color(color), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

struct Disclosure: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(Theme.caption).foregroundStyle(Theme.text3)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Row hover highlight used across lists.
    func hoverHighlight(_ isHovered: Bool) -> some View {
        background(isHovered ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
