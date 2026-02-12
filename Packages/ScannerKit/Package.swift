// swift-tools-version: 5.9
//
//  Package.swift
//  ScannerKit
//
//  Defines the ScannerKit Swift Package.
//  - ScannerKit: Core, UI-agnostic models + capture utilities.
//
//  NOTE:
//  Sources are organized as sibling folders under Sources/ (Capture, Models, ScannerKit).
//  SwiftPM only auto-discovers Sources/<TargetName>/..., so we explicitly map sources.
//

import PackageDescription

let package = Package(
    name: "ScannerKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ScannerKit",
            targets: ["ScannerKit"]
        ),
    ],
    targets: [
        // 1) Core module: includes Sources/Capture, Sources/Models, Sources/ScannerKit
        .target(
            name: "ScannerKit",
            path: "Sources",
            sources: [
                "Capture",
                "Models",
                "ScannerKit"
            ]
        ),
    ]
)

// Package.swift
