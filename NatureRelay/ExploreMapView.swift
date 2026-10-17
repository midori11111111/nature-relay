import SwiftUI
import MapKit
import UIKit

struct ExploreMapView: View {
    @EnvironmentObject private var store: RelayStore
    let observations: [NatureObservation]
    @Binding var selected: NatureObservation?
    @Binding var center: CLLocationCoordinate2D
    @Binding var mapSpan: MKCoordinateSpan
    let onCapture: () -> Void
    var onUseCommunityPhoto: ((NatureObservation) -> Void)? = nil

    @StateObject private var location = LocationService()
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: NRTheme.campus, span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006))
    )
    @State private var showSearch = false
    @State private var showCommunity = false
    @State private var pendingCommunityPhoto: NatureObservation?
    @State private var useSatellite = false
    @State private var activeKind: NatureKind?
    @State private var locationMessage: String?
    @State private var placeName = "De Anza & nearby"
    @State private var namedPlaceCoordinate = NRTheme.campus
    @State private var lastVisibleCenter = NRTheme.campus
    @State private var visibleRegion = MKCoordinateRegion(center: NRTheme.campus, span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006))
    @State private var namedPlaceRadius: CLLocationDistance = 500
    @State private var showLocationDetails = false

    private var visibleObservations: [NatureObservation] {
        let filtered = observations.filter { activeKind == nil || $0.kind == activeKind }
        return Dictionary(grouping: filtered, by: \.storyID).values.compactMap { records in
            records.max { $0.observedAt < $1.observedAt }
        }.sorted { $0.observedAt > $1.observedAt }
    }

    private var hasOnlySamples: Bool {
        !observations.isEmpty && observations.allSatisfy(\.isSample)
    }

    private var centerPlaceLabel: String {
        let current = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let named = CLLocation(latitude: namedPlaceCoordinate.latitude, longitude: namedPlaceCoordinate.longitude)
        return current.distance(from: named) < namedPlaceRadius ? placeName : "Exploring the map"
    }

    private var observationsInView: Int {
        visibleObservations.filter { observation in
            let latitudeDistance = abs(observation.latitude - visibleRegion.center.latitude)
            let longitudeDistance = abs(observation.longitude - visibleRegion.center.longitude)
            return latitudeDistance <= visibleRegion.span.latitudeDelta / 2
                && min(longitudeDistance, 360 - longitudeDistance) <= visibleRegion.span.longitudeDelta / 2
        }.count
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
                if let coordinate = location.coordinate, let accuracy = location.horizontalAccuracy {
                    MapCircle(center: coordinate, radius: max(accuracy, 10))
                        .foregroundStyle(.blue.opacity(0.08))
                        .stroke(.blue.opacity(0.25), lineWidth: 1)
                }
                ForEach(visibleObservations) { observation in
                    Annotation(observation.name, coordinate: observation.coordinate, anchor: .bottom) {
                        Button {
                            selected = observation
                        } label: {
                            MapFriendMarker(observation: observation, compact: visibleRegion.span.latitudeDelta > 0.12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(observation.name), \(observation.kind.title)\(observation.isSample ? ", demo observation" : ""). \(location.distanceDescription(to: observation.coordinate) ?? ""). View discovery.")
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(useSatellite ? .hybrid(elevation: .flat) : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                lastVisibleCenter = context.region.center
                visibleRegion = context.region
                mapSpan = context.region.span
                center = context.region.center
            }
            .overlay(alignment: .topLeading) {
                mapCaption
                    .padding(.top, 12)
                    .padding(.leading, 16)
                    .padding(.trailing, 70)
            }
            .overlay(alignment: .trailing) {
                mapControls.padding(.trailing, 18)
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { discoveryCard }
        }
        .background(NRTheme.cream)
        .onAppear {
            lastVisibleCenter = center
            position = .region(.init(center: center, span: mapSpan))
        }
        .onChange(of: center.latitude) { _, _ in syncExternalCenter() }
        .onChange(of: center.longitude) { _, _ in syncExternalCenter() }
        .onChange(of: observations.map(\.companionImageName)) { _, _ in activeKind = nil }
        .onChange(of: location.lastUpdatedAt) { _, _ in
            guard let coordinate = location.coordinate else { return }
            moveMap(to: coordinate, name: location.isApproximate ? "Your approximate location" : "Your location")
        }
        .onChange(of: location.message) { _, message in locationMessage = message }
        .sheet(isPresented: $showLocationDetails) {
            locationDetails
        }
        .sheet(isPresented: $showSearch) {
            PlaceSearchSheet(center: center) { item in
                moveMap(to: item.placemark.coordinate, name: item.name ?? "Selected place")
            }
        }
        .sheet(isPresented: $showCommunity, onDismiss: {
            guard let source = pendingCommunityPhoto else { return }
            pendingCommunityPhoto = nil
            onUseCommunityPhoto?(source)
        }) {
            CampusSightingsView(onImported: { first in
                activeKind = nil
                if let first { moveMap(to: first.coordinate, name: "Community sightings · De Anza") }
            }, onCreateCompanion: onUseCommunityPhoto == nil ? nil : { observation in
                pendingCommunityPhoto = observation
                showCommunity = false
            })
            .environmentObject(store)
        }
        .alert("Choose your location", isPresented: Binding(
            get: { locationMessage != nil },
            set: { if !$0 { locationMessage = nil } }
        )) {
            if location.canOpenSettings {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { locationMessage = nil }
        } message: {
            Text(locationMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Find nature nearby")
                    .font(.title2.weight(.bold))
                    .tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { showCommunity = true } label: {
                    Text("Community")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(NRTheme.green)
                .accessibilityLabel("Community sightings from iNaturalist")
                .accessibilityHint("Browse and import public nature observations")
            }

            HStack(spacing: 8) {
                Button { showSearch = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Search places")
                            .font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(NRTheme.ink.opacity(0.75))
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("explore.search")

                Menu {
                    Button("California", systemImage: "map") {
                        moveMap(to: .init(latitude: 37.2, longitude: -119.5), name: "California",
                                span: .init(latitudeDelta: 10.5, longitudeDelta: 10.5), nameRadius: 600_000)
                    }
                    Button("De Anza & nearby", systemImage: "leaf") {
                        moveMap(to: NRTheme.campus, name: "De Anza & nearby", span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08), nameRadius: 5000)
                    }
                    Button("De Anza campus", systemImage: "building.columns") {
                        moveMap(to: NRTheme.campus, name: "De Anza College")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map")
                        Text("Area")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(NRTheme.green)
                .accessibilityLabel("Explore California or De Anza campus")
                .accessibilityIdentifier("explore.area")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(nil, title: "All", symbol: "square.grid.2x2.fill")
                    categoryButton(.flower, title: "Flowers", symbol: NatureKind.flower.symbol)
                    categoryButton(.tree, title: "Trees", symbol: NatureKind.tree.symbol)
                    categoryButton(.bird, title: "Birds", symbol: NatureKind.bird.symbol)
                    categoryButton(.butterfly, title: "Butterflies", symbol: NatureKind.butterfly.symbol)
                    categoryButton(.plant, title: "Plants", symbol: NatureKind.plant.symbol)
                    categoryButton(.other, title: "More", symbol: NatureKind.other.symbol)
                }
            }
            .contentMargins(.trailing, 6)
        }
        .foregroundStyle(NRTheme.ink)
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(NRTheme.cream)
    }

    private var mapCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(centerPlaceLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(hasOnlySamples ? "Demo pins · tap to explore" : "\(observationsInView) in view · tap a pin")
                .font(.caption)
                .foregroundStyle(NRTheme.ink.opacity(0.75))
        }
        .foregroundStyle(NRTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    private func categoryButton(_ kind: NatureKind?, title: String, symbol: String) -> some View {
        let isActive = activeKind == kind
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { activeKind = kind }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .foregroundStyle(isActive ? .white : NRTheme.ink)
                .background(isActive ? NRTheme.green : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var mapControls: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { useSatellite.toggle() }
            } label: {
                Image(systemName: useSatellite ? "map.fill" : "square.3.layers.3d")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
            }
            .accessibilityLabel(useSatellite ? "Show standard map" : "Show satellite map")

            Button { location.requestLocation() } label: {
                Group {
                    if location.isLocating {
                        ProgressView().tint(NRTheme.ink)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(width: 46, height: 46)
            }
            .disabled(location.isLocating)
            .accessibilityLabel("Go to my current location")
            .accessibilityValue(location.accuracyDescription ?? "Location not requested")
        }
        .buttonStyle(.plain)
        .foregroundStyle(NRTheme.ink)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
        .shadow(color: NRTheme.ink.opacity(0.13), radius: 12, y: 5)
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Add a discovery")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onCapture) {
                    Label("Choose photo", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 15)
                        .frame(minHeight: 44)
                        .foregroundStyle(NRTheme.ink)
                        .background(NRTheme.lime, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a discovery: choose a photo or use the camera")
                .accessibilityHint("Use the photo’s saved GPS or choose its location before saving")
                .accessibilityIdentifier("explore.capture")
            }

            Text("Use your photo’s saved GPS or choose a spot.")
                .font(.subheadline)
                .foregroundStyle(NRTheme.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if let accuracy = location.accuracyDescription {
                Button { showLocationDetails = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: location.isApproximate ? "location.circle" : "location.circle.fill")
                        Text(accuracy)
                        Image(systemName: "info.circle")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NRTheme.green)
                    .frame(minHeight: 32, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Location details. \(accuracy)")
            }
        }
        .foregroundStyle(NRTheme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(NRTheme.ink.opacity(0.08)).frame(height: 1) }
    }

    private var locationDetails: some View {
        NavigationStack {
            List {
                Section("Current location") {
                    Text(location.accuracyDescription ?? "Location not requested")
                    if let updated = location.lastUpdatedAt {
                        LabeledContent("Last fix", value: updated.formatted(date: .omitted, time: .shortened))
                    }
                    let count = visibleObservations.filter { !$0.isSample && (location.distance(to: $0.coordinate) ?? .infinity) <= 1_000 }.count
                    LabeledContent("Recorded within 1 km", value: "\(count)")
                }
                Section {
                    Text("Distances are calculated on this iPhone. Use the location button to refresh your position.")
                        .foregroundStyle(NRTheme.ink.opacity(0.75))
                }
            }
            .foregroundStyle(NRTheme.ink)
            .navigationTitle("Location details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showLocationDetails = false }.tint(NRTheme.green)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func moveMap(to coordinate: CLLocationCoordinate2D, name: String,
                         span: MKCoordinateSpan = .init(latitudeDelta: 0.005, longitudeDelta: 0.005),
                         nameRadius: CLLocationDistance = 500) {
        lastVisibleCenter = coordinate
        center = coordinate
        placeName = name
        namedPlaceCoordinate = coordinate
        namedPlaceRadius = nameRadius
        withAnimation(.smooth(duration: 0.6)) {
            position = .region(.init(center: coordinate, span: span))
        }
    }

    private func syncExternalCenter() {
        let visible = CLLocation(latitude: lastVisibleCenter.latitude, longitude: lastVisibleCenter.longitude)
        let next = CLLocation(latitude: center.latitude, longitude: center.longitude)
        guard visible.distance(from: next) > 10 else { return }
        lastVisibleCenter = center
        withAnimation(.smooth(duration: 0.5)) {
            position = .region(.init(center: center, span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        }
    }
}

private struct MapFriendMarker: View {
    let observation: NatureObservation
    var compact = false

    var body: some View {
        Group {
            if compact {
                CompanionArtwork(observation: observation, size: 33)
                    .padding(3)
                    .background(observation.kind.color.opacity(0.22), in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: NRTheme.ink.opacity(0.2), radius: 3, y: 2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            } else {
                fullMarker
            }
        }
    }

    private var fullMarker: some View {
        VStack(spacing: -2) {
            CompanionArtwork(observation: observation, size: 54)
                .padding(7)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(observation.kind.color.opacity(0.6), lineWidth: 2))
                .shadow(color: NRTheme.ink.opacity(0.15), radius: 7, y: 4)
            Image(systemName: "triangle.fill")
                .font(.system(size: 12))
                .rotationEffect(.degrees(180))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            if observation.isSample {
                Text("DEMO")
                    .font(.system(size: 6, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(NRTheme.muted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(NRTheme.cream, in: Capsule())
                    .offset(x: 4, y: -4)
            } else if observation.isCommunity {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(NRTheme.green, in: Circle())
                    .offset(x: 4, y: -4)
            }
        }
    }
}

private struct PlaceSearchSheet: View {
    let center: CLLocationCoordinate2D
    let onSelect: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var activeSearch: MKLocalSearch?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Search for a campus, park, or city to explore nearby discoveries.")
                    .font(.system(size: 14))
                    .foregroundStyle(NRTheme.muted)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)

                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching places…").font(.system(size: 14))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                }

                if !results.isEmpty {
                    List(Array(results.enumerated()), id: \.offset) { _, item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 20))
                                    .foregroundStyle(NRTheme.green)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name ?? "Place")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(NRTheme.ink)
                                    Text(item.placemark.title ?? "")
                                        .font(.system(size: 12))
                                        .foregroundStyle(NRTheme.muted)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(NRTheme.green)
                            }
                            .padding(.vertical, 5)
                        }
                        .listRowBackground(Color.white)
                    }
                    .scrollContentBackground(.hidden)
                } else if !isSearching {
                    ContentUnavailableView {
                        Label(hasSearched ? "No places found" : "Where shall we explore?", systemImage: hasSearched ? "magnifyingglass" : "map")
                    } description: {
                        Text(searchError ?? (hasSearched ? "Try a campus, park, city, or street name." : "Search for your campus, a nearby park, or somewhere new."))
                    } actions: {
                        if !hasSearched {
                            Button("Find De Anza College") { query = "De Anza College" }
                                .buttonStyle(.borderedProminent)
                                .tint(NRTheme.green)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .background(NRTheme.cream)
            .navigationTitle("Find a place")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Campus, park, or address")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(NRTheme.green)
                }
            }
            .task(id: query) {
                activeSearch?.cancel()
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    results = []
                    hasSearched = false
                    isSearching = false
                    searchError = nil
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(400))
                    try Task.checkCancellation()
                    await searchPlaces()
                } catch { }
            }
            .onDisappear { activeSearch?.cancel() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func searchPlaces() async {
        isSearching = true
        searchError = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = .init(center: center, latitudinalMeters: 25_000, longitudinalMeters: 25_000)
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        activeSearch = search
        do {
            let response = try await search.start()
            guard !Task.isCancelled else { return }
            results = response.mapItems
            hasSearched = true
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            hasSearched = true
            isSearching = false
            searchError = "Search couldn't connect. Try again, or explore by moving the map."
        }
    }
}
