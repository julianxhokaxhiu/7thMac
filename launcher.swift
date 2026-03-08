#!/usr/bin/env swift
// =============================================================================
// 7th Heaven macOS Launcher
// Compiled to: 7thHeaven.app/Contents/MacOS/7thHeaven
// =============================================================================

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Configuration

let GITHUB_API_URL = "https://api.github.com/repos/tsunamods-codes/7th-Heaven/releases/latest"
let TARGET_EXE_REL = "drive_c/Users/\(NSUserName())/AppData/Local/Programs/7th Heaven/7th Heaven.exe"

// Fetch latest installer URL from GitHub releases
func getLatestInstallerURL() -> String? {
    guard let url = URL(string: GITHUB_API_URL) else { return nil }

    do {
        let data = try Data(contentsOf: url)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assets = json["assets"] as? [[String: Any]] {

            for asset in assets {
                if let name = asset["name"] as? String,
                   name.hasSuffix("_Release.exe"),
                   let downloadURL = asset["browser_download_url"] as? String {
                    return downloadURL
                }
            }
        }
    } catch {
        log("Failed to fetch latest release info: \(error)")
    }

    return nil
}

// MARK: - Path Setup

let bundle = Bundle.main.bundleURL
let wineDir = bundle.appendingPathComponent("Contents/Resources/wine")
let wineBin = wineDir.appendingPathComponent("bin/wine")
let wineServer = wineDir.appendingPathComponent("bin/wineserver")
let wineLib = wineDir.appendingPathComponent("lib")

let appSupport = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/7th Heaven")
let winePrefix = appSupport.appendingPathComponent("prefix")
let targetExe = winePrefix.appendingPathComponent(TARGET_EXE_REL)
let logFile = appSupport.appendingPathComponent("launcher.log")

// MARK: - Logging

func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let logMessage = "[\(timestamp)] \(message)\n"
    print(message)

    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

// MARK: - Wine Environment

func setupWineEnvironment() {
    setenv("DYLD_FALLBACK_LIBRARY_PATH", wineLib.path, 1)
    setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "1", 1)
    setenv("WINEPREFIX", winePrefix.path, 1)
    setenv("WINEDLLPATH", wineDir.appendingPathComponent("lib/wine").path, 1)
    setenv("WINEDEBUG", "-all", 1)
    setenv("WINE_LARGE_ADDRESS_AWARE", "1", 1)
    setenv("WINEDLLOVERRIDES", "dinput=n,b", 1)
    log("Wine environment configured")
}

// MARK: - Process Execution

@discardableResult
func runCommand(_ command: String, args: [String], wait: Bool = true) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: command)
    task.arguments = args

    // Suppress output
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        if wait {
            task.waitUntilExit()
        }
        return task.terminationStatus
    } catch {
        log("Error running \(command): \(error)")
        return -1
    }
}

// MARK: - Wine Prefix Initialization

func initializeWinePrefix() {
    let driveC = winePrefix.appendingPathComponent("drive_c")

    if !FileManager.default.fileExists(atPath: driveC.path) {
        log("Initializing Wine prefix at \(winePrefix.path)...")
        showAlert(message: "First launch detected. Initializing Windows environment...", style: .informational)

        try? FileManager.default.createDirectory(at: winePrefix, withIntermediateDirectories: true)
        runCommand(wineBin.path, args: ["wineboot", "--init"])
        runCommand(wineServer.path, args: ["-w"])

        log("Wine prefix initialized")
    }
}

// MARK: - Wine Registry Configuration

func configureWineRegistry() {
    log("Configuring Wine registry for GDI rendering...")
    runCommand(wineBin.path, args: [
        "reg", "add",
        "HKCU\\Software\\Wine\\AppDefaults\\7th Heaven.exe\\Direct3D",
        "/v", "renderer",
        "/t", "REG_SZ",
        "/d", "gdi",
        "/f"
    ])
    log("Wine registry configured")
}

// MARK: - Download Installer

func downloadInstaller() -> Bool {
    log("Downloading 7th Heaven installer...")

    // Fetch latest installer URL from GitHub
    guard let installerURL = getLatestInstallerURL() else {
        log("Failed to determine latest installer URL")
        return false
    }

    log("Latest installer URL: \(installerURL)")

    let tempFile = appSupport.appendingPathComponent("7thHeaven-installer.exe.tmp")
    let installerExe = appSupport.appendingPathComponent("7thHeaven-installer.exe")

    // Show download progress
    DispatchQueue.main.async {
        showAlert(message: "Downloading 7th Heaven installer. This may take a few minutes...", style: .informational)
    }

    // Use curl for download
    let result = runCommand("/usr/bin/curl", args: [
        "-L",
        "--progress-bar",
        "-o", tempFile.path,
        installerURL
    ])

    if result == 0 {
        _ = try? FileManager.default.removeItem(at: installerExe)
        try? FileManager.default.moveItem(at: tempFile, to: installerExe)
        log("Download complete")
        return true
    } else {
        log("Download failed with status: \(result)")
        try? FileManager.default.removeItem(at: tempFile)
        return false
    }
}

// MARK: - Optional Custom FF7 Installer

func promptForCustomFF7Installer() -> URL? {
    let alert = NSAlert()
    alert.messageText = "Optional: Install Final Fantasy VII"
    alert.informativeText = "If you have a GOG (or other) FF7 installer, choose it now. Otherwise click Skip to continue with Steam autodetect."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Choose Installer")
    alert.addButton(withTitle: "Skip")

    let response = alert.runModal()
    if response != .alertFirstButtonReturn {
        return nil
    }

    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [UTType(filenameExtension: "exe")].compactMap { $0 }
    panel.title = "Choose Final Fantasy VII Installer"
    panel.message = "Select your FF7 installer .exe file."

    if panel.runModal() == .OK, let url = panel.url {
        return url
    }

    return nil
}

// MARK: - Find FF7 Steam Installation

func findFF7Path() -> String? {
    let gameDir = "FINAL FANTASY VII"
    let steamConfig = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/steamapps/libraryfolders.vdf")

    // Parse Steam library folders
    if FileManager.default.fileExists(atPath: steamConfig.path),
       let content = try? String(contentsOf: steamConfig, encoding: .utf8) {

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("\"path\"") {
                let components = line.components(separatedBy: "\"")
                if components.count >= 4 {
                    let path = components[3]
                    let candidate = "\(path)/steamapps/common/\(gameDir)"
                    if FileManager.default.fileExists(atPath: candidate) {
                        log("Found FF7 at: \(candidate)")
                        return candidate
                    }
                }
            }
        }
    }

    // Fallback locations
    let fallbacks = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/common/\(gameDir)").path,
        "/Volumes/SteamLibrary/steamapps/common/\(gameDir)",
        winePrefix.appendingPathComponent("drive_c/GOG Games/Final Fantasy VII").path
    ]

    for fallback in fallbacks {
        if FileManager.default.fileExists(atPath: fallback) {
            log("Found FF7 at fallback: \(fallback)")
            return fallback
        }
    }

    return nil
}

// MARK: - Mount Steam Game

func mountSteamGame(at path: String) {
    let dosDevices = winePrefix.appendingPathComponent("dosdevices")
    try? FileManager.default.createDirectory(at: dosDevices, withIntermediateDirectories: true)

    let gDrive = dosDevices.appendingPathComponent("g:")

    // Remove stale mapping
    try? FileManager.default.removeItem(at: gDrive)

    // Create symlink
    try? FileManager.default.createSymbolicLink(atPath: gDrive.path, withDestinationPath: path)
    log("Mounted Steam FF7 as G: -> \(path)")
}

// MARK: - UI Alerts

func showAlert(message: String, style: NSAlert.Style) {
    let alert = NSAlert()
    alert.messageText = style == .critical ? "7th Heaven - Error" : "7th Heaven"
    alert.informativeText = message
    alert.alertStyle = style
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

func showErrorAndExit(_ message: String) -> Never {
    log("FATAL: \(message)")
    showAlert(message: message, style: .critical)
    exit(1)
}

// MARK: - Main

func main() {
    log("=== 7th Heaven Launcher started ===")

    let userHomeFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("7th Heaven")
    try? FileManager.default.createDirectory(at: userHomeFolder, withIntermediateDirectories: true)

    // Verify Wine exists
    guard FileManager.default.fileExists(atPath: wineBin.path) else {
        showErrorAndExit("Wine runtime not found in app bundle. Please rebuild the application.")
    }

    setupWineEnvironment()

    // Check if Option key is held down to launch winecfg instead
    if NSEvent.modifierFlags.contains(.option) {
        log("Option key detected - launching winecfg")
        showAlert(message: "Launching Wine Configuration...\n\nHold Option (⌥) at launch to open this again.", style: .informational)

        let winecfg = wineDir.appendingPathComponent("bin/winecfg")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: winecfg.path)

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            showErrorAndExit("Failed to launch winecfg:\n\(error.localizedDescription)")
        }

        log("=== winecfg exited ===")
        exit(0)
    }

    // Check if 7th Heaven is already installed
    if FileManager.default.fileExists(atPath: targetExe.path) {
        log("7th Heaven already installed")
    } else {
        log("7th Heaven not found, starting installation flow")

        // Initialize Wine prefix
        initializeWinePrefix()

        // Download installer
        if !downloadInstaller() {
            showErrorAndExit("Failed to download 7th Heaven installer. Please check your internet connection.")
        }

        // Run installer
        log("Launching installer...")
        showAlert(message: "Running 7th Heaven installer. Please wait...", style: .informational)

        let installerExe = appSupport.appendingPathComponent("7thHeaven-installer.exe")
        runCommand(wineBin.path, args: [installerExe.path, "/VERYSILENT"])
        runCommand(wineServer.path, args: ["-w"])

        // Verify installation succeeded
        if !FileManager.default.fileExists(atPath: targetExe.path) {
            showErrorAndExit("Something went wrong. Please check the log file.")
        }

        log("7th Heaven installed successfully")

        if let customInstaller = promptForCustomFF7Installer() {
            log("Running custom FF7 installer: \(customInstaller.path)")
            showAlert(message: "Running FF7 installer. Please follow the on-screen instructions.", style: .informational)
            runCommand(wineBin.path, args: [customInstaller.path])
            runCommand(wineServer.path, args: ["-w"])
        } else {
            log("No custom FF7 installer selected; continuing with Steam autodetect")
        }
    }

    // Find and mount FF7 Steam installation
    log("Locating Final Fantasy VII installation...")
    guard let ff7Path = findFF7Path() else {
        showErrorAndExit("Could not locate Final Fantasy VII in your Steam library. Please ensure it is installed via Steam.")
    }

    mountSteamGame(at: ff7Path)

    // Configure Wine registry for rendering
    configureWineRegistry()

    // Launch 7th Heaven
    log("Launching 7th Heaven...")

    // Use exec-style launch (replace current process)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: wineBin.path)
    task.arguments = [targetExe.path]

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        showErrorAndExit("Failed to launch 7th Heaven:\n\(error.localizedDescription)")
    }

    log("=== 7th Heaven exited ===")
}

// Run main
main()
