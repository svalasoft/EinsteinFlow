import Foundation
import SwiftUI

private enum FlowPalette: Int, CaseIterable, Identifiable {
    case aurora, prism, ink

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .prism: return "Prism"
        case .ink: return "Ink"
        }
    }
}

struct EinsteinFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var palette = FlowPalette.aurora
    @State private var controlsVisible = true
    @State private var clock = FlowClock()
    @State private var cutterCount = 1
    @State private var fieldSize = FlowFieldSize.small
    @State private var fieldModel = LaserFieldModel()
    @State private var navigation = CameraNavigation()
    @State private var previousDrag = CGSize.zero
    @State private var dragContext: CameraInputContext?
    @State private var previousMagnification: CGFloat = 1

    private let seafoam = Color(red: 0.51, green: 0.94, blue: 0.83)

    var body: some View {
        GeometryReader { viewport in
            let compact = viewport.size.width < 540 && viewport.size.height > viewport.size.width
            ZStack {
                if !compact {
                    interactiveField.ignoresSafeArea()
                    VStack {
                        LinearGradient(colors: [Color.black.opacity(0.6), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 170)
                        Spacer(minLength: 0)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    header(compact: compact)
                    if compact {
                        interactiveField
                            .clipped()
                    } else {
                        Spacer(minLength: 20)
                    }
                    if controlsVisible {
                        controls(compact: compact)
                            .padding(.horizontal, compact ? 8 : 20)
                            .padding(.bottom, compact ? 2 : 12)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        sourceLink
                    }
                    .padding(.horizontal, compact ? 8 : 20)
                    .padding(.bottom, compact ? 4 : 12)
                }
            }
        }
        .background(Color(red: 0.008, green: 0.022, blue: 0.04))
        .preferredColorScheme(.dark)
        .onAppear {
            clock.setReducedMotion(reduceMotion, at: Date())
            clock.setVisible(true, at: Date())
        }
        .onDisappear { clock.setVisible(false, at: Date()) }
        .onChange(of: reduceMotion) { value in clock.setReducedMotion(value, at: Date()) }
        .onChange(of: scenePhase) { phase in
            // Use the callback's new phase. Reading the enclosing view's old
            // environment here can leave the clock paused after activation.
            clock.setVisible(phase == .active, at: Date())
        }
    }

    private var interactiveField: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clock.running)) { context in
                LaserFieldView(size: geometry.size, time: clock.elapsed(at: context.date),
                               palette: palette.rawValue, reducedMotion: reduceMotion,
                               cutterCount: cutterCount, fieldSize: fieldSize,
                               rotation: clock.rotationAngle(at: context.date),
                               navigation: navigation, model: fieldModel)
            }
            .overlay(WheelZoomInput(onZoom: { factor in navigation.magnify(by: factor) }))
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
        }
        .accessibilityHidden(true)
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: compact ? .center : .top, spacing: compact ? 6 : 16) {
            if controlsVisible {
                VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                    Link("EINSTEIN FLOW", destination: URL(string: "https://www.scientificamerican.com/article/newfound-mathematical-einstein-shape-creates-a-never-repeating-pattern/")!)
                        .font(.system(size: compact ? 12 : 13, weight: .bold, design: .monospaced))
                        .tracking(compact ? 2 : 3)
                        .foregroundStyle(seafoam)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("articleLink")
                    Text("Geometry, forged in light.")
                        .font(.system(size: compact ? 15 : 23, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
            Button {
                navigation.reset()
                previousDrag = .zero
                previousMagnification = 1
                dragContext = nil
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: compact ? 44 : 38, height: compact ? 44 : 38)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Center camera")
            .accessibilityIdentifier("centerCamera")
            let visibilityTitle = controlsVisible ? "Hide controls" : "Show controls"
            Button {
                controlsVisible.toggle()
            } label: {
                Text(compact ? (controlsVisible ? "Hide" : "Show") : visibilityTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 0 : 11)
                    .frame(minHeight: compact ? 44 : nil)
                    .background(Color.black.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(visibilityTitle))
            .accessibilityIdentifier("controlsVisibility")
        }
        .padding(.horizontal, compact ? 12 : 24)
        .padding(.top, compact ? 4 : 20)
        .padding(.bottom, compact ? 4 : 0)
    }

    private var sourceLink: some View {
        Link("github.com/svalasoft/EinsteinFlow", destination: URL(string: "https://github.com/svalasoft/EinsteinFlow")!)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.5), in: Capsule())
            .accessibilityIdentifier("sourceLink")
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in pan(to: value.translation) }
            .onEnded { value in
                pan(to: value.translation)
                previousDrag = .zero
                dragContext = nil
            }
    }

    private func pan(to translation: CGSize) {
        if dragContext == nil { dragContext = fieldModel.cameraInputContext }
        guard let context = dragContext else { return }
        let delta = CGSize(width: translation.width - previousDrag.width,
                           height: translation.height - previousDrag.height)
        navigation.pan(screenDelta: delta, viewport: context.viewport,
                       automaticSpan: context.automaticSpan, angle: context.angle)
        previousDrag = translation
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                guard value.isFinite, value > 0 else { return }
                navigation.magnify(by: Double(value / previousMagnification))
                previousMagnification = value
            }
            .onEnded { value in
                if value.isFinite, value > 0 {
                    navigation.magnify(by: Double(value / previousMagnification))
                }
                previousMagnification = 1
            }
    }

    private func controls(compact: Bool) -> some View {
        VStack(spacing: compact ? 0 : 12) {
            HStack(spacing: compact ? 4 : 12) {
                Menu {
                    ForEach(1...8, id: \.self) { count in
                        Button(count == 1 ? "1 laser" : "\(count) lasers") { cutterCount = count }
                    }
                } label: {
                    controlLabel("Lasers", value: "\(cutterCount)", compact: compact)
                }
                .accessibilityIdentifier("cutterCount")

                if compact {
                    speedMenu(compact: true)
                } else {
                    HStack(spacing: 2) {
                        rotationButton("arrow.left", step: -1, compact: false)
                        speedMenu(compact: false)
                        rotationButton("arrow.right", step: 1, compact: false)
                    }
                    .frame(maxWidth: .infinity)
                }

                Menu {
                    ForEach(FlowFieldSize.allCases) { size in
                        Button(size.title) { fieldSize = size }
                    }
                } label: {
                    controlLabel("Field", value: "\(fieldSize.rawValue)", compact: compact)
                }
                .accessibilityIdentifier("fieldSize")
            }
            .buttonStyle(.plain)

            HStack(spacing: compact ? 4 : 8) {
                ForEach(FlowPalette.allCases) { option in
                    Button { palette = option } label: {
                        Text(option.title)
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(palette == option ? Color.black : Color.white.opacity(0.8))
                            .padding(.vertical, compact ? 0 : 11)
                            .frame(maxWidth: .infinity, minHeight: compact ? 44 : nil)
                            .background(palette == option ? seafoam : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(palette == option ? [.isSelected] : [])
                    .accessibilityIdentifier("palette-\(option.title)")
                }

                Button { clock.togglePaused(at: Date()) } label: {
                    Text(clock.paused ? "Play" : "Pause")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, compact ? 12 : 17)
                        .padding(.vertical, compact ? 0 : 11)
                        .frame(minHeight: compact ? 44 : nil)
                        .background(Color.white.opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pauseAnimation")
            }
            HStack(spacing: compact ? 6 : 0) {
                if compact { rotationButton("arrow.left", step: -1, compact: true) }
                Text(reduceMotion ? "A still moment · Reduce Motion is enabled" : rotationTitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                if compact { rotationButton("arrow.right", step: 1, compact: true) }
            }
        }
        .padding(compact ? 4 : 14)
        .frame(maxWidth: 540)
        .background(Color(red: 0.025, green: 0.055, blue: 0.085).opacity(0.92),
                    in: RoundedRectangle(cornerRadius: compact ? 16 : 24))
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 24).stroke(seafoam.opacity(0.2), lineWidth: 1))
    }

    private func speedMenu(compact: Bool) -> some View {
        Menu {
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { speed in
                Button(speedTitle(speed)) { clock.setSpeed(speed, at: Date()) }
            }
        } label: {
            controlLabel("Speed", value: speedTitle(clock.speed), compact: compact)
        }
        .accessibilityIdentifier("animationSpeed")
    }

    private func speedTitle(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed)×"
    }

    private var rotationTitle: String {
        if clock.rotationStep == 0 { return "Rotation stopped" }
        return "Rotation: \(abs(clock.rotationStep))× \(clock.rotationStep > 0 ? "clockwise" : "counterclockwise")"
    }

    private func rotationButton(_ symbol: String, step: Int, compact: Bool) -> some View {
        Button { clock.stepRotation(by: step, at: Date()) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(seafoam)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.07), in: Circle())
                .frame(width: compact ? 44 : 24, height: compact ? 44 : 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(step < 0 ? clock.rotationStep == -4 : clock.rotationStep == 4)
        .accessibilityLabel(step < 0 ? "Step rotation counterclockwise" : "Step rotation clockwise")
        .accessibilityIdentifier(step < 0 ? "rotationDecrease" : "rotationIncrease")
    }

    private func controlLabel(_ title: String, value: String, compact: Bool) -> some View {
        HStack(spacing: compact ? 3 : 5) {
            Text(title).foregroundStyle(.white.opacity(0.65))
            Text(value).foregroundStyle(seafoam)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: compact ? 44 : nil)
        .padding(.vertical, compact ? 0 : 6)
    }

}
