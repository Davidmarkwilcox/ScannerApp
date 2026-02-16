// SettingsView.swift
// File: SettingsView.swift
// Description:
// Settings screen (placeholder) for ScannerApp.
// - Persists the selected Scan Preset via AppStorage so ScanView/ScannerKit can consume it.
// - Uses Theme styles and ScannerDebug logging.
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

    // Section 2.2 Persisted State
    // Key shared with ScanView. Stored as the Preset rawValue ("Fast" / "Balanced" / "Quality").
    @AppStorage("scanner.scanPreset") private var selectedPresetRaw: String = Preset.balanced.rawValue

    // Section 2.3 Derived Binding
    private var selectedPreset: Binding<Preset> {
        Binding<Preset>(
            get: { Preset(rawValue: selectedPresetRaw) ?? .balanced },
            set: { selectedPresetRaw = $0.rawValue }
        )
    }

    // Section 2.4 Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Section 2.4.1 Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Settings")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Placeholder screen. Presets will live here.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.4.2 Preset
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Scan Preset")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Picker("Preset", selection: selectedPreset) {
                        ForEach(Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPresetRaw) { _, newValue in
                        if ScannerDebug.isEnabled { ScannerDebug.writeLog("SettingsView: preset changed to \(newValue)") }
                    }

                        .font(Theme.Typography.caption)
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
