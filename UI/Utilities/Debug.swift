// Debug.swift
// File: Debug.swift
// Description:
// Centralized debug utility for ScannerApp.
// - Controls debug logging via a single toggle.
// - Allows optional accumulation of logs.
// - Can export logs to a timestamped text file in Documents when requested.
// - Default debug mode is OFF.
//
// Sections:
// 1. Configuration
// 2. Logging
// 3. Log Storage
// 4. Export
//
// End of file marker included at bottom.

import Foundation

// Section 1. Configuration
enum ScannerDebug {
    
    // Toggle debug mode globally.
    static var isEnabled: Bool = false
    
    // Internal in-memory log buffer.
    private static var logBuffer: [String] = []
    
    // Date formatter for consistent timestamps.
    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()
    
    // Section 2. Logging
    static func writeLog(_ message: String) {
        guard isEnabled else { return }
        
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        
        print(entry)
        logBuffer.append(entry)
    }
    
    // Section 3. Log Storage
    static func clearLogs() {
        logBuffer.removeAll()
    }
    
    static func currentLogs() -> String {
        logBuffer.joined(separator: "\n")
    }
    
    // Section 4. Export
    // Writes accumulated logs to a file in the app's Documents directory.
    static func exportLogsToFile() {
        guard isEnabled else { return }
        
        let fileName = "ScannerDebugLog_\(Int(Date().timeIntervalSince1970)).txt"
        let logText = currentLogs()
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("ScannerDebug: Unable to locate Documents directory.")
            return
        }
        
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            try logText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("ScannerDebug: Logs exported to \(fileURL.path)")
        } catch {
            print("ScannerDebug: Failed to write log file: \(error)")
        }
    }
}

// End of file: Debug.swift
