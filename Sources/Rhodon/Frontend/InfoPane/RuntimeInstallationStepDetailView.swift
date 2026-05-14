//
//  RuntimeInstallationStepDetailView.swift
//  Rhodon
//
//  Created by Matt Kiazyk on 2023-11-23.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import RhodonKit

struct RuntimeInstallationStepDetailView: View {
    let installationStep: RuntimeInstallationStep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Step \(installationStep.stepNumber) of \(installationStep.stepCount): \(installationStep.message)")

            switch installationStep {
            case let .downloading(progress):
                ObservingProgressIndicator(
                    progress,
                    controlSize: .regular,
                    style: .bar,
                    showsAdditionalDescription: true
                )

            case .installing, .trashingArchive:
                ObservingProgressIndicator(
                    Progress(),
                    controlSize: .regular,
                    style: .bar,
                    showsAdditionalDescription: false
                )
            }
        }
    }
}

#Preview("Downloading") {
    RuntimeInstallationStepDetailView(
        installationStep: .downloading(
            progress: configure(Progress()) {
                $0.kind = .file
                $0.fileOperationKind = .downloading
                $0.estimatedTimeRemaining = 123
                $0.totalUnitCount = 11_944_848_484
                $0.completedUnitCount = 848_444_920
                $0.throughput = 9_211_681
            }
        )
    )
}

#Preview("Installing") {
    RuntimeInstallationStepDetailView(
        installationStep: .installing
    )
}
