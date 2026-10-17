import SwiftUI

struct ObservationImage: View {
    let name: String?
    var contentMode: ContentMode = .fill
    var remoteURL: String? = nil

    var body: some View {
        if let name, let image = Self.load(name) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else if let remoteURL, let url = URL(string: remoteURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                case .empty:
                    Rectangle().fill(NRTheme.cream)
                        .overlay(ProgressView().tint(NRTheme.green))
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle().fill(NRTheme.cream)
            .overlay(Image(systemName: "photo").font(.system(size: 28, weight: .light)).foregroundStyle(NRTheme.muted))
    }

    static func load(_ name: String) -> UIImage? {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NatureRelayMedia").appendingPathComponent(name)
        return UIImage(contentsOfFile: file.path)
    }
}

private struct CompanionImage: View {
    let observation: NatureObservation
    var size: CGFloat
    var body: some View {
        CompanionArtwork(observation: observation, size: size)
    }
}

private struct SampleTag: View {
    var body: some View {
        Text("DEMO").font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(1).padding(.horizontal, 7).padding(.vertical, 4)
            .background(NRTheme.ink.opacity(0.07), in: Capsule())
    }
}

private struct CommunityTag: View {
    let observation: NatureObservation
    var body: some View {
        Text(sourceArchiveLabel(for: observation)).font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(NRTheme.cream, in: Capsule()).foregroundStyle(NRTheme.green)
    }
}

private func sourceArchiveLabel(for observation: NatureObservation) -> String {
    let host = observation.sourceURL.flatMap(URL.init(string:))?.host?.lowercased() ?? ""
    return host == "inaturalist.org" || host.hasSuffix(".inaturalist.org") ? "iNaturalist" : "Source"
}

struct RelayFeedView: View {
    let observations: [NatureObservation]
    let onSelect: (NatureObservation) -> Void
    let onLike: (UUID) -> Void
    @State private var followingOnly = false
    private var visibleObservations: [NatureObservation] {
        followingOnly ? observations.filter(\.followed) : observations
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("NATURE RELAY").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(NRTheme.muted)
                        Text("Nature discoveries").font(.system(size: 31, weight: .semibold, design: .serif)).tracking(-0.7)
                        Text("Find a place to revisit. Add your own photo to its story.")
                            .font(.system(size: 14)).foregroundStyle(NRTheme.muted).lineSpacing(4)
                    }
                    Spacer()
                    Image(systemName: "leaf").font(.system(size: 24, weight: .light)).rotationEffect(.degrees(-20)).padding(13)
                        .background(NRTheme.lime, in: Circle()).padding(.top, 21)
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

                HStack(spacing: 7) {
                    Circle().fill(NRTheme.green).frame(width: 5, height: 5)
                    Text("PHOTOS & FIELD NOTES").tracking(1.1)
                    Spacer()
                    Text("\(visibleObservations.count) observations")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(NRTheme.muted)
                .padding(.horizontal, 24).padding(.bottom, 18)

                HStack(spacing: 24) {
                    feedFilter("All discoveries", selected: !followingOnly) { followingOnly = false }
                    feedFilter("Following", selected: followingOnly) { followingOnly = true }
                    Spacer()
                }.padding(.horizontal, 24).padding(.bottom, 22)

                if followingOnly && visibleObservations.isEmpty {
                    VStack(spacing: 14) {
                        NatureCharacter(kind: .bird, size: 150)
                        Text("Follow a place’s story.").font(.system(size: 22, design: .serif))
                        Text("Open a discovery and tap Follow story. Its photos will appear here. Following is saved on this device.")
                            .font(.system(size: 14)).foregroundStyle(NRTheme.muted).multilineTextAlignment(.center)
                        Button("Explore all discoveries") { followingOnly = false }
                            .font(.system(size: 13, weight: .semibold)).padding(.top, 5)
                    }.frame(maxWidth: .infinity).padding(30)
                } else if observations.isEmpty {
                    emptyJournal
                } else {
                    LazyVStack(spacing: 26) {
                        ForEach(visibleObservations) { observation in
                            FeedObservationRow(observation: observation, onSelect: { onSelect(observation) }, onLike: { onLike(observation.id) })
                        }
                    }
                }
                Text("Archive sightings and your own photos. Saved and followed discoveries stay on this device.")
                    .font(.system(size: 12)).foregroundStyle(NRTheme.muted).multilineTextAlignment(.center).lineSpacing(4)
                    .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 30)
            }
        }
        .background(NRTheme.cream).foregroundStyle(NRTheme.ink)
    }

    private func feedFilter(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Text(label).font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? NRTheme.ink : NRTheme.muted)
                Rectangle().fill(selected ? NRTheme.green : .clear).frame(height: 2)
            }.fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyJournal: some View {
        VStack(spacing: 14) {
            NatureCharacter(kind: .plant, size: 155)
            Text("Your campus story starts here.").font(.system(size: 22, design: .serif))
            Text("Photograph a plant or animal to add the first discovery.")
                .font(.system(size: 14)).foregroundStyle(NRTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(30)
    }
}

private struct FeedObservationRow: View {
    let observation: NatureObservation
    let onSelect: () -> Void
    let onLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(String(observation.author.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32)
                    .background(NRTheme.green.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(observation.author).font(.system(size: 13, weight: .semibold))
                    Text(observation.locationLabel).font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                    Text("Observed \(observation.observationDayLabel)")
                        .font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                }
                Spacer()
                if observation.isSample { SampleTag() }
                if observation.isCommunity { CommunityTag(observation: observation) }
            }.padding(.horizontal, 24)

            Button(action: onSelect) {
                GeometryReader { geometry in
                    ZStack {
                        Rectangle().fill(observation.kind.color.opacity(0.24))
                        if observation.originalImageName != nil || observation.sourcePhotoURL != nil {
                            ObservationImage(name: observation.originalImageName, remoteURL: observation.sourcePhotoURL)
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        } else {
                            CompanionImage(observation: observation, size: 220)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if observation.originalImageName != nil || observation.sourcePhotoURL != nil {
                            CompanionImage(observation: observation, size: 105)
                                .padding(7).background(NRTheme.cream, in: RoundedRectangle(cornerRadius: 9)).padding(15)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(observation.isSample ? "Demo illustration" : observation.companionImageName != nil || SpeciesCharacterCatalog.assetInfo(for: observation).isAIGenerated ? "Photo + AI companion" : observation.isCommunity ? "Photo + companion" : observation.originalImageName != nil ? "Photo + companion" : "Category illustration")
                            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7)
                            .background(NRTheme.cream, in: Capsule()).padding(15)
                    }
                }.frame(height: 260)
            }.buttonStyle(.plain)

            HStack(alignment: .top) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(observation.commonName ?? observation.name).font(.system(size: 25, weight: .medium, design: .serif)).tracking(-0.5)
                        Text(observation.note).font(.system(size: 13)).lineSpacing(3).foregroundStyle(NRTheme.muted).lineLimit(2)
                    }.multilineTextAlignment(.leading)
                }.buttonStyle(.plain)
                Spacer(minLength: 12)
                Button(action: onLike) {
                    Image(systemName: observation.liked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .light)).foregroundStyle(observation.liked ? Color(red: 0.85, green: 0.36, blue: 0.36) : NRTheme.ink)
                        .frame(width: 40, height: 40)
                }.accessibilityLabel(observation.liked ? "Remove from favorites on this device" : "Favorite on this device")
            }.padding(.horizontal, 24)
            Rectangle().fill(NRTheme.ink.opacity(0.10)).frame(height: 0.5).padding(.horizontal, 24)
        }
    }
}

struct NatureCollectionView: View {
    let observations: [NatureObservation]
    let onSelect: (NatureObservation) -> Void
    private var collected: [NatureObservation] { observations.filter(\.collected) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("YOUR FIELD NOTES").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(NRTheme.muted)
                        Text("Saved discoveries").font(.system(size: 31, weight: .semibold, design: .serif)).tracking(-1)
                    }
                    Spacer()
                    Text(String(format: "%02d", collected.count)).font(.system(size: 48, weight: .light, design: .serif)).foregroundStyle(NRTheme.green).padding(.top, 22)
                }
                Text("Your photos and saved archive discoveries, kept on this device. Open a discovery and tap Save to Journal.")
                    .font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(4)

                if collected.isEmpty {
                    VStack(spacing: 8) {
                        NatureCharacter(kind: .bird, size: 180)
                        Text("Your first discovery belongs here.").font(.system(size: 20, design: .serif))
                        Text("Open a discovery and tap Save to Journal.").font(.system(size: 13)).foregroundStyle(NRTheme.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 24) {
                        ForEach(Array(collected.enumerated()), id: \.element.id) { index, observation in
                            Button { onSelect(observation) } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    GeometryReader { geometry in
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 5).fill(observation.kind.color.opacity(0.18))
                                            if observation.companionImageName == nil && !SpeciesCharacterCatalog.assetInfo(for: observation).isAIGenerated && (observation.originalImageName != nil || observation.sourcePhotoURL != nil) {
                                                ObservationImage(name: observation.originalImageName, remoteURL: observation.sourcePhotoURL)
                                                    .frame(width: geometry.size.width, height: 170).clipped()
                                            } else {
                                                CompanionImage(observation: observation, size: 143)
                                            }
                                        }
                                        .frame(width: geometry.size.width, height: 170).clipped()
                                        .overlay(alignment: .topLeading) {
                                            Text(String(format: "%02d", index + 1))
                                                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(NRTheme.ink)
                                                .padding(6).background(NRTheme.cream, in: Capsule()).padding(9)
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            if observation.isSample { SampleTag().padding(9) }
                                            if observation.isCommunity { CommunityTag(observation: observation).padding(9) }
                                        }
                                    }.frame(height: 170)
                                    Text(observation.commonName ?? observation.name).font(.system(size: 18, weight: .medium, design: .serif)).lineLimit(1)
                                    Text(observation.kind.title.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(NRTheme.muted)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(24).padding(.bottom, 25)
        }.background(NRTheme.cream).foregroundStyle(NRTheme.ink)
    }
}

struct ObservationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let observation: NatureObservation
    var story: [NatureObservation] = []
    let onLike: () -> Void
    let onCollect: () -> Void
    let onFollow: () -> Void
    let onAddPhoto: () -> Void
    var onPublish: (() -> Void)? = nil

    private var isArchive: Bool { observation.isSourceArchive == true || observation.isCommunity }
    private var hasOriginalPhoto: Bool { observation.originalImageName != nil || observation.sourcePhotoURL != nil }
    private var storyRecords: [NatureObservation] {
        (story.isEmpty ? [observation] : story).sorted { $0.observedAt > $1.observedAt }
    }

    private func shouldShowNote(_ note: String) -> Bool {
        !note.isEmpty && note != "A recorded discovery from California. The map shows an approximate area; the organism may no longer be there."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                discoveryHero
                VStack(alignment: .leading, spacing: 24) {
                    identity
                    fieldRecord
                    if shouldShowNote(observation.note) {
                        Text(observation.note).font(.system(size: 15)).foregroundStyle(NRTheme.muted).lineSpacing(5)
                    }
                    localActions
                    Divider().overlay(NRTheme.ink.opacity(0.1))
                    sourceDetails
                    if let label = observation.visionLabel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested label: \(label)").font(.system(size: 14, weight: .semibold))
                            Text("An on-device visual suggestion, not a verified species identification.")
                                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                            if let confidence = observation.confidence {
                                Text("Model confidence \(Int(confidence * 100))%")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(NRTheme.muted)
                            }
                        }
                    }
                    Divider().overlay(NRTheme.ink.opacity(0.1))
                    placeStory
                }.padding(.horizontal, 24).padding(.bottom, 35)
            }
        }.background(NRTheme.cream).foregroundStyle(NRTheme.ink)
    }

    private var discoveryHero: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(observation.kind.color.opacity(0.23))
                if hasOriginalPhoto {
                    ObservationImage(name: observation.originalImageName, remoteURL: observation.sourcePhotoURL)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    CompanionImage(observation: observation, size: 250)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .overlay(alignment: .topLeading) {
                Text(observation.isSample ? "DEMO ILLUSTRATION" : hasOriginalPhoto ? "ORIGINAL PHOTO" : "CATEGORY ILLUSTRATION")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                    .padding(.horizontal, 11).padding(.vertical, 8).background(NRTheme.cream, in: Capsule()).padding(20)
            }
            .overlay(alignment: .bottomTrailing) {
                if hasOriginalPhoto {
                    VStack(spacing: 5) {
                        CompanionImage(observation: observation, size: 100)
                        Text(observation.companionImageName != nil || SpeciesCharacterCatalog.assetInfo(for: observation).isAIGenerated ? "AI companion" : "Companion").font(.system(size: 10, weight: .medium))
                    }.padding(9).background(NRTheme.cream, in: RoundedRectangle(cornerRadius: 10)).padding(20)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 36).background(NRTheme.cream, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Close discovery details").padding(18)
            }
        }.frame(height: 290)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DISCOVERY DETAILS").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(NRTheme.muted)
                Text(observation.commonName ?? observation.name)
                    .font(.system(size: 32, weight: .medium, design: .serif)).tracking(-0.7).fixedSize(horizontal: false, vertical: true)
                if let scientificName = observation.scientificName, scientificName != (observation.commonName ?? observation.name) {
                    Text(scientificName).font(.system(size: 15, design: .serif)).italic().foregroundStyle(NRTheme.muted)
                }
                if observation.isSample { SampleTag() }
            }
            Spacer(minLength: 0)
            Button(action: onLike) {
                Image(systemName: observation.liked ? "heart.fill" : "heart").font(.system(size: 21, weight: .light))
                    .foregroundStyle(observation.liked ? Color(red: 0.85, green: 0.36, blue: 0.36) : NRTheme.ink)
                    .frame(width: 44, height: 44).background(.white, in: Circle())
            }.accessibilityLabel(observation.liked ? "Remove from favorites on this device" : "Favorite on this device")
        }
    }

    private var fieldRecord: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let method = observation.identificationMethod {
                recordLine("leaf", title: "Plant name", value: method)
            }
            recordLine("calendar", title: "Observed", value: observation.observationDayLabel)
            recordLine("person", title: "Observer", value: observation.author)
            recordLine("mappin", title: observation.isSample ? "Demo place" : "Approximate place", value: observation.locationLabel)
            if observation.isSourceArchive != true, let source = observation.locationSource {
                Text(source).font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
            }
            if !observation.isSample, let url = mapsURL {
                Link(destination: url) {
                    Label("Open recorded area in Maps", systemImage: "map")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }.tint(NRTheme.green)
            }
            Text(locationContext).font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(4)
        }
    }

    private func recordLine(_ icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(NRTheme.green).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(NRTheme.muted)
                Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var localActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onCollect) {
                    Label(observation.collected ? "Saved to Journal" : "Save to Journal", systemImage: observation.collected ? "checkmark" : "bookmark")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(NRTheme.ink, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                }
                Button(action: onFollow) {
                    Label(observation.followed ? "Following story" : "Follow story", systemImage: observation.followed ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(NRTheme.lime, in: RoundedRectangle(cornerRadius: 10))
                }
            }.buttonStyle(.plain)
            if let onPublish, !observation.isSample {
                Button(action: onPublish) {
                    Label(isArchive ? "Share this archive discovery" : "Publish to the community", systemImage: "person.2")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NRTheme.green.opacity(0.25)))
                }.buttonStyle(.plain).accessibilityIdentifier("discovery.publish")
            }
            Text("Save keeps this discovery in your Journal. Follow groups this story’s photos in Following. Both are saved on this device.")
                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(4)
        }
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("PHOTO & SOURCE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.4)
                Spacer()
                shareAction
            }
            Text(companionDescription).font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(4)
            if observation.companionImageName == nil {
                let asset = SpeciesCharacterCatalog.assetInfo(for: observation)
                if let url = URL(string: asset.sourceURL), url.scheme == "https" {
                    Link("Character: \(asset.credit) · \(asset.licenseName)", destination: url)
                        .font(.system(size: 11)).tint(NRTheme.green)
                } else {
                    Text("Character: \(asset.credit) · \(asset.licenseName)").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                }
                Text(asset.matchDescription).font(.system(size: 11)).foregroundStyle(NRTheme.muted)
            }
            if isArchive {
                Text("\(sourceArchiveLabel(for: observation)) archive").font(.system(size: 14, weight: .semibold))
                Text("A recorded sighting from \(observation.observationDayLabel). The observer and original photo remain credited to their source.")
                    .font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(4)
            }
            if let attribution = observation.sourceAttribution {
                Text(attribution).font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(4).textSelection(.enabled)
            }
            if let license = observation.photoLicense {
                if let licenseURL = observation.photoLicenseURL, let url = URL(string: licenseURL) {
                    Link("Photo license: \(license)", destination: url).font(.system(size: 13)).tint(NRTheme.green)
                } else {
                    Text("Photo license: \(license)").font(.system(size: 12)).foregroundStyle(NRTheme.muted)
                }
            }
            if let source = observation.sourceURL, let url = URL(string: source) {
                Link(destination: url) {
                    Label("View original observation", systemImage: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                }.tint(NRTheme.green)
            }
        }
    }

    private var placeStory: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PHOTO HISTORY AT THIS PLACE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2)
            Text("Share a find with a friend, visit its recorded area, then add your own photo to continue the story.")
                .font(.system(size: 15, design: .serif)).lineSpacing(4)
            Text("\(storyRecords.count) \(storyRecords.count == 1 ? "photo record" : "photo records") · newest first")
                .font(.system(size: 12)).foregroundStyle(NRTheme.muted)
            ForEach(storyRecords) { record in storyMoment(record) }
            Button(action: onAddPhoto) {
                Label("Add my photo at this place", systemImage: "camera")
                    .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NRTheme.ink.opacity(0.25), lineWidth: 1))
            }.buttonStyle(.plain)
            Text("Your new photo joins this story in your journal. Publish it to the community to share it with friends; private journal entries stay on this device.")
                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(4)
        }
    }

    private var mapsURL: URL? {
        guard observation.latitude.isFinite, observation.longitude.isFinite,
              (-90...90).contains(observation.latitude), (-180...180).contains(observation.longitude) else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(observation.latitude),\(observation.longitude)"),
            URLQueryItem(name: "q", value: "\(observation.commonName ?? observation.name) · recorded area"),
            URLQueryItem(name: "z", value: "15")
        ]
        return components?.url
    }

    private var locationContext: String {
        if observation.isSample { return "A demo location, provided to show how a place story works." }
        let accuracy = observation.coordinateAccuracyMeters.flatMap { value -> String? in
            guard value.isFinite, value > 0 else { return nil }
            return "Recorded accuracy: about \(Int(value.rounded())) m. "
        } ?? ""
        return accuracy + (isArchive
            ? "This is an archival location, not the organism’s current location. The map opens its recorded area."
            : "The map opens the place recorded for this photo, not a live location.")
    }

    private func storyMoment(_ record: NatureObservation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Circle().fill(NRTheme.green).frame(width: 7, height: 7)
                Rectangle().fill(NRTheme.green.opacity(0.18)).frame(width: 1).frame(minHeight: 78)
            }.frame(width: 9).padding(.top, 7)
            VStack(alignment: .leading, spacing: 10) {
                Text(record.observationDayLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(NRTheme.muted)
                Text(record.isSample ? "Demo observation · \(record.author)" : "Observed by \(record.author)")
                    .font(.system(size: 14, weight: .medium))
                HStack(alignment: .top, spacing: 12) {
                    if record.originalImageName != nil || record.sourcePhotoURL != nil {
                        ObservationImage(name: record.originalImageName, remoteURL: record.sourcePhotoURL)
                            .frame(width: 74, height: 86).clipped()
                    } else {
                        CompanionArtwork(observation: record, size: 74)
                            .frame(width: 74, height: 86).background(record.kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.commonName ?? record.name).font(.system(size: 14, weight: .medium))
                        if shouldShowNote(record.note) {
                            Text(record.note).font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(3).lineLimit(4)
                        }
                        if let attribution = record.sourceAttribution {
                            Text(attribution).font(.system(size: 11)).foregroundStyle(NRTheme.muted).lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }.padding(.vertical, 5)
    }

    private var shareCaption: String {
        var lines = ["\(observation.commonName ?? observation.name) · Nature Relay", "Observed \(observation.observationDayLabel) by \(observation.author)", "Recorded area: \(observation.locationLabel)"]
        if !observation.note.isEmpty { lines.append(observation.note) }
        if isArchive { lines.append("Archive sighting, not a live location.") }
        if observation.companionImageName != nil { lines.append("AI-generated companion illustration; not a species identification.") }
        let asset = SpeciesCharacterCatalog.assetInfo(for: observation)
        if observation.companionImageName == nil { lines.append("Character: \(asset.credit), \(asset.licenseName). \(asset.sourceURL)") }
        if let attribution = observation.sourceAttribution { lines.append("Original photo: \(attribution)") }
        if let license = observation.photoLicense { lines.append("Photo license: \(license)") }
        if let licenseURL = observation.photoLicenseURL { lines.append(licenseURL) }
        if let provider = observation.aiProvider { lines.append("Illustration generated with \(provider)\(observation.aiModel.map { " · " + $0 } ?? "").") }
        if let source = observation.sourceURL { lines.append(source) }
        return lines.joined(separator: "\n")
    }

    private var companionDescription: String {
        if observation.companionImageName != nil {
            return "The small AI companion is artwork inspired by the original photo.\(observation.aiProvider.map { " Created with " + $0 + "." } ?? "") It is not a species identification."
        }
        let asset = SpeciesCharacterCatalog.assetInfo(for: observation)
        if asset.isAIGenerated {
            return "An AI-generated character designed for this species in the Nature Relay collection. It keeps distinguishing shapes and colors; the original photo remains the field record. It does not identify the species."
        }
        return asset.isSpeciesSpecific
            ? "A species-inspired illustrated companion. The original photograph remains the record of the real organism."
            : "A playful \(observation.kind.title.lowercased()) companion. This illustration represents a broad type; it does not establish the species."
    }

    @ViewBuilder private var shareAction: some View {
        if let renderedImage = companionShareImage {
            let image = Image(uiImage: renderedImage)
            ShareLink(item: image, message: Text(shareCaption), preview: SharePreview(observation.commonName ?? observation.name, image: image)) {
                Label("Share", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
            }.accessibilityLabel("Share this discovery, photo and source credit")
        } else {
            ShareLink(item: shareCaption) {
                Label("Share", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
            }.accessibilityLabel("Share this discovery and source credit")
        }
    }

    @MainActor private var companionShareImage: UIImage? {
        if hasOriginalPhoto && observation.originalImageName.flatMap({ ObservationImage.load($0) }) == nil && observation.companionImageName == nil { return nil }
        let renderer = ImageRenderer(content: CompanionShareCard(observation: observation))
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct CompanionShareCard: View {
    let observation: NatureObservation
    private var hasOriginalPhoto: Bool { observation.originalImageName != nil || observation.sourcePhotoURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("NATURE RELAY").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                Spacer()
                Image(systemName: "leaf").font(.system(size: 15))
            }
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(observation.kind.color.opacity(0.22))
                if hasOriginalPhoto, let name = observation.originalImageName, let original = ObservationImage.load(name) {
                    Image(uiImage: original).resizable().scaledToFill().frame(width: 310, height: 240).clipped()
                } else {
                    CompanionArtwork(observation: observation, size: 225).frame(maxWidth: .infinity)
                }
                if hasOriginalPhoto {
                    CompanionArtwork(observation: observation, size: 85).padding(6)
                        .background(NRTheme.cream, in: RoundedRectangle(cornerRadius: 8)).padding(12)
                }
            }.frame(width: 310, height: 240).clipped()
            Text(observation.commonName ?? observation.name)
                .font(.system(size: 28, weight: .medium, design: .serif)).tracking(-0.6).fixedSize(horizontal: false, vertical: true)
            if let scientificName = observation.scientificName, scientificName != (observation.commonName ?? observation.name) {
                Text(scientificName).font(.system(size: 14, design: .serif)).italic().foregroundStyle(NRTheme.muted)
            }
            Rectangle().fill(NRTheme.ink.opacity(0.14)).frame(height: 0.5).padding(.vertical, 1)
            Text("Observed \(observation.observationDayLabel)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(NRTheme.muted)
            Text("By \(observation.author) · \(observation.locationLabel)")
                .font(.system(size: 12)).foregroundStyle(NRTheme.muted).fixedSize(horizontal: false, vertical: true)
            if observation.isSample {
                Text("Demo illustration and location").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
            } else if observation.isSourceArchive == true || observation.isCommunity {
                Text("\(sourceArchiveLabel(for: observation)) archive · recorded area, not a live location")
                    .font(.system(size: 11)).foregroundStyle(NRTheme.muted)
            }
            if let attribution = observation.sourceAttribution {
                Text("Original photo: \(attribution)")
                    .font(.system(size: 10)).foregroundStyle(NRTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let license = observation.photoLicense {
                Text("Photo license: \(license)").font(.system(size: 10)).foregroundStyle(NRTheme.muted)
            }
            if observation.companionImageName == nil {
                let asset = SpeciesCharacterCatalog.assetInfo(for: observation)
                Text("Character: \(asset.credit) · \(asset.licenseName)").font(.system(size: 9)).foregroundStyle(NRTheme.muted)
            }
            if observation.companionImageName != nil {
                Text("AI companion illustration\(observation.aiProvider.map { " · " + $0 } ?? "")")
                    .font(.system(size: 10)).foregroundStyle(NRTheme.muted)
            }
        }
        .padding(25).frame(width: 360).background(NRTheme.cream).foregroundStyle(NRTheme.ink)
    }
}
