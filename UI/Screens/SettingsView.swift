// SettingsView.swift
// File: SettingsView.swift
// Description: Placeholder Settings screen. Eventually manages presets (3-tier), sync settings,
// and app behaviors. Styled with Theme defaults.
//
// Section 1. Imports
import SwiftUI

// Section 2. View
struct SettingsView: View {

    // Section 2.1 Types
    enum Preset: String, CaseIterable, Identifiable {
        case fast = "Fast"
        case balanced = "Balanced"
        case quality = "Quality"
        var id: String { rawValue }
    }

    // Section 2.2 State
    @State private var selectedPreset: Preset = .balanced

    // Section 2.3 Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Section 2.3.1 Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Settings")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Placeholder screen. Presets + sync settings will live here.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.3.2 Preset
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Scan Preset")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPreset) { _, newValue in
                        if ScannerDebug.isEnabled { ScannerDebug.writeLog("SettingsView: preset changed to \(newValue.rawValue)") }
                    }

                    Text("Planned: 3-tier presets (Fast / Balanced / Quality).")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.3.3 Cloud Sync
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Cloud Sync")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Label("Sync scans + settings (planned)", systemImage: "icloud")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(Theme.Spacing.lg)
        }
        .scannerScreen()
        .navigationTitle("Settings")
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("SettingsView appeared") }
        }
    }
}

// Section 3. Preview
#Preview {
    NavigationStack { SettingsView() }
}

// End of file: SettingsView.swift
