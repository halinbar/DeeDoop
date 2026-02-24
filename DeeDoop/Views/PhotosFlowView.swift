//
//  PhotosFlowView.swift
//  DeeDoop
//

import SwiftUI

struct PhotosFlowView: View {
    let mediaFilter: PhotoLibraryService.MediaFilter
    
    @StateObject private var photoService = PhotoLibraryService()
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var hasStartedScan = false
    
    private var title: String {
        mediaFilter == .photosOnly ? "Photos" : "Videos"
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea(edges: .all)
            Group {
                if !hasStartedScan {
                    DateRangeStepView(
                        startDate: $startDate,
                        endDate: $endDate,
                        authorizationStatus: photoService.authorizationStatus,
                        scanScopeLabel: mediaFilter == .photosOnly ? "photos" : "videos",
                        onRequestAccess: { photoService.requestAuthorization() },
                        onStartScan: {
                            hasStartedScan = true
                            Task {
                                await photoService.scanForDuplicates(from: startDate, to: endDate, mediaFilter: mediaFilter)
                            }
                        }
                    )
                } else {
                    ScanResultsView(photoService: photoService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasStartedScan && !photoService.isScanning {
                ToolbarItem(placement: .primaryAction) {
                    Button("Rescan") {
                        hasStartedScan = false
                    }
                }
            }
        }
    }
}

#Preview("Photos flow") {
    NavigationStack {
        PhotosFlowView(mediaFilter: .photosOnly)
    }
}

#Preview("Videos flow") {
    NavigationStack {
        PhotosFlowView(mediaFilter: .videosOnly)
    }
}
