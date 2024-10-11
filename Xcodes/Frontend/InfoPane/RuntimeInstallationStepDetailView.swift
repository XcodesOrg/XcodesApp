//
//  RuntimeInstallationStepDetailView.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-11-23.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import XcodesKit

struct RuntimeInstallationStepDetailView: View {
    let installationStep: RuntimeInstallationStep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: localizeString("InstallationStepDescription"), installationStep.stepNumber, installationStep.stepCount, installationStep.message))
            
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
            $0.totalUnitCount = 11944848484
            $0.completedUnitCount = 848444920
            $0.throughput = 9211681
        }
    ))
}
#Preview("Installing") {
    RuntimeInstallationStepDetailView(
        installationStep: .installing
        )
}
