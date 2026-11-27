// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// The Andarium-style front door: pick/import the Arch image, see what is
/// installed, then start the guest. The session view behind it stays the
/// proven Kernarium Linux runtime.
struct ArchriumHomeView: View {
    @ObservedObject private var launcher = EmulatorLauncher.shared
    @State private var launched = false
    @State private var importing = false
    @State private var copyingImage = false
    @State private var importError: String?
    @State private var images: [String] = []
    @State private var settingsPresented = false

    private var selectedImage: String? { images.first }

    /// The runtime boots one guest per process. Once a run has returned,
    /// starting again in this process is not what it offers, so the screen
    /// says how to get another run instead of leaving a dead Start button.
    private var runEnded: Bool {
        if case .ended = launcher.phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    imageCard
                    startButton
                    secondaryRow
                }
                .padding(24)
            }
            .background {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.09, blue: 0.16), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $settingsPresented) {
                EmulatorSettingsView()
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                importImage(result)
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .onAppear {
                removeStaleImports()
                refresh()
            }
        }
        .fullScreenCover(isPresented: $launched) {
            ContentView()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.cyan, .indigo)
            Text("Archrium")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("Arch Linux, in its own cabin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Guest image", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text(selectedImage == nil ? "Missing" : "Ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedImage == nil ? .orange : .green)
            }

            if let selectedImage {
                Text(selectedImage)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("4 KiB EROFS · ArchLinuxARM aarch64 · KDE Plasma")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Copy archrium.erofs into Files → On My iPhone / iPad → Archrium, or import it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if runEnded {
                Text("The last Linux run has ended. Close and reopen Archrium to start another.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button {
                importing = true
            } label: {
                HStack(spacing: 8) {
                    if copyingImage {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(copyingImage ? "Importing…" :
                        (selectedImage == nil ? "Import image" : "Replace image"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(copyingImage)
            .accessibilityIdentifier("importImage")
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var startButton: some View {
        Button {
            guard selectedImage != nil else { return }
            launched = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text(runEnded ? "Reopen Archrium to run again" : "Start Arch")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .disabled(selectedImage == nil || copyingImage || runEnded)
        .accessibilityIdentifier("startArch")
    }

    private var secondaryRow: some View {
        HStack(spacing: 12) {
            Button {
                settingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                refresh()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func refresh() {
        images = RootfsImage.availableFilenames()
    }

    /// An import killed mid-copy leaves a hidden multi-gigabyte temporary
    /// beside the images. Nothing can resume it, so remove it at launch.
    private func removeStaleImports() {
        let manager = FileManager.default
        // Do not skip hidden files: the temporary itself starts with a dot.
        guard let all = try? manager.contentsOfDirectory(
            at: RootfsImage.documentsDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for url in all {
            let name = url.lastPathComponent
            guard name.hasPrefix(".archrium-import-"),
                  (name as NSString).pathExtension.lowercased() == "erofs"
            else { continue }
            try? manager.removeItem(at: url)
        }
    }

    private func importImage(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            guard source.pathExtension.lowercased() == "erofs" else {
                throw NSError(
                    domain: "Archrium",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Only .erofs images can be imported here."
                    ]
                )
            }
            let destination = RootfsImage.documentsDirectory
                .appendingPathComponent(RootfsImage.defaultFilename)
            let temporary = RootfsImage.documentsDirectory
                .appendingPathComponent(
                    ".archrium-import-\(UUID().uuidString).erofs"
                )
            let scoped = source.startAccessingSecurityScopedResource()
            copyingImage = true
            Task { @MainActor in
                // A multi-gigabyte copy must not run on the main actor, or
                // iOS can end the app for a blocked launch screen.
                let failure: String? = await Task.detached(
                    priority: .userInitiated
                ) {
                    let manager = FileManager.default
                    do {
                        if manager.fileExists(atPath: temporary.path) {
                            try manager.removeItem(at: temporary)
                        }
                        try manager.copyItem(at: source, to: temporary)
                        if manager.fileExists(atPath: destination.path) {
                            _ = try manager.replaceItemAt(
                                destination,
                                withItemAt: temporary,
                                backupItemName: nil,
                                options: []
                            )
                        } else {
                            try manager.moveItem(
                                at: temporary, to: destination
                            )
                        }
                        return nil
                    } catch {
                        try? manager.removeItem(at: temporary)
                        return error.localizedDescription
                    }
                }.value
                if scoped { source.stopAccessingSecurityScopedResource() }
                copyingImage = false
                if let failure {
                    importError = failure
                    return
                }
                // The writable layer describes the old base image.
                OverlayDisk.reset()
                refresh()
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}
