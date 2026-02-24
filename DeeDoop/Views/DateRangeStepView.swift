//
//  DateRangeStepView.swift
//  DeeDoop
//

import SwiftUI

struct DateRangeStepView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let authorizationStatus: PhotoLibraryService.AuthorizationStatus
    /// e.g. "photos" or "videos" for the subtitle and description.
    var scanScopeLabel: String = "photos and videos"
    let onRequestAccess: () -> Void
    let onStartScan: () -> Void
    
    private var canScan: Bool {
        authorizationStatus == .authorized && startDate <= endDate
    }
    
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                // Permission section
                if authorizationStatus != .authorized {
                    PermissionCard(
                        status: authorizationStatus,
                        onRequestAccess: onRequestAccess
                    )
                }
                
                // Date range section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select date range")
                        .font(.headline)
                    Text("Scans \(scanScopeLabel) in your gallery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 16) {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                        
                        DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                    
                    if startDate > endDate {
                        Text("End date must be after start date")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                Text("The app will scan your gallery for \(scanScopeLabel) in this date range, and find duplicates based on file size and creation date.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 24)
                
                Button(action: onStartScan) {
                    HStack {
                        Text("Start Scan")
                        Image(systemName: "magnifyingglass")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canScan ? Color.orange : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canScan)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, max(24, geo.safeAreaInsets.bottom))
                .frame(minHeight: geo.size.height)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PermissionCard: View {
    let status: PhotoLibraryService.AuthorizationStatus
    let onRequestAccess: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status == .denied || status == .restricted ? "exclamationmark.triangle" : "photo.on.rectangle.angled")
                    .foregroundStyle(status == .denied || status == .restricted ? .red : .orange)
                Text("Photo Library Access")
                    .font(.headline)
            }
            
            switch status {
            case .notDetermined:
                Text("DeeDoop needs access to your photo library to find duplicate photos and videos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Grant Access", action: onRequestAccess)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            case .denied, .restricted:
                Text("Photo library access was denied. Please enable it in Settings → DeeDoop → Photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Link("Open Settings", destination: URL.appSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            case .authorized:
                EmptyView()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
    }
}

#Preview("Not determined") {
    DateRangeStepView(
        startDate: .constant(Date()),
        endDate: .constant(Date()),
        authorizationStatus: .notDetermined,
        onRequestAccess: {},
        onStartScan: {}
    )
}

#Preview("Authorized") {
    DateRangeStepView(
        startDate: .constant(Date()),
        endDate: .constant(Date()),
        authorizationStatus: .authorized,
        onRequestAccess: {},
        onStartScan: {}
    )
}

#Preview("Denied") {
    DateRangeStepView(
        startDate: .constant(Date()),
        endDate: .constant(Date()),
        authorizationStatus: .denied,
        onRequestAccess: {},
        onStartScan: {}
    )
}

#Preview("Permission card - not determined") {
    PermissionCard(status: .notDetermined, onRequestAccess: {})
}

#Preview("Permission card - denied") {
    PermissionCard(status: .denied, onRequestAccess: {})
}
