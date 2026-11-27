// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// The Andarium-style front door: pick/import the Arch image, see what is
/// installed, then start the guest. The session view behind it stays the
/// proven Kernarium Linux runtime.
struct ArchriumHomeView: View {
    @State private var launched = false
    @State private var importing = false
    @State private var importError: String?
    @State private var images: [String] = []
    @State private var settingsPresented = false
    @State private var preparingImage = false

    private var selectedImage: String? { images.first }

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
            .overlay {
                if preparingImage {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing the bundled Linux image…")
                            .font(.callout)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .onAppear(perform: refresh)
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

            Button {
                importing = true
            } label: {
                Label(selectedImage == nil ? "Import image" : "Replace image", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
                Text("Start Arch")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .disabled(selectedImage == nil)
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
        guard selectedImage == nil, RootfsImage.needsBundledImage,
              !preparingImage else { return }
        preparingImage = true
        DispatchQueue.global(qos: .userInitiated).async {
            try? RootfsImage.installBundledImageIfNeeded()
            DispatchQueue.main.async {
                preparingImage = false
                images = RootfsImage.availableFilenames()
            }
        }
    }

    private func importImage(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let destination = RootfsImage.documentsDirectory
                .appendingPathComponent("archrium.erofs")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            refresh()
        } catch {
            importError = error.localizedDescription
        }
    }
}
