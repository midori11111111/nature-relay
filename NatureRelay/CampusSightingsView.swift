import SwiftUI
import CoreLocation

/// Reads public observations near the fixed De Anza campus. User location is never sent.
struct CampusSightingsView: View {
    let onImported: (NatureObservation?) -> Void
    var onCreateCompanion: ((NatureObservation) -> Void)? = nil
    @EnvironmentObject private var store: RelayStore
    @Environment(\.dismiss) private var dismiss
    @State private var observations: [NatureObservation] = []
    @State private var selectedIDs: Set<Int> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var importError: String?
    @State private var totalResults = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                introduction
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(NRTheme.green)
                        Text("Finding campus neighbors…")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load sightings", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent).tint(NRTheme.green)
                    }
                } else if observations.isEmpty {
                    ContentUnavailableView("No sightings to show", systemImage: "leaf", description: Text("No openly licensed observations were available nearby. Try again later or add your own discovery."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            HStack {
                                Text("\(observations.count) recent records · \(totalResults) available")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(NRTheme.muted)
                                Spacer()
                                Button(selectedIDs.count == observations.count ? "Clear" : "Select all") {
                                    if selectedIDs.count == observations.count { selectedIDs.removeAll() }
                                    else { selectedIDs = Set(observations.compactMap(\.sourceRecordID)) }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NRTheme.green)
                            }
                            ForEach(observations) { observation in
                                sightingRow(observation)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .background(NRTheme.cream)
            .foregroundStyle(NRTheme.ink)
            .navigationTitle("Campus neighbors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(NRTheme.green)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !observations.isEmpty && errorMessage == nil && !isLoading {
                    Button(action: importSelected) {
                        HStack(spacing: 9) {
                            Image(systemName: "map.fill")
                            Text(selectedIDs.isEmpty ? "Choose sightings to add" : "Add \(selectedIDs.count) to my map")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(selectedIDs.isEmpty ? NRTheme.muted : .white)
                        .background(selectedIDs.isEmpty ? Color.white : NRTheme.green, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(selectedIDs.isEmpty)
                    .padding(18)
                    .background(NRTheme.cream)
                }
            }
            .task { await load() }
            .alert("Couldn't save sightings", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "") }
        }
        .presentationDragIndicator(.visible)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Real discoveries. Shared by the community.", systemImage: "leaf.fill")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Public iNaturalist observations within 1 km of De Anza College. Choose a real photo to make a companion, or add its original record to your map. Dates and photo credits stay attached.")
                .font(.system(size: 12))
                .foregroundStyle(NRTheme.muted)
            HStack(spacing: 5) {
                Image(systemName: "location.slash")
                Text("These are dated records, not live animal locations. Your location is never sent to iNaturalist.")
            }
            .font(.system(size: 10))
            .foregroundStyle(NRTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.white.opacity(0.7))
    }

    private func sightingRow(_ observation: NatureObservation) -> some View {
        let isSelected = observation.sourceRecordID.map { selectedIDs.contains($0) } ?? false
        return VStack(alignment: .leading, spacing: 11) {
            Button {
                guard let id = observation.sourceRecordID else { return }
                if selectedIDs.contains(id) { selectedIDs.remove(id) }
                else { selectedIDs.insert(id) }
            } label: {
                HStack(spacing: 13) {
                    AsyncImage(url: observation.sourcePhotoURL.flatMap(URL.init(string:))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            observation.kind.color.opacity(0.2)
                                .overlay(Image(systemName: observation.kind.symbol).foregroundStyle(NRTheme.green))
                        }
                    }
                    .frame(width: 82, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(observation.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(NRTheme.ink)
                            .multilineTextAlignment(.leading)
                        Text("Observed \(observation.observedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11))
                            .foregroundStyle(NRTheme.muted)
                        Text("by @\(observation.author)")
                            .font(.system(size: 11))
                            .foregroundStyle(NRTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? NRTheme.green : NRTheme.muted.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isSelected ? "Deselect" : "Select") \(observation.name), observed \(observation.observedAt.formatted(date: .abbreviated, time: .omitted))")
            if let onCreateCompanion {
                Button { onCreateCompanion(observation) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                        Text("Make a companion from this photo")
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NRTheme.green)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .background(NRTheme.lime.opacity(0.32), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("community.create.\(observation.sourceRecordID ?? 0)")
            }
            Text(observation.sourceAttribution ?? "Photo attribution on iNaturalist")
                .font(.system(size: 9))
                .foregroundStyle(NRTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let source = observation.sourceURL, let url = URL(string: source) {
                Link(destination: url) {
                    Label("View original observation", systemImage: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(NRTheme.green)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(isSelected ? NRTheme.green.opacity(0.5) : .clear, lineWidth: 1.5))
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await CampusSightingsAPI.fetch()
            guard !Task.isCancelled else { return }
            observations = response.observations
            totalResults = response.total
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            errorMessage = "The public observation service couldn't connect. Check your internet connection and try again."
        }
    }

    private func importSelected() {
        let entries = observations.filter { $0.sourceRecordID.map { selectedIDs.contains($0) } ?? false }
        do {
            try store.importCommunity(entries)
            onImported(entries.first)
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }
}

enum CampusSightingsAPI {
    struct Response {
        var observations: [NatureObservation]
        var total: Int
    }

    static func fetch() async throws -> Response {
        let url = URL(string: "https://api.inaturalist.org/v1/observations?lat=37.3195&lng=-122.0450&radius=1&per_page=20&photos=true&quality_grade=research&photo_license=cc0,cc-by&order_by=observed_on&order=desc")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        return Response(observations: decoded.results.compactMap(convert), total: decoded.total_results)
    }

    /// Downloads only an attributed, openly licensed public iNaturalist image.
    /// The streaming cap prevents a remote photo from using unbounded memory.
    static func downloadPhoto(for observation: NatureObservation) async throws -> Data {
        guard observation.sourceRecordID != nil,
              let source = observation.sourcePhotoURL, let url = URL(string: source),
              isAllowedPhotoURL(url) else { throw PhotoDownloadError.invalidSource }
        var request = URLRequest(url: url)
        request.timeoutInterval = 35
        request.setValue("image/jpeg,image/png,image/webp;q=0.9", forHTTPHeaderField: "Accept")
        let maximumBytes = 8 * 1_024 * 1_024
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let finalURL = http.url, isAllowedPhotoURL(finalURL),
              http.mimeType?.hasPrefix("image/") == true else {
            throw PhotoDownloadError.invalidImage
        }
        guard http.expectedContentLength <= Int64(maximumBytes) else { throw PhotoDownloadError.tooLarge }
        var data = Data()
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw PhotoDownloadError.tooLarge }
            data.append(byte)
        }
        guard !data.isEmpty else { throw PhotoDownloadError.invalidImage }
        return data
    }

    private static func isAllowedPhotoURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "static.inaturalist.org"
            || host == "inaturalist-open-data.s3.amazonaws.com"
            || host == "inaturalist-open-data.s3.us-east-1.amazonaws.com"
    }

    enum PhotoDownloadError: LocalizedError {
        case invalidSource, invalidImage, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalidSource: return "This public photo link isn't supported. Try another iNaturalist photo."
            case .invalidImage: return "The public image couldn't be downloaded. Try again or choose another photo."
            case .tooLarge: return "This photo is larger than the 8 MB limit. Choose another photo."
            }
        }
    }

    private static func convert(_ record: Record) -> NatureObservation? {
        guard let coordinates = record.geojson?.coordinates, coordinates.count >= 2,
              let taxon = record.taxon,
              let photo = record.photos.first(where: { ["cc0", "cc-by"].contains($0.license_code ?? "") }),
              let date = date(from: record.time_observed_at, fallback: record.observed_on) else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let name = taxon.preferred_common_name ?? taxon.name
        let kind: NatureKind
        switch taxon.iconic_taxon_name {
        case "Aves": kind = .bird
        case "Plantae":
            let suggested = PhotoRecognitionService.kind(for: [name])
            kind = [.flower, .tree, .plant].contains(suggested) ? suggested : .plant
        case "Insecta":
            kind = PhotoRecognitionService.kind(for: [name]) == .butterfly ? .butterfly : .other
        default: kind = .other
        }
        let uuid = UUID(uuidString: String(format: "20000000-0000-0000-0000-%012llx", Int64(record.id)))!
        return NatureObservation(
            id: uuid, name: name, kind: kind,
            note: "A public community observation near De Anza College. Recorded on \(date.formatted(date: .abbreviated, time: .omitted)); this is not a live location.",
            author: record.user.login, latitude: coordinate.latitude, longitude: coordinate.longitude,
            observedAt: date,
            sourceURL: "https://www.inaturalist.org/observations/\(record.id)",
            sourceAttribution: photo.attribution,
            sourcePhotoURL: photo.url.replacingOccurrences(of: "/square.", with: "/medium."),
            sourceRecordID: record.id
        )
    }

    private static func date(from timestamp: String?, fallback: String?) -> Date? {
        if let timestamp {
            let formatter = ISO8601DateFormatter()
            if let result = formatter.date(from: timestamp) { return result }
            formatter.formatOptions.insert(.withFractionalSeconds)
            if let result = formatter.date(from: timestamp) { return result }
        }
        guard let fallback else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: fallback)
    }

    private struct Payload: Decodable {
        let total_results: Int
        let results: [Record]
    }
    private struct Record: Decodable {
        let id: Int
        let observed_on: String?
        let time_observed_at: String?
        let geojson: GeoJSON?
        let taxon: Taxon?
        let user: User
        let photos: [Photo]
    }
    private struct GeoJSON: Decodable { let coordinates: [Double] }
    private struct Taxon: Decodable {
        let name: String
        let preferred_common_name: String?
        let iconic_taxon_name: String?
    }
    private struct User: Decodable { let login: String }
    private struct Photo: Decodable {
        let url: String
        let attribution: String
        let license_code: String?
    }
}
