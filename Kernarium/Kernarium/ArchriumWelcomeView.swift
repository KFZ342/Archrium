// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI

/// Shown while Documents holds no guest image. Archrium cannot boot by itself,
/// so the first launch explains where the Arch image has to go instead of
/// starting a guest that is certain to fail.
struct ArchriumWelcomeView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text("Archrium")
                        .font(.largeTitle.weight(.semibold))
                    Text("Arch Linux, in its own cabin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Copy archrium.erofs into Files", systemImage: "1.circle.fill")
                    Label("On My iPhone / iPad → Archrium", systemImage: "2.circle.fill")
                    Label("Return here and launch", systemImage: "3.circle.fill")
                }
                .font(.callout)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Text("The image is a 4 KiB EROFS built for the UML runtime. AirDrop or the Files app works; no terminal needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 520)
        }
        .accessibilityIdentifier("archriumWelcome")
    }
}
