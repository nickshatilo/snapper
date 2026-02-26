import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var screenCaptureGranted = false
    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private let steps = [
        "Welcome",
        "Screen Recording",
        "Accessibility",
        "System Shortcuts",
        "Ready",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: screenRecordingStep
                case 2: accessibilityStep
                case 3: systemShortcutsStep
                default: readyStep
                }
            }
            .frame(maxWidth: .infinity)
            .padding(32)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") { currentStep -= 1 }
                }
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Continue") { currentStep += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { finishOnboarding() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 500, height: 400)
        .onReceive(pollTimer) { _ in
            accessibilityGranted = PermissionChecker.isAccessibilityGranted()
            screenCaptureGranted = PermissionChecker.isScreenCaptureGranted()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Snapper")
                .font(.title)
                .fontWeight(.bold)
            Text("A powerful, open source screenshot tool for macOS.\nLet's set up a few things to get you started.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var screenRecordingStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 48))
                .foregroundStyle(screenCaptureGranted ? .green : .orange)
            Text("Screen Recording Permission")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Snapper needs screen recording access to capture screenshots.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if screenCaptureGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Permission") {
                    let granted = PermissionChecker.requestScreenCapture()
                    if !granted {
                        PermissionChecker.openScreenRecordingSettings()
                    }
                }
                .buttonStyle(.bordered)

                Text("If you just enabled it, quit and reopen Snapper.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(accessibilityGranted ? .green : .orange)
            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Required for global keyboard shortcuts to work.\nSnapper will intercept Cmd+Shift+3/4/5.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if accessibilityGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings") {
                    let granted = PermissionChecker.requestAccessibility()
                    if !granted {
                        PermissionChecker.openAccessibilitySettings()
                    }
                }
                .buttonStyle(.bordered)

                Text("Return to Snapper after enabling it to activate hotkeys.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var systemShortcutsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Disable System Screenshots")
                .font(.title2)
                .fontWeight(.semibold)
            Text("For the best experience, disable macOS built-in screenshot shortcuts in System Settings > Keyboard > Shortcuts > Screenshots.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open Keyboard Settings") {
                PermissionChecker.openKeyboardShortcutSettings()
            }
            .buttonStyle(.bordered)

            Text("You can skip this — Snapper will intercept the shortcuts either way.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
            Text("Snapper is ready. Use these shortcuts to capture:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("⌘⇧3", "Capture Fullscreen")
                shortcutRow("⌘⇧4", "Capture Area")
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }

    private func finishOnboarding() {
        appState.isFirstRun = false
        NSApp.keyWindow?.close()
    }
}
