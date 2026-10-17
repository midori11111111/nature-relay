import SwiftUI
import CoreLocation
import MapKit

private struct CaptureRequest: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    var parent: NatureObservation? = nil
    var source: NatureObservation? = nil
}

@main
struct NatureRelayApp: App {
    @StateObject private var store = RelayStore()
    var body: some Scene {
        WindowGroup {
            RelayRootView().environmentObject(store).preferredColorScheme(.light)
        }
    }
}

struct RelayRootView: View {
    @EnvironmentObject private var store: RelayStore
    @StateObject private var community = CommunityStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var publishSelection: NatureObservation?
    @State private var feedVersion = UUID()
    @State private var showPeople = false
    @State private var tab = 0
    @State private var selected: NatureObservation?
    @State private var captureRequest: CaptureRequest?
    @State private var center = NRTheme.campus
    @State private var mapSpan = MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    @State private var showAbout = false
    var body: some View {
        ZStack {
            NRTheme.cream.ignoresSafeArea()
            Group {
                switch tab {
                case 0:
                    ExploreMapView(observations: mapObservations, selected: $selected, center: $center, mapSpan: $mapSpan, onCapture: { captureRequest = CaptureRequest(coordinate: center) }, onUseCommunityPhoto: { source in
                        captureRequest = CaptureRequest(coordinate: source.coordinate, source: source)
                    })
                case 1:
                    CommunityFeedView(store: community, observations: store.displayObservations, onSelectArchive: { selected = $0 }).id(feedVersion)
                default:
                    NatureCollectionView(observations: store.collected, onSelect: { selected = $0 })
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        .task {
            #if DEBUG
            DeviceVerification.runIfRequested(store: store)
            #endif
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await community.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard !Task.isCancelled else { return }
                if tab == 0 { await community.refresh() }
            }
        }
        .sheet(item: $publishSelection) { entry in
            PublishObservationView(observation: entry, store: community) { post in
                publishSelection = nil
                feedVersion = UUID()
                tab = 1
            }
        }
        .sheet(item: $captureRequest) { request in
            CaptureView(initialCoordinate: request.coordinate, parentObservation: request.parent, sourceObservation: request.source) { observation in
                center = observation.coordinate
                mapSpan = .init(latitudeDelta: 0.006, longitudeDelta: 0.006)
                tab = 0
                captureRequest = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    selected = observation
                }
            }.environmentObject(store).environmentObject(community)
        }
        .sheet(item: $selected) { entry in
            if let sharedID = entry.sharedPostID, let post = community.posts.first(where: { $0.id == sharedID }) {
                CommunityPostDetailView(post: post, store: community)
            } else {
            let current = store.observations.first { $0.id == entry.id } ?? entry
            ObservationDetailView(observation: current, story: store.story(for: current), onLike: { store.toggleLike(entry.id) }, onCollect: { store.toggleCollection(entry.id) }, onFollow: { store.toggleFollow(entry.id) }, onAddPhoto: {
                center = current.coordinate
                selected = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    captureRequest = CaptureRequest(coordinate: current.coordinate, parent: current)
                }
            }, onPublish: {
                selected = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    publishSelection = current
                }
            })
            .presentationDragIndicator(.visible)
            }
        }
        .alert("Journal storage", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button("OK") { store.storageError = nil }
        } message: { Text(store.storageError ?? "") }
    }
    private var mapObservations: [NatureObservation] {
        let remote = community.posts.compactMap(\.mapObservation)
        let publishedIDs = Set(community.posts.filter { $0.author.id == community.user?.id }.compactMap(\.clientObservationID).map { $0.lowercased() })
        return store.displayObservations.filter { !publishedIDs.contains($0.id.uuidString.lowercased()) } + remote
    }
    private var navigationBar: some View {
        HStack(spacing: 0) {
            navItem("Explore", icon: "map", value: 0)
            navItem("Discover", icon: "rectangle.stack", value: 1)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                captureRequest = CaptureRequest(coordinate: center)
            } label: {
                Image(systemName: "camera.fill").font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(NRTheme.ink).frame(width: 58, height: 58)
                    .background(NRTheme.lime, in: Circle())
                    .overlay(Circle().stroke(NRTheme.ink.opacity(0.09), lineWidth: 1))
            }.accessibilityLabel("Discover with a photo").frame(maxWidth: .infinity)
            navItem("Journal", icon: "square.grid.2x2", value: 2)
            Button { showAbout = true } label: {
                VStack(spacing: 5) {
                    Text("TA").font(.system(size: 12, weight: .bold, design: .rounded)).frame(width: 25, height: 25).background(NRTheme.ink.opacity(0.08), in: Circle())
                    Text("You").font(.system(size: 10, weight: .semibold))
                }.foregroundStyle(NRTheme.muted).frame(maxWidth: .infinity)
            }.accessibilityLabel("Your field profile")
        }
        .padding(.horizontal, 9).padding(.top, 10).padding(.bottom, 4)
        .background(NRTheme.cream.ignoresSafeArea(edges: .bottom).shadow(color: .black.opacity(0.06), radius: 12, y: -3))
        .sheet(isPresented: $showAbout) { profile }
    }
    private func navItem(_ text: String, icon: String, value: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { tab = value } } label: {
            VStack(spacing: 6) {
                Image(systemName: icon + (tab == value ? ".fill" : "")).font(.system(size: 20, weight: .medium))
                Text(text).font(.system(size: 10, weight: .semibold))
            }.foregroundStyle(tab == value ? NRTheme.ink : NRTheme.muted).frame(maxWidth: .infinity).frame(height: 54)
        }.accessibilityLabel(text)
    }
    private var profile: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Your campus.\nYour discoveries.").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(NRTheme.ink)
                    HStack { Label("\(store.personalCount) discoveries", systemImage: "camera.macro"); Spacer(); Label("\(store.collected.count) collected", systemImage: "square.grid.2x2") }.font(.subheadline.weight(.semibold))
                    Text("Nature Relay").font(.title2.bold())
                    Text("Turn the nature around you into a world of little characters. Photograph a plant or animal, meet your illustrated companion, and leave a discovery on the map.").foregroundStyle(NRTheme.muted)
                    Button { showPeople = true } label: {
                        Label(community.user.map { "Community profile · " + $0.nickname } ?? "Set up your community profile", systemImage: "person.2")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text("Your journal stays on this iPhone. Publish a discovery to share it with other devices; comments and people you follow are stored by the community service. Shared locations are rounded to an approximate area, and photo metadata is removed.").font(.footnote).foregroundStyle(NRTheme.muted)
                    Text("Choose a plant name yourself, or request candidate matches from Pl@ntNet when connected. Confirm the result before saving. A character is an illustration, not evidence of a species.").font(.footnote).foregroundStyle(NRTheme.muted)
                    Link("Plant identification powered by Pl@ntNet", destination: URL(string: "https://plantnet.org/")!).font(.footnote)
                    Text("The A collection has \(SpeciesACollection.records.count) individually designed species companions. Their flower shapes, leaves, plumage and wing patterns are inspired by each species. These pre-generated AI illustrations stay available offline and do not identify a plant or animal.").font(.footnote).foregroundStyle(NRTheme.muted)
                    Text("Unknown categories can use the earlier type illustrations, including adapted Twemoji artwork by Twitter, Inc. and contributors under CC BY 4.0. Artwork credits are shown in each discovery.").font(.footnote).foregroundStyle(NRTheme.muted)
                    Link("Twemoji artwork · CC BY 4.0", destination: URL(string: "https://github.com/jdecked/twemoji/blob/main/LICENSE-GRAPHICS")!).font(.footnote)
                    Text("Optional AI illustration sends a resized photo without GPS to Hugging Face / Black Forest Labs; their cache may be public. Shared free quotas can run out. No paid fallback is enabled.").font(.footnote).foregroundStyle(NRTheme.muted)
                    Link("Inspired by discovering the real world", destination: URL(string: "https://www.pokemon.com/us/pokemon-video-games/pokemon-go/")!).font(.footnote)
                }.padding(26)
            }.background(NRTheme.cream).navigationTitle("Field profile").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
        }.tint(NRTheme.green)
        .sheet(isPresented: $showPeople) { CommunityPeopleView(store: community) }
    }
}
