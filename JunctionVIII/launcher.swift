#!/usr/bin/env swift

/****************************************************************************/
//    Copyright (C) 2026 Julian Xhokaxhiu                                   //
//                                                                          //
//    This file is part of SummonKit                                        //
//                                                                          //
//    SummonKit is free software: you can redistribute it and/or modify     //
//    it under the terms of the GNU General Public License as published by  //
//    the Free Software Foundation, either version 3 of the License         //
//                                                                          //
//    SummonKit is distributed in the hope that it will be useful,          //
//    but WITHOUT ANY WARRANTY; without even the implied warranty of        //
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         //
//    GNU General Public License for more details.                          //
/****************************************************************************/

// =============================================================================
// Junction VIII macOS Launcher
// Compiled to: JunctionVIII.app/Contents/MacOS/JunctionVIII
// =============================================================================

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Configuration

let GITHUB_API_URL = "https://api.github.com/repos/tsunamods-codes/Junction-VIII/releases/latest"
let TARGET_EXE_REL = "drive_c/Users/\(NSUserName())/AppData/Local/Programs/Junction VIII/Junction VIII.exe"
let FF8_GAME_DIR = "FINAL FANTASY VIII"

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
    .appendingPathComponent("Library/Application Support/Junction VIII")
let winePrefix = appSupport.appendingPathComponent("prefix")
let targetExe = winePrefix.appendingPathComponent(TARGET_EXE_REL)
let logFile = appSupport.appendingPathComponent("launcher.log")
let wineLogFile = appSupport.appendingPathComponent("wine.log")

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
    setenv("LANG", "en-US.UTF-8", 1)
    setenv("LC_ALL", "en-US", 1)
    setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "1", 1)
    setenv("WINEPREFIX", winePrefix.path, 1)
    setenv("WINEDLLPATH", wineDir.appendingPathComponent("lib/wine").path, 1)
    setenv("WINE_LARGE_ADDRESS_AWARE", "1", 1)
    setenv("WINEDLLOVERRIDES", "dinput=n,b", 1)
    setenv("DXMT_LOG_LEVEL", "info", 1)
    setenv("DXMT_LOG_PATH", appSupport.path, 1)

    let dxmtRoot = bundle.appendingPathComponent("Contents/Resources/dxmt")
    if let entries = try? FileManager.default.contentsOfDirectory(
        at: dxmtRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) {
        let versionDirs = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }

        if let dxmtVersionDir = versionDirs.first {
            setenv("WINEDLLPATH_PREPEND", dxmtVersionDir.path, 1)
            log("WINEDLLPATH_PREPEND set to: \(dxmtVersionDir.path)")
        } else {
            log("Warning: No DXMT version directory found under: \(dxmtRoot.path)")
        }
    } else {
        log("Warning: Failed to enumerate DXMT directory at: \(dxmtRoot.path)")
    }

    log("Wine environment configured")
}

// MARK: - Process Execution

@discardableResult
func runCommand(_ command: String, args: [String], wait: Bool = true) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: command)
    task.arguments = args

    // Redirect Wine output to log file for debugging
    if command.contains("wine") {
        if let handle = try? FileHandle(forWritingTo: wineLogFile) {
            handle.seekToEndOfFile()
            task.standardOutput = handle
            task.standardError = handle
        } else {
            // Create log file if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            try? Data().write(to: wineLogFile)
            if let handle = try? FileHandle(forWritingTo: wineLogFile) {
                task.standardOutput = handle
                task.standardError = handle
            }
        }
    } else {
        // Suppress output for non-Wine commands
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
    }

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
        showStatusMessage(message: "First launch detected. Initializing Windows environment...", style: .informational)

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
        "HKCU\\Software\\Wine\\AppDefaults\\Junction VIII.exe\\Direct3D",
        "/v", "renderer",
        "/t", "REG_SZ",
        "/d", "gdi",
        "/f"
    ])
    log("Wine registry configured")
}

func setupSteamRegistry(steamPath: String) {
    log("Configuring Wine registry for Steam path...")
    let windowsPath = steamPath.replacingOccurrences(of: winePrefix.path + "/drive_c", with: "C:")
        .replacingOccurrences(of: "/", with: "\\")
    
    runCommand(wineBin.path, args: [
        "reg", "add",
        "HKCU\\SOFTWARE\\Valve\\Steam",
        "/v", "SteamPath",
        "/t", "REG_SZ",
        "/d", windowsPath,
        "/f"
    ])
    log("Steam registry configured with path: \(windowsPath)")
}

func patchConfigVDF(at path: String, steamPath: String) {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        log("Failed to read config VDF for patching at: \(path)")
        return
    }

    var patchedContent = content
    let windowsPath = steamPath.replacingOccurrences(of: winePrefix.path + "/drive_c", with: "C:")
        .replacingOccurrences(of: "/", with: "\\")

    // Replace Unix Steam paths with Windows Steam path
    let unixPathPattern = try! NSRegularExpression(pattern: "\"path\"\\s+\"[^\"]*\\/Users\\/[^\"]*\\/Library\\/Application Support\\/Steam\"", options: [])
    let range = NSRange(patchedContent.startIndex..., in: patchedContent)
    let matches = unixPathPattern.matches(in: patchedContent, options: [], range: range)

    if matches.count > 0 {
        let escapedWindowsPath = windowsPath.replacingOccurrences(of: "\\", with: "\\\\\\\\")
        patchedContent = unixPathPattern.stringByReplacingMatches(in: patchedContent, options: [], range: range, withTemplate: "\"path\"\t\t\"\(escapedWindowsPath)\"")
        do {
            try patchedContent.write(toFile: path, atomically: true, encoding: .utf8)
            log("Patched config VDF at: \(path)")
        } catch {
            log("Failed to patch config VDF: \(error.localizedDescription)")
        }
    } else {
        log("No Unix Steam path found in config VDF to patch")
    }
}

// MARK: - Download Installer

func downloadInstaller() -> Bool {
    log("Downloading Junction VIII installer...")

    // Fetch latest installer URL from GitHub
    guard let installerURL = getLatestInstallerURL() else {
        log("Failed to determine latest installer URL")
        return false
    }

    log("Latest installer URL: \(installerURL)")

    let tempFile = appSupport.appendingPathComponent("JunctionVIII-installer.exe.tmp")
    let installerExe = appSupport.appendingPathComponent("JunctionVIII-installer.exe")

    // Show download progress
    DispatchQueue.main.async {
        showStatusMessage(message: "Downloading Junction VIII installer. This may take a few minutes...", style: .informational)
    }

    // Use native URLSession for download
    let semaphore = DispatchSemaphore(value: 0)
    var success = false

    guard let url = URL(string: installerURL) else {
        log("Invalid installer URL: \(installerURL)")
        return false
    }

    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:148.0) Gecko/20100101 Firefox/148.0", forHTTPHeaderField: "User-Agent")

    let task = URLSession.shared.downloadTask(with: request) { tempUrl, response, error in
        if let error = error {
            log("Download failed: \(error.localizedDescription)")
        } else if let httpResponse = response as? HTTPURLResponse {
            log("HTTP Response: \(httpResponse.statusCode)")

            if httpResponse.statusCode >= 400 {
                log("Download failed with HTTP \(httpResponse.statusCode)")
            } else if let tempUrl = tempUrl {
                do {
                    try FileManager.default.removeItem(at: installerExe)
                } catch {
                    // File doesn't exist, that's fine
                }
                do {
                    try FileManager.default.moveItem(at: tempUrl, to: installerExe)
                    log("Download complete")
                    success = true
                } catch {
                    log("Failed to save downloaded file: \(error.localizedDescription)")
                }
            }
        }
        semaphore.signal()
    }

    task.resume()
    semaphore.wait()

    if !success {
        try? FileManager.default.removeItem(at: tempFile)
    }

    return success
}

// MARK: - Find FF8 Steam Installation

func parseInstallDirFromAppManifest(_ manifestPath: String) -> String? {
    guard let manifestContent = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
        return nil
    }

    for rawLine in manifestContent.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.contains("\"installdir\"") {
            let components = line.components(separatedBy: "\"")
            if components.count >= 4 {
                let installDir = components[3]
                if !installDir.isEmpty {
                    return installDir
                }
            }
        }
    }

    return nil
}

func findFF8Path() -> (path: String, installDir: String, gameID: String, libraryPath: String)? {
    let ff7GameIDs = ["39150"]  // FF8 original and remaster

    let steamConfig = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/steamapps/libraryfolders.vdf")

    // Parse Steam library folders and check for FF8 game IDs
    if FileManager.default.fileExists(atPath: steamConfig.path),
       let content = try? String(contentsOf: steamConfig, encoding: .utf8) {

        let lines = content.components(separatedBy: .newlines)
        var currentLibraryPath: String?
        var inAppsSection = false

        for line in lines {
            // Extract library path
            if line.contains("\"path\"") {
                let components = line.components(separatedBy: "\"")
                if components.count >= 4 {
                    currentLibraryPath = components[3]
                }
            }

            // Check if we're entering the apps section
            if line.contains("\"apps\"") {
                inAppsSection = true
            }

            // Check if we're leaving the apps section (closing brace)
            if inAppsSection && line.trimmingCharacters(in: .whitespaces) == "}" {
                inAppsSection = false
                currentLibraryPath = nil
            }

            // Check for FF8 game IDs in the apps section
            if inAppsSection, let libraryPath = currentLibraryPath {
                for gameID in ff7GameIDs {
                    if line.contains("\"\(gameID)\"") {
                        let manifestPath = "\(libraryPath)/steamapps/appmanifest_\(gameID).acf"
                        if let installDir = parseInstallDirFromAppManifest(manifestPath) {
                            let candidate = "\(libraryPath)/steamapps/common/\(installDir)"
                            if FileManager.default.fileExists(atPath: candidate) {
                                log("Found FF8 (Game ID: \(gameID)) at: \(candidate) [installdir=\(installDir)]")
                                return (candidate, installDir, gameID, libraryPath)
                            }
                        }

                        let fallbackCandidate = "\(libraryPath)/steamapps/common/\(FF8_GAME_DIR)"
                        if FileManager.default.fileExists(atPath: fallbackCandidate) {
                            log("Found FF8 (Game ID: \(gameID)) at fallback path: \(fallbackCandidate)")
                            return (fallbackCandidate, FF8_GAME_DIR, gameID, libraryPath)
                        }
                    }
                }
            }
        }

        // Fallback: Check for appmanifest files in each library path
        var libraryPaths: [String] = []
        for line in lines {
            if line.contains("\"path\"") {
                let components = line.components(separatedBy: "\"")
                if components.count >= 4 {
                    libraryPaths.append(components[3])
                }
            }
        }

        for libraryPath in libraryPaths {
            for gameID in ff7GameIDs {
                let manifestPath = "\(libraryPath)/steamapps/appmanifest_\(gameID).acf"
                if FileManager.default.fileExists(atPath: manifestPath) {
                    if let installDir = parseInstallDirFromAppManifest(manifestPath) {
                        let candidate = "\(libraryPath)/steamapps/common/\(installDir)"
                        if FileManager.default.fileExists(atPath: candidate) {
                            log("Found FF8 (Game ID: \(gameID) via manifest) at: \(candidate) [installdir=\(installDir)]")
                            return (candidate, installDir, gameID, libraryPath)
                        }
                    }

                    let fallbackCandidate = "\(libraryPath)/steamapps/common/\(FF8_GAME_DIR)"
                    if FileManager.default.fileExists(atPath: fallbackCandidate) {
                        log("Found FF8 (Game ID: \(gameID) via manifest fallback) at: \(fallbackCandidate)")
                        return (fallbackCandidate, FF8_GAME_DIR, gameID, libraryPath)
                    }
                }
            }
        }
    }

    // Fallback locations
    let fallbacks = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/common/\(FF8_GAME_DIR)").path,
        "/Volumes/SteamLibrary/steamapps/common/\(FF8_GAME_DIR)",
        winePrefix.appendingPathComponent("drive_c/GOG Games/FINAL FANTASY VIII").path
    ]

    for fallback in fallbacks {
        if FileManager.default.fileExists(atPath: fallback) {
            log("Found FF8 at fallback: \(fallback)")
            // For fallback paths, return empty gameID and libraryPath as we don't have Steam metadata
            return (fallback, URL(fileURLWithPath: fallback).lastPathComponent, "", "")
        }
    }

    return nil
}

// MARK: - File Copying

func recursivelyRemoveUnusedFiles(at destinationURL: URL, sourceURL: URL) -> Bool {
    do {
        let fileManager = FileManager.default
        let destinationContents = try fileManager.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil)

        for item in destinationContents {
            let sourceItem = sourceURL.appendingPathComponent(item.lastPathComponent)

            if !fileManager.fileExists(atPath: sourceItem.path) {
                try fileManager.removeItem(at: item)
                log("Removed: \(item.path)")
            }
        }
        return true
    } catch {
        log("Error removing unused files: \(error.localizedDescription)")
        return false
    }
}

func recursivelyCopyFiles(from sourceURL: URL, to destinationURL: URL) -> Bool {
    let fileManager = FileManager.default

    do {
        // Create destination if it doesn't exist
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let sourceContents = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey, .typeIdentifierKey])

        for sourceItem in sourceContents {
            let destinationItem = destinationURL.appendingPathComponent(sourceItem.lastPathComponent)

            do {
                let resourceValues = try sourceItem.resourceValues(forKeys: [.isDirectoryKey])

                if resourceValues.isDirectory == true {
                    // Recursively copy subdirectory
                    if !recursivelyCopyFiles(from: sourceItem, to: destinationItem) {
                        return false
                    }
                } else {
                    // Remove existing file before copying
                    if fileManager.fileExists(atPath: destinationItem.path) {
                        try fileManager.removeItem(at: destinationItem)
                    }

                    // Copy file
                    try fileManager.copyItem(at: sourceItem, to: destinationItem)
                }
            } catch {
                log("Error copying \(sourceItem.lastPathComponent): \(error.localizedDescription)")
                return false
            }
        }

        return true
    } catch {
        log("Error reading source directory: \(error.localizedDescription)")
        return false
    }
}

// MARK: - Copy Steam VDF Files

func copySteamVDFFiles(gameID: String, libraryPath: String, steamPath: String) {
    guard !gameID.isEmpty && !libraryPath.isEmpty else {
        log("Cannot copy VDF files: gameID or libraryPath is empty")
        return
    }

    let fileManager = FileManager.default
    let steamappsPath = "\(steamPath)/steamapps"
    let configPath = "\(steamPath)/config"

    func copyIfNeeded(source: String, destination: String, label: String) -> Bool {
        guard fileManager.fileExists(atPath: source) else {
            log("Warning: \(label) not found at \(source)")
            return false
        }

        if fileManager.fileExists(atPath: destination),
           fileManager.contentsEqual(atPath: source, andPath: destination) {
            log("Skipping \(label): already up to date")
            return false
        }

        let destinationParent = URL(fileURLWithPath: destination).deletingLastPathComponent().path
        do {
            try fileManager.createDirectory(atPath: destinationParent, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.copyItem(atPath: source, toPath: destination)
            log("Copied \(label) to Wine prefix")
            return true
        } catch {
            log("Failed to copy \(label): \(error.localizedDescription)")
            return false
        }
    }

    var copiedAny = false

    // Copy steamapps/libraryfolders.vdf if needed
    let sourceVDF = "\(libraryPath)/steamapps/libraryfolders.vdf"
    let destVDF = "\(steamappsPath)/libraryfolders.vdf"
    copiedAny = copyIfNeeded(source: sourceVDF, destination: destVDF, label: "libraryfolders.vdf") || copiedAny

    // Copy steamapps/appmanifest_GAME_ID.acf if needed
    let sourceACF = "\(libraryPath)/steamapps/appmanifest_\(gameID).acf"
    let destACF = "\(steamappsPath)/appmanifest_\(gameID).acf"
    copiedAny = copyIfNeeded(source: sourceACF, destination: destACF, label: "appmanifest_\(gameID).acf") || copiedAny

    // Copy config/libraryfolders.vdf if needed
    let sourceConfigVDF = "\(libraryPath)/config/libraryfolders.vdf"
    let destConfigVDF = "\(configPath)/libraryfolders.vdf"
    copiedAny = copyIfNeeded(source: sourceConfigVDF, destination: destConfigVDF, label: "config/libraryfolders.vdf") || copiedAny

    if !copiedAny {
        log("Steam VDF files already up to date; no copy needed")
    }

    // Patch config VDF to use Windows Steam path
    patchConfigVDF(at: destConfigVDF, steamPath: steamPath)
}

func isSteamFF8Install(path: String, gameID: String, libraryPath: String) -> Bool {
    if !gameID.isEmpty || !libraryPath.isEmpty {
        return true
    }

    // Handle fallback Steam paths where metadata may be unavailable.
    return path.contains("/steamapps/common/")
}

func ensureSteamUserDirectoriesIfNeeded(isSteamInstall: Bool) {
    guard isSteamInstall else {
        return
    }

    let documentsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Square Enix/FINAL FANTASY VIII Steam/user_12345678")

    do {
        try FileManager.default.createDirectory(at: documentsPath, withIntermediateDirectories: true)
        log("Ensured Steam user directories at: \(documentsPath.path)")
    } catch {
        log("Warning: Failed to create Steam user directories: \(error.localizedDescription)")
    }
}

// MARK: - Copy FF8 Game Into Wine Prefix

func copyFF8IntoWinePrefix(from sourcePath: String, installDir: String) -> String? {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    let destinationURL = winePrefix
        .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/\(installDir)")
    let destinationParent = destinationURL.deletingLastPathComponent()

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        log("Source FF8 path does not exist: \(sourceURL.path)")
        return nil
    }

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        if let existingEntries = try? FileManager.default.contentsOfDirectory(atPath: destinationURL.path),
           !existingEntries.isEmpty {
            log("FF8 already present in Wine prefix at: \(destinationURL.path), skipping copy")
            return destinationURL.path
        }

        // Remove empty/partial destination before copying to avoid stale state.
        try? FileManager.default.removeItem(at: destinationURL)
    }

    try? FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
    showStatusMessage(message: "Copying FINAL FANTASY VIII into Wine prefix. This may take a while...", style: .informational)

    // Use native Swift recursive copy with cleanup
    if recursivelyCopyFiles(from: sourceURL, to: destinationURL) {
        log("FF8 copied to Wine prefix at: \(destinationURL.path)")
        return destinationURL.path
    }

    log("Failed to copy FF8 using recursive copy")
    try? FileManager.default.removeItem(at: destinationURL)
    return nil
}

// MARK: - UI Status Window

final class StatusWindow {
    private let window: NSWindow
    private let textView: NSTextView

    init() {
        let windowSize = NSSize(width: 640, height: 360)
        self.window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.window.title = "Junction VIII - Status"
        self.window.center()

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(origin: .zero, size: windowSize)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        self.textView = scrollView.documentView as! NSTextView
        self.textView.isEditable = false  // Read-only: prevents focus stealing blocking updates
        self.textView.isSelectable = true
        self.textView.drawsBackground = true
        self.textView.backgroundColor = .textBackgroundColor
        self.textView.textColor = .labelColor
        self.textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        self.textView.isVerticallyResizable = true
        self.textView.isHorizontallyResizable = false
        self.textView.textContainer?.containerSize = NSSize(
            width: windowSize.width,
            height: .greatestFiniteMagnitude
        )
        self.textView.textContainer?.widthTracksTextView = true
        self.textView.isRichText = false

        // Add initial text to verify rendering
        self.textView.string = "INFO: Launching Junction VIII...\n"
        self.window.contentView = scrollView
    }

    func show() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.window.orderOut(nil)
        }
    }

    func append(message: String, style: NSAlert.Style) {
        let prefix = style == .critical ? "ERROR: " : "INFO: "
        let line = prefix + message + "\n"

        DispatchQueue.main.async {
            self.textView.string += line

            let endRange = NSRange(location: self.textView.string.count, length: 0)
            self.textView.scrollRangeToVisible(endRange)
        }
    }
}

var statusWindow: StatusWindow!

func showStatusMessage(message: String, style: NSAlert.Style) {
    statusWindow.append(message: message, style: style)
}

func showErrorAndExit(_ message: String) -> Never {
    log("FATAL: \(message)")
    showStatusMessage(message: message, style: .critical)
    exit(1)
}

// MARK: - Main

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusWindow = StatusWindow()
        NSApp.activate(ignoringOtherApps: true)  // use NSApp, not application
        statusWindow.show()
        DispatchQueue.global(qos: .userInitiated).async {
            runMain()                             // renamed to avoid conflict with AppDelegate.main
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

func runMain() {
    log("=== Junction VIII Launcher started ===")

    // Verify Wine exists
    guard FileManager.default.fileExists(atPath: wineBin.path) else {
        showErrorAndExit("Wine runtime not found in app bundle. Please rebuild the application.")
    }

    setupWineEnvironment()

    // Check if Option key is held down to launch winecfg instead
    if NSEvent.modifierFlags.contains(.option) {
        log("Option key detected - launching winecfg")
        showStatusMessage(message: "Launching Wine Configuration...\n\nHold Option (⌥) at launch to open this again.", style: .informational)

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

    // Check if Junction VIII is already installed
    if FileManager.default.fileExists(atPath: targetExe.path) {
        log("Junction VIII already installed")
    } else {
        log("Junction VIII not found, starting installation flow")

        // Initialize Wine prefix
        initializeWinePrefix()

        // Download installer
        if !downloadInstaller() {
            showErrorAndExit("Failed to download Junction VIII installer. Please check your internet connection.")
        }

        // Run installer
        log("Launching installer...")
        showStatusMessage(message: "Running Junction VIII installer. Please wait...", style: .informational)

        let installerExe = appSupport.appendingPathComponent("JunctionVIII-installer.exe")
        runCommand(wineBin.path, args: [installerExe.path, "/VERYSILENT"])
        runCommand(wineServer.path, args: ["-w"])

        // Verify installation succeeded
        if !FileManager.default.fileExists(atPath: targetExe.path) {
            showErrorAndExit("Something went wrong. Please check the log file.")
        }

        log("Junction VIII installed successfully")

        // Clean up installer
        do {
            try FileManager.default.removeItem(at: installerExe)
            log("Cleaned up installer executable")
        } catch {
            log("Warning: Failed to clean up installer: \(error.localizedDescription)")
        }
    }

    // Find FF8 installation and copy it to the expected Steam path in Wine prefix
    log("Locating FINAL FANTASY VIII installation...")
    guard let ff7Install = findFF8Path() else {
        showErrorAndExit("Could not locate FINAL FANTASY VIII in your Steam library. Please ensure it is installed via Steam.")
    }

    let steamInstallDetected = isSteamFF8Install(path: ff7Install.path, gameID: ff7Install.gameID, libraryPath: ff7Install.libraryPath)
    ensureSteamUserDirectoriesIfNeeded(isSteamInstall: steamInstallDetected)

    guard copyFF8IntoWinePrefix(from: ff7Install.path, installDir: ff7Install.installDir) != nil else {
        showErrorAndExit("Failed to copy FINAL FANTASY VIII into the Wine prefix. Please check permissions and free disk space.")
    }

    // Copy Steam VDF files for game detection (includes config VDF patching)
    let steamPath = winePrefix.path + "/drive_c/Program Files (x86)/Steam"
    copySteamVDFFiles(gameID: ff7Install.gameID, libraryPath: ff7Install.libraryPath, steamPath: steamPath)

    // Setup Steam registry path
    setupSteamRegistry(steamPath: steamPath)

    // Configure Wine registry for rendering
    configureWineRegistry()

    // Launch Junction VIII
    log("Launching Junction VIII...")

    // Use exec-style launch (replace current process)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: wineBin.path)
    task.arguments = [targetExe.path]

    do {
        try task.run()
        statusWindow.hide()
        task.waitUntilExit()
    } catch {
        showErrorAndExit("Failed to launch Junction VIII:\n\(error.localizedDescription)")
    }

    log("=== Junction VIII exited ===")
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
