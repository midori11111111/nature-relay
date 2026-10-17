import SwiftUI
import PhotosUI
import MapKit
import UIKit

private struct NatureCameraRequest: Identifiable {
    let id = UUID()
    var fixture: UIImage? = nil
}

struct CaptureView: View {
    private static let poppyDesignNote = "Poppy-inspired character design from the public Unsplash sample. Created in advance with the built-in image tool; no new API request or verified species identification. Not a campus sighting."
    private static let liveSampleNote = "Live-scan design sample. Photo © Annette Herz (CC BY), https://www.inaturalist.org/observations/108094155 . Character artwork was generated in advance. This is not a campus sighting or a new species identification."
    @EnvironmentObject private var store: RelayStore
    @EnvironmentObject private var community: CommunityStore
    @Environment(\.dismiss) private var dismiss
    let initialCoordinate: CLLocationCoordinate2D
    let parentObservation: NatureObservation?
    let onSaved: (NatureObservation) -> Void
    @State private var photoItem: PhotosPickerItem?
    @State private var importTask: Task<Void, Never>?
    @State private var selectionID = UUID()
    @State private var selectedPhotoIdentifier: String?
    @State private var locationResolved = false
    @State private var isReadingPhotoLocation = false
    @State private var photoLocationError: String?
    @State private var image: UIImage?
    @State private var recognition: RecognitionResult?
    @State private var isAnalyzing = false
    @State private var cameraRequest: NatureCameraRequest?
    @State private var showLocation = false
    @State private var error: String?
    @State private var recognitionError: String?
    @State private var name = ""
    @State private var note = ""
    @State private var kind: NatureKind = .flower
    @State private var coordinate: CLLocationCoordinate2D
    @State private var observedAt = Date()
    @State private var locationSource = "Selected map location"
    @State private var isSaving = false
    @State private var isSamplePhoto = false
    @State private var samplePhotoCredit = "Flower photograph via Unsplash. This is a practice discovery, not an observation made on campus."
    @State private var publicSource: NatureObservation?
    @State private var sourceLoaded = false
    @State private var externalPhotoEnabled = false
    @State private var externalObserver = ""
    @State private var externalPhotoCredit = ""
    @State private var externalSourceURL = ""
    @State private var externalPhotoLicense = ""
    @State private var companion: GeneratedCompanion?
    @State private var generationTask: Task<Void, Never>?
    @State private var isGenerating = false
    @State private var generationStatus = ""
    @State private var generationError: String?
    @State private var isSavedAIExample = false
    @State private var commonName = ""
    @State private var scientificName = ""
    @State private var identificationMethod: String?
    @State private var showSpeciesPicker = false
    @State private var identificationTask: Task<Void, Never>?
    @State private var identificationRequestID = UUID()
    @State private var isIdentifying = false
    @State private var identificationCandidates: [PlantIdentificationCandidate] = []
    @State private var identificationError: String?
    @State private var remainingIdentificationRequests: Int?
    @State private var identificationAccountConnected: Bool?
    @State private var identificationConnectionError: String?
    @AppStorage("nature-relay-name") private var author = "Tomoki"
    init(initialCoordinate: CLLocationCoordinate2D, parentObservation: NatureObservation? = nil, sourceObservation: NatureObservation? = nil, onSaved: @escaping (NatureObservation) -> Void) {
        self.parentObservation = parentObservation
        self.initialCoordinate = initialCoordinate
        self.onSaved = onSaved
        _coordinate = State(initialValue: initialCoordinate)
        _kind = State(initialValue: parentObservation?.kind ?? .flower)
        _name = State(initialValue: parentObservation?.name ?? "")
        _publicSource = State(initialValue: sourceObservation)
        let linked = sourceObservation ?? parentObservation
        _commonName = State(initialValue: linked?.commonName ?? (sourceObservation?.name ?? ""))
        _scientificName = State(initialValue: linked?.scientificName ?? "")
        _identificationMethod = State(initialValue: linked?.identificationMethod ?? (sourceObservation == nil ? nil : "Name from the original iNaturalist record"))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    if isAnalyzing { analyzing }
                    else if image == nil { intro }
                    else { review }
                }.padding(24).padding(.bottom, 25)
            }
            .background(NRTheme.cream)
            .foregroundStyle(NRTheme.ink)
            .navigationTitle(image == nil ? "Add a discovery" : "Review your discovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if image != nil && !isAnalyzing && !isGenerating && !isReadingPhotoLocation { ToolbarItem(placement: .topBarTrailing) { Button("Retake") { reset() } } }
            }
            .tint(NRTheme.green)
            .onChange(of: kind) { previous, current in
                if name == previous.friendName { name = current.friendName }
                cancelIdentification(clearCandidates: true)
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                importTask?.cancel()
                generationTask?.cancel()
                cancelIdentification(clearCandidates: true)
                clearIdentity()
                clearExternalPhotoCredit()
                selectionID = UUID()
                let requestID = selectionID
                isAnalyzing = true
                isGenerating = false
                image = nil
                recognition = nil
                companion = nil
                selectedPhotoIdentifier = nil
                locationResolved = false
                photoLocationError = nil
                importTask = Task { await load(item, requestID: requestID) }
            }
            .fullScreenCover(item: $cameraRequest) { request in
                LiveNatureCameraView(fixtureImage: request.fixture,
                    speciesName: request.fixture == nil ? parentObservation?.name : "Poppy-inspired design · public sample",
                    characterImage: request.fixture == nil ? (store.image(named: parentObservation?.companionImageName) ?? parentObservation.flatMap { SpeciesCharacterCatalog.artwork(for: $0) }) : bundledPoppyArtwork,
                    fixtureCredit: request.fixture == nil ? nil : "Photo © Annette Herz · CC BY",
                    fixtureSourceURL: request.fixture == nil ? nil : URL(string: "https://www.inaturalist.org/observations/108094155"),
                    onCapture: { result in
                    let isFixture = request.fixture != nil
                    cameraRequest = nil
                    Task { @MainActor in
                        await analyze(result, data: result.jpegData(compressionQuality: 0.9), sample: isFixture)
                        if isFixture {
                            usePoppyDesignExample()
                            samplePhotoCredit = "Photo © Annette Herz (CC BY), from iNaturalist observation 108094155. This is a demo, not an observation made on campus."
                            note = Self.liveSampleNote
                        }
                    }
                }, onClose: { cameraRequest = nil })
            }
            .sheet(isPresented: $showSpeciesPicker) {
                CaptureSpeciesPicker(commonName: commonName, scientificName: scientificName, kind: kind) { choice in
                    cancelIdentification(clearCandidates: true)
                    kind = choice.kind
                    commonName = choice.commonName
                    scientificName = choice.scientificName
                    identificationMethod = "Chosen by photographer"
                    companion = nil
                    isSavedAIExample = false
                    generationError = nil
                    showSpeciesPicker = false
                }
            }
            .sheet(isPresented: $showLocation) {
                CaptureLocationPicker(coordinate: $coordinate) {
                    locationSource = "Location selected by you"
                    locationResolved = true
                    photoLocationError = nil
                    showLocation = false
                }
            }
            .alert("Couldn't complete that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .task {
                guard let source = publicSource, !sourceLoaded else { return }
                sourceLoaded = true
                isAnalyzing = true
                do {
                    let data = try await CampusSightingsAPI.downloadPhoto(for: source)
                    guard let photo = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    await analyze(photo, data: nil, sample: false)
                } catch {
                    isAnalyzing = false
                    self.error = "The public photo couldn't be loaded: \(error.localizedDescription)"
                }
            }
            .task { await checkIdentificationConnection() }
            .onDisappear {
                importTask?.cancel()
                generationTask?.cancel()
                cancelIdentification(clearCandidates: true)
                selectionID = UUID()
            }
        }
        .interactiveDismissDisabled(isSaving || isGenerating)
    }
    private var bundledPoppyArtwork: UIImage? {
        var poppy = NatureObservation(name: "California poppy", kind: .flower, note: "", author: "", latitude: 0, longitude: 0)
        poppy.commonName = "California poppy"
        poppy.scientificName = "Eschscholzia californica"
        return SpeciesCharacterCatalog.artwork(for: poppy, targetSize: 250)
    }
    private func usePoppyDesignExample() {
        guard let example = bundledPoppyArtwork else { return }
        kind = .flower
        name = NatureKind.flower.friendName
        companion = GeneratedCompanion(image: example, provider: "Nature Relay · built-in imagegen design example", model: "Pre-generated poppy companion", seed: nil, prompt: "Curated original soft poppy-inspired character, generated in advance with the built-in image tool.")
        isSavedAIExample = true
        note = Self.poppyDesignNote
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(parentObservation == nil ? "Turn a photo\ninto a companion." : "Add a photo to\n\(parentObservation!.name)’s story.")
                .font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-0.7)
            ZStack {
                if let artwork = SpeciesCharacterCatalog.artwork(for: introCharacter) {
                    Image(uiImage: artwork).resizable().scaledToFit().frame(width: 180, height: 180)
                }
                Text("Meet your species companion").font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8).background(.white, in: Capsule()).offset(y: 87)
            }.frame(maxWidth: .infinity).frame(height: 202)
            Text("Choose a plant or animal photo. Use its saved GPS, or choose where you took it.")
                .font(.system(size: 16)).foregroundStyle(NRTheme.muted).lineSpacing(5)
            VStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { cameraRequest = NatureCameraRequest() } label: { primaryLabel("Use camera", icon: "viewfinder") }.accessibilityIdentifier("capture.camera")
                }
                PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) {
                    primaryLabel("Choose a photo", icon: "photo.on.rectangle")
                }.accessibilityIdentifier("capture.library")
                if ProcessInfo.processInfo.arguments.contains("--sample-mode"), Bundle.main.url(forResource: "DemoFlower", withExtension: "jpg") != nil {
                    Button {
                        guard let url = Bundle.main.url(forResource: "LiveScanSample", withExtension: "jpg"), let photo = UIImage(contentsOfFile: url.path) else { return }
                        cameraRequest = NatureCameraRequest(fixture: photo)
                    } label: {
                        Label("Try the live-scan sample", systemImage: "viewfinder").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14).overlay(Capsule().stroke(NRTheme.green.opacity(0.25)))
                    }.accessibilityIdentifier("capture.liveSample")
                    Button {
                        guard let url = Bundle.main.url(forResource: "DemoFlower", withExtension: "jpg"), let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { error = "The sample photo could not be loaded."; return }
                        Task { await analyze(image, data: data, sample: true) }
                    } label: {
                        Label("Try a sample flower", systemImage: "camera.macro").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14).overlay(Capsule().stroke(NRTheme.green.opacity(0.25)))
                    }.accessibilityIdentifier("capture.sample")
                    if bundledPoppyArtwork != nil {
                        Button {
                            guard let url = Bundle.main.url(forResource: "DemoFlower", withExtension: "jpg"),
                                  let data = try? Data(contentsOf: url), let photo = UIImage(data: data) else { return }
                            Task { @MainActor in
                                await analyze(photo, data: data, sample: true)
                                usePoppyDesignExample()
                            }
                        } label: {
                            Label("Try the poppy art style", systemImage: "leaf").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.accessibilityIdentifier("capture.aiExample")
                    }
                }
            }.buttonStyle(.plain)
            Label("A companion is ready without an upload.", systemImage: "leaf").font(.system(size: 12)).foregroundStyle(NRTheme.muted)
            Text("Choose a name yourself, or request plant suggestions from Pl@ntNet and confirm a candidate. On-device photo labels suggest only a broad category.").font(.system(size: 11)).foregroundStyle(NRTheme.muted).lineSpacing(3)
            Link("Explore De Anza’s official plant gallery", destination: URL(string: "https://daweb2.deanza.edu/es/esa/gallery1.html")!)
                .font(.system(size: 12, weight: .medium))
        }
    }
    private var analyzing: some View {
        VStack(spacing: 26) {
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(height: 300).clipped().clipShape(RoundedRectangle(cornerRadius: 28)) }
            ProgressView().tint(NRTheme.green).scaleEffect(1.4)
            Text("Getting to know\nyour discovery.").font(.system(size: 28, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text("Reading the photo and looking for its subject…").font(.subheadline).foregroundStyle(NRTheme.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 12) {
                if let companion {
                    Image(uiImage: companion.image).resizable().scaledToFit().frame(height: 235)
                        .accessibilityLabel(isSavedAIExample ? "Pre-generated poppy design example" : "Your character created from this photo")
                        .overlay(alignment: .bottomTrailing) {
                            if let image {
                                Image(uiImage: PhotoRecognitionService.photoBadge(from: image)).resizable().scaledToFit()
                                    .frame(width: 74, height: 74).padding(5).background(.white, in: Circle())
                            }
                        }
                    Text("YOUR LITTLE COMPANION").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4)
                } else if let artwork = SpeciesCharacterCatalog.artwork(for: previewObservation) {
                    Image(uiImage: artwork).resizable().scaledToFit().frame(height: 235)
                        .accessibilityLabel(previewAssetInfo.title)
                        .overlay(alignment: .bottomTrailing) {
                            if let image {
                                Image(uiImage: PhotoRecognitionService.photoBadge(from: image)).resizable().scaledToFit()
                                    .frame(width: 74, height: 74).padding(5).background(.white, in: Circle())
                            }
                        }
                    Text("YOUR ILLUSTRATED COMPANION").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                    Text(previewAssetInfo.title).font(.subheadline.weight(.semibold))
                    Text(previewAssetInfo.isSpeciesSpecific ? "Pre-created artwork for your chosen species. Check the real photo for identification." : "A shared type character. Choose a species name below for its artwork.")
                        .font(.caption).foregroundStyle(NRTheme.muted).multilineTextAlignment(.center)
                    Text(previewAssetInfo.attribution).font(.system(size: 9)).foregroundStyle(NRTheme.muted).multilineTextAlignment(.center)
                }
            }.frame(maxWidth: .infinity).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 26))
            if let result = recognition, !isSavedAIExample {
                VStack(alignment: .leading, spacing: 7) {
                    Label("On-device image label: \(result.label)", systemImage: "viewfinder").font(.system(size: 15, weight: .semibold))
                    Text("Suggested category: \(result.kind.title) · image label confidence: \(Int(result.confidence * 100))%. Confirm the category and choose a species name yourself.").font(.system(size: 12)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                    Text("This label does not identify a species.").font(.system(size: 11, weight: .semibold)).foregroundStyle(NRTheme.muted)
                }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(NRTheme.lime.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("capture.recognition")
            }
            if let recognitionError {
                Text(recognitionError).font(.footnote).foregroundStyle(NRTheme.muted)
                Text("Choose a category and a name yourself to continue.").font(.footnote.weight(.semibold))
            }
            speciesControls
            if linkedIdentity == nil {
                externalPhotoControls
            }
            locationControls
            #if DEBUG
            DisclosureGroup("Optional AI illustration") { aiControls.padding(.top, 12) }
                .font(.system(size: 14, weight: .semibold)).tint(NRTheme.green)
            #endif
            if let source = publicSource {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Real photo from iNaturalist", systemImage: "photo.on.rectangle").font(.caption.weight(.semibold))
                    Text("Observed by \(source.author) on \(source.observedAt.formatted(date: .abbreviated, time: .omitted)). The original date, map position and photo credit will be kept.").font(.caption).lineSpacing(3)
                    if let credit = source.sourceAttribution { Text(credit).font(.caption2) }
                    if let link = source.sourceURL, let url = URL(string: link) { Link("View original record", destination: url).font(.caption.weight(.semibold)) }
                }.foregroundStyle(NRTheme.muted)
            }
            if isSamplePhoto {
                Label("Sample photo · choose a demo location", systemImage: "info.circle").font(.caption.weight(.semibold)).foregroundStyle(NRTheme.green)
                Text(samplePhotoCredit).font(.caption2).foregroundStyle(NRTheme.muted)
            }
            field("GIVE YOUR FRIEND A NAME") {
                TextField(kind.friendName, text: $name).font(.system(size: 24, weight: .bold, design: .rounded)).accessibilityIdentifier("capture.name")
            }
            field("WHAT DID YOU FIND?") {
                Picker("Category", selection: Binding(get: { kind }, set: { next in
                    if next != kind {
                        companion = nil; isSavedAIExample = false; generationError = nil
                        cancelIdentification(clearCandidates: true)
                        clearIdentity()
                    }
                    kind = next
                })) { ForEach(NatureKind.allCases) { item in Label(item.title, systemImage: item.symbol).tag(item) } }.pickerStyle(.menu).tint(NRTheme.green).disabled(isGenerating || linkedIdentity != nil).accessibilityIdentifier("capture.kind")
            }
            field("LEAVE A LITTLE STORY") {
                TextField("What caught your eye?", text: $note, axis: .vertical).lineLimit(2...4).font(.system(size: 16)).accessibilityIdentifier("capture.caption")
            }
            field(publicSource == nil && !externalPhotoEnabled ? "DISCOVERED BY" : "ORIGINAL OBSERVER") {
                if let source = publicSource { Text(source.author) }
                else if externalPhotoEnabled { Text(trimmed(externalObserver) ?? "Add the original observer in Photo source and credit.") }
                else { TextField("Your name", text: $author).textContentType(.givenName).accessibilityIdentifier("capture.author") }
            }
            field("OBSERVED ON") {
                if let source = publicSource { Text(source.observedAt.formatted(date: .long, time: .omitted)) }
                else if externalPhotoEnabled { Text(observedAt.formatted(date: .long, time: .omitted)) }
                else { DatePicker("Observed", selection: $observedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
            }
            Button(action: save) { primaryLabel(isSaving ? "Saving your discovery…" : !locationResolved ? "Choose a location to continue" : "Add to my world", icon: "plus.circle.fill") }
                .buttonStyle(.plain).disabled(isSaving || image == nil || isGenerating || isIdentifying || isReadingPhotoLocation).accessibilityIdentifier("capture.save")
            Text("Saved on this iPhone. You can share the discovery after saving.").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
        }
    }
    private var externalPhotoControls: some View {
        DisclosureGroup("Photo source and credit") {
            VStack(alignment: .leading, spacing: 15) {
                Toggle("This photo is from another source", isOn: $externalPhotoEnabled)
                    .font(.subheadline).accessibilityIdentifier("capture.externalPhoto")
                if externalPhotoEnabled {
                    Text("Keep the original observer and photographer credit. This saves an archive reference, not a sighting by you.")
                        .font(.caption).foregroundStyle(NRTheme.muted).lineSpacing(3)
                    TextField("Original observer (required)", text: $externalObserver)
                        .textContentType(.name).accessibilityIdentifier("capture.externalObserver")
                    TextField("Photographer / photo credit (required)", text: $externalPhotoCredit, axis: .vertical)
                        .lineLimit(2...4).accessibilityIdentifier("capture.externalPhotoCredit")
                    TextField("https://original-record.example (required)", text: $externalSourceURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("capture.externalSourceURL")
                    Picker("Photo license", selection: $externalPhotoLicense) {
                        Text("Not specified").tag("")
                        Text("CC BY 4.0").tag("cc-by")
                        Text("CC0").tag("cc0")
                    }.accessibilityIdentifier("capture.externalPhotoLicense")
                    DatePicker("Original observation date", selection: $observedAt, in: ...Date(), displayedComponents: [.date])
                        .accessibilityIdentifier("capture.externalObservedDate")
                    Text("Use the original date and choose the recorded location below. No exact observation time is assumed. Adding a license records your information; it does not grant reuse rights.")
                        .font(.caption).foregroundStyle(NRTheme.muted).lineSpacing(3)
                }
            }.font(.system(size: 14)).padding(.top, 14)
        }.font(.system(size: 14, weight: .semibold)).tint(NRTheme.green)
            .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("capture.externalCredits")
    }
    private var linkedIdentity: NatureObservation? { publicSource ?? parentObservation }
    private var introCharacter: NatureObservation {
        if let parentObservation { return parentObservation }
        var example = previewObservation
        example.name = "California poppy"
        example.commonName = "California poppy"
        example.scientificName = "Eschscholzia californica"
        return example
    }
    private var isPlantCategory: Bool { kind == .flower || kind == .tree || kind == .plant }
    private var previewObservation: NatureObservation {
        var observation = NatureObservation(name: name.isEmpty ? kind.friendName : name, kind: kind, note: note, author: author,
                                            latitude: coordinate.latitude, longitude: coordinate.longitude)
        observation.commonName = trimmed(commonName)
        observation.scientificName = trimmed(scientificName)
        return observation
    }
    private var previewAssetInfo: SpeciesCharacterCatalog.AssetInfo { SpeciesCharacterCatalog.assetInfo(for: previewObservation) }
    private var speciesControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("NAME YOUR DISCOVERY").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
            if trimmed(commonName) != nil || trimmed(scientificName) != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trimmed(commonName) ?? scientificName).font(.system(size: 20, weight: .semibold, design: .rounded))
                    if trimmed(scientificName) != nil { Text(scientificName).font(.system(size: 12)).italic() }
                    if let identificationMethod { Text(identificationMethod).font(.caption).foregroundStyle(NRTheme.muted) }
                }.accessibilityIdentifier("capture.selectedSpecies")
            } else {
                Text("No species name chosen").font(.subheadline.weight(.semibold))
                Text("You can save an unnamed discovery with a shared type companion.").font(.caption).foregroundStyle(NRTheme.muted)
            }
            if linkedIdentity != nil {
                Text(publicSource == nil ? "This photo keeps the name from its existing discovery." : "The species name comes from the original iNaturalist record.")
                    .font(.caption).foregroundStyle(NRTheme.muted)
            } else {
                Button {
                    cancelIdentification(clearCandidates: true)
                    showSpeciesPicker = true
                } label: {
                    Label(trimmed(commonName) == nil && trimmed(scientificName) == nil ? "Choose a name yourself" : "Change the chosen name", systemImage: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                }.disabled(isGenerating).accessibilityIdentifier("capture.chooseSpecies")
                Text("Choose from \(CaptureSpeciesPicker.catalogCount) nature names, or enter another name. This is your manual choice, not an AI identification.")
                    .font(.caption).foregroundStyle(NRTheme.muted).lineSpacing(2)
                if isPlantCategory {
                    Divider()
                    plantIdentificationControls
                }
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    private var plantIdentificationControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Plant suggestions from Pl@ntNet").font(.subheadline.weight(.semibold))
            if let identificationConnectionError {
                Text(identificationConnectionError).font(.caption).foregroundStyle(NRTheme.muted)
            } else if identificationAccountConnected == false {
                Text("Pl@ntNet free service · account connection pending. Choose a name yourself while the connection is being set up.")
                    .font(.caption).foregroundStyle(NRTheme.muted).accessibilityIdentifier("capture.identificationPending")
            } else {
                Text(identificationAccountConnected == nil ? "Checking whether the free plant service is connected. You can choose a name yourself now." : "A plant identification request sends this photo to Pl@ntNet. Review its possible matches and confirm a name yourself.")
                    .font(.caption).foregroundStyle(NRTheme.muted).lineSpacing(2)
            }
            if isIdentifying {
                HStack(spacing: 10) { ProgressView(); Text("Requesting possible plant matches…").font(.subheadline) }
                Button("Cancel request") { cancelIdentification(clearCandidates: true) }.font(.caption.weight(.semibold))
            } else {
                Button { requestPlantIdentification() } label: {
                    Label("Request plant suggestions", systemImage: "camera.macro")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(NRTheme.lime, in: Capsule())
                }.buttonStyle(.plain).disabled(image == nil || isGenerating || !PlantIdentificationService().isConfigured || identificationAccountConnected != true)
                    .accessibilityIdentifier("capture.identifyPlant")
            }
            Text("Only a resized photo is sent. GPS, photo metadata, your note, and journal location are removed. This does not publish a discovery.")
                .font(.system(size: 10)).foregroundStyle(NRTheme.muted).lineSpacing(2)
            if !PlantIdentificationService().isConfigured {
                Text("Plant identification is not connected yet. Manual names and illustrated companions are available offline.")
                    .font(.caption).foregroundStyle(NRTheme.muted)
            }
            if let identificationError { Text(identificationError).font(.caption).foregroundStyle(NRTheme.muted).accessibilityIdentifier("capture.identificationError") }
            if !identificationCandidates.isEmpty {
                Text("Choose a possible match after checking the photo. Provider scores rank suggestions; they are not a probability of a correct identification.")
                    .font(.caption).foregroundStyle(NRTheme.muted)
                ForEach(identificationCandidates) { candidate in
                    Button { confirm(candidate) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: scientificName == candidate.scientificName ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20)).foregroundStyle(NRTheme.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.displayName).font(.subheadline.weight(.semibold))
                                Text(candidate.scientificName).font(.caption).italic()
                                Text("Provider score: \(Int((candidate.score * 100).rounded()))% · tap to confirm")
                                    .font(.system(size: 10)).foregroundStyle(NRTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(NRTheme.cream, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).disabled(isGenerating).accessibilityIdentifier("capture.plantCandidate.\(candidate.id)")
                }
                if let remainingIdentificationRequests {
                    Text("Shared provider allowance remaining: \(remainingIdentificationRequests)").font(.system(size: 10)).foregroundStyle(NRTheme.muted)
                }
            }
        }
    }
    @MainActor private func requestPlantIdentification() {
        guard let image, !isIdentifying, linkedIdentity == nil, identificationAccountConnected == true else { return }
        cancelIdentification(clearCandidates: true)
        let requestID = UUID()
        let photoID = selectionID
        identificationRequestID = requestID
        isIdentifying = true
        identificationTask = Task { @MainActor in
            defer {
                if identificationRequestID == requestID { isIdentifying = false; identificationTask = nil }
            }
            do {
                try await community.ensureSession()
                try Task.checkCancellation()
                guard requestID == identificationRequestID, photoID == selectionID else { return }
                guard let token = community.api.bearerToken else { throw PlantIdentificationService.IdentificationError.unavailable }
                let result = try await PlantIdentificationService().identify(image: image, bearerToken: token)
                try Task.checkCancellation()
                guard requestID == identificationRequestID, photoID == selectionID else { return }
                identificationCandidates = result.candidates
                remainingIdentificationRequests = result.remainingDailyRequests
                identificationAccountConnected = true
            } catch is CancellationError {
                // A cancelled or replaced photo must never receive stale candidates.
            } catch {
                guard requestID == identificationRequestID, photoID == selectionID, !Task.isCancelled else { return }
                identificationError = error.localizedDescription
            }
        }
    }
    @MainActor private func confirm(_ candidate: PlantIdentificationCandidate) {
        commonName = candidate.commonNames.first ?? ""
        scientificName = candidate.scientificName
        identificationMethod = "Pl@ntNet candidate · confirmed by photographer"
        companion = nil
        isSavedAIExample = false
        generationError = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    @MainActor private func cancelIdentification(clearCandidates: Bool) {
        identificationTask?.cancel()
        identificationTask = nil
        identificationRequestID = UUID()
        isIdentifying = false
        identificationError = nil
        if clearCandidates { identificationCandidates = []; remainingIdentificationRequests = nil }
    }
    private func clearIdentity() {
        commonName = ""
        scientificName = ""
        identificationMethod = nil
    }
    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    @MainActor private func checkIdentificationConnection() async {
        guard let base = CommunityConfiguration.apiBaseURL else { identificationAccountConnected = false; return }
        do {
            let request = URLRequest(url: base.appendingPathComponent("health"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let connected = values["identificationConfigured"] as? Bool else {
                if !Task.isCancelled { identificationConnectionError = "Plant suggestions are unavailable right now. Choose a name yourself to continue." }
                return
            }
            identificationAccountConnected = connected
            identificationConnectionError = nil
        } catch {
            guard !Task.isCancelled else { return }
            identificationConnectionError = "Plant suggestions are unavailable right now. Choose a name yourself to continue."
        }
    }
    private var locationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("YOUR CHARACTER’S PLACE", systemImage: "mappin.and.ellipse")
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
            if locationResolved {
                Map(initialPosition: .region(.init(center: coordinate, span: .init(latitudeDelta: 0.003, longitudeDelta: 0.003))), interactionModes: []) {
                    Marker(name.isEmpty ? "Your discovery" : name, coordinate: coordinate).tint(NRTheme.green)
                }.mapStyle(.standard(pointsOfInterest: .excludingAll)).mapControlVisibility(.hidden)
                    .frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 16))
                    .id("\(coordinate.latitude),\(coordinate.longitude)")
                Text(locationSource).font(.subheadline.weight(.medium))
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(NRTheme.muted)
            } else {
                Text("This photo has no saved location. Choose where it was taken before adding your character to the map.")
                    .font(.system(size: 13)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                if selectedPhotoIdentifier != nil {
                    Button { readSelectedPhotoLocation() } label: {
                        HStack(spacing: 8) {
                            if isReadingPhotoLocation { ProgressView() }
                            Label(isReadingPhotoLocation ? "Reading photo location…" : "Read this photo’s library location", systemImage: "photo.badge.checkmark")
                        }.font(.system(size: 13, weight: .semibold))
                    }.disabled(isReadingPhotoLocation).accessibilityIdentifier("capture.readPhotoLocation")
                    Text("You can allow access to only this photo. Your current location is not used automatically.")
                        .font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                }
            }
            if publicSource == nil {
                Button { showLocation = true } label: {
                    Label(locationResolved ? "Adjust this location" : "Choose location on map", systemImage: "map")
                        .font(.system(size: 14, weight: .semibold))
                }.disabled(isReadingPhotoLocation).accessibilityIdentifier("capture.location")
            }
            if let photoLocationError { Text(photoLocationError).font(.caption).foregroundStyle(NRTheme.muted) }
            Text("Your location stays in the journal. Identification and illustration requests remove photo metadata.")
                .font(.system(size: 10)).foregroundStyle(NRTheme.muted).lineSpacing(2)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    @MainActor private func readSelectedPhotoLocation() {
        guard let identifier = selectedPhotoIdentifier, !isReadingPhotoLocation else { return }
        let requestID = selectionID
        isReadingPhotoLocation = true
        photoLocationError = nil
        Task { @MainActor in
            defer { if requestID == selectionID { isReadingPhotoLocation = false } }
            do {
                let metadata = try await PhotoLibraryMetadataService.metadata(for: identifier)
                guard requestID == selectionID, !Task.isCancelled else { return }
                if let date = metadata?.takenAt { observedAt = min(date, Date()) }
                if let gps = metadata?.coordinate {
                    coordinate = gps
                    locationSource = "Location saved with your photo"
                    locationResolved = true
                } else {
                    photoLocationError = "This photo has no saved location. Choose its place on the map."
                }
            } catch {
                guard requestID == selectionID, !Task.isCancelled else { return }
                photoLocationError = error.localizedDescription
            }
        }
    }
    #if DEBUG
    private var aiControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(companion == nil ? "A DIFFERENT ART STYLE" : "OPTIONAL AI ARTWORK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                Spacer()
                Text("FREE").font(.system(size: 9, weight: .bold, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 5).background(NRTheme.lime, in: Capsule())
            }
            if isGenerating {
                HStack(spacing: 12) { ProgressView().tint(NRTheme.green); Text(generationStatus).font(.subheadline) }
                Text("The shared free service may take a while or be unavailable. You can cancel and keep your current companion.").font(.caption).foregroundStyle(NRTheme.muted)
                Button("Cancel generation") { generationTask?.cancel() }.font(.caption.weight(.semibold))
            } else {
                Button { generateCompanion() } label: {
                    Label(companion == nil ? "Generate an AI illustration" : "Make another AI version", systemImage: "camera.macro")
                        .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15).background(NRTheme.lime, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("capture.generate")
                Text("Sends a resized photo to Hugging Face / Black Forest Labs. GPS and photo metadata are removed. Uploaded and generated images may be accessible at public cache URLs; use nature photos you can share.")
                    .font(.system(size: 11)).foregroundStyle(NRTheme.muted).lineSpacing(3)
                Text("No account, payment or API key. Limited daily shared quota; no paid fallback.").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                Link("About the free image AI", destination: URL(string: "https://huggingface.co/spaces/black-forest-labs/FLUX.2-klein-4B")!).font(.system(size: 11, weight: .semibold))
            }
            if let generationError { Text(generationError).font(.footnote).foregroundStyle(NRTheme.muted) }
            if companion != nil {
                Text(isSavedAIExample ? "Saved AI example generated earlier from this sample photo. No new request was made." : "AI interpretation of the photo · FLUX.2 [klein] 4B. This does not identify a species.").font(.system(size: 11)).foregroundStyle(NRTheme.muted)
                Button("Use the free illustrated companion") { companion = nil; isSavedAIExample = false }.font(.caption.weight(.semibold))
            }
        }.padding(17).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }
    #endif
    @MainActor private func generateCompanion() {
        #if !DEBUG
        generationError = "Online illustration is unavailable in this build. Your offline companion is ready to save."
        return
        #else
        guard let image, !isGenerating else { return }
        let requestID = selectionID
        isGenerating = true
        generationError = nil
        generationStatus = "Preparing your nature photo…"
        generationTask = Task { @MainActor in
            defer { if requestID == selectionID { isGenerating = false; generationTask = nil } }
            do {
                let generated = try await FreeStickerAIService().generate(image: image, kind: kind, label: recognition?.label ?? kind.title, paletteHex: recognition?.paletteHex) { message in generationStatus = message }
                try Task.checkCancellation()
                guard requestID == selectionID else { return }
                companion = generated
                if note == Self.poppyDesignNote {
                    note = "AI companion inspired by the public Unsplash sample, generated with FLUX.2 [klein] 4B. Artistic interpretation, not a verified species identification or a campus sighting."
                } else if note == Self.liveSampleNote {
                    note = "AI companion from the live-scan sample, generated with FLUX.2 [klein] 4B. Photo © Annette Herz (CC BY), https://www.inaturalist.org/observations/108094155 . Artistic interpretation, not a verified species identification or a campus sighting."
                }
                isSavedAIExample = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                guard requestID == selectionID else { return }
                generationError = "Generation cancelled. Your photo and on-device companion are still available."
            } catch {
                guard requestID == selectionID else { return }
                generationError = error.localizedDescription
            }
        }
        #endif
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(NRTheme.muted)
            content()
            Rectangle().fill(NRTheme.ink.opacity(0.12)).frame(height: 1)
        }
    }
    private func primaryLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) { Image(systemName: icon); Text(title) }.font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 19).foregroundStyle(NRTheme.cream).background(NRTheme.ink, in: Capsule())
    }
    @MainActor private func load(_ item: PhotosPickerItem, requestID: UUID) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                guard requestID == selectionID, !Task.isCancelled else { return }
                error = "That photo couldn't be opened. Please choose another one."
                isAnalyzing = false
                return
            }
            try Task.checkCancellation()
            guard requestID == selectionID else { return }
            selectedPhotoIdentifier = item.itemIdentifier
            await analyze(image, data: data, sample: false, requestID: requestID)
        } catch {
            guard requestID == selectionID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
            isAnalyzing = false
        }
    }
    @MainActor
    private func analyze(_ image: UIImage, data: Data?, sample: Bool, requestID: UUID? = nil) async {
        guard !Task.isCancelled else { return }
        let activeID = requestID ?? UUID()
        if requestID == nil { selectionID = activeID; selectedPhotoIdentifier = nil }
        guard activeID == selectionID else { return }
        generationTask?.cancel()
        cancelIdentification(clearCandidates: true)
        clearIdentity()
        clearExternalPhotoCredit()
        isGenerating = false
        self.image = image
        isSamplePhoto = sample
        samplePhotoCredit = "Flower photograph via Unsplash. This is a practice discovery, not an observation made on campus."
        recognition = nil
        recognitionError = nil
        companion = nil
        isSavedAIExample = false
        generationError = nil
        photoLocationError = nil
        isReadingPhotoLocation = false
        isAnalyzing = true
        coordinate = initialCoordinate
        locationResolved = parentObservation != nil
        observedAt = Date()
        locationSource = parentObservation == nil ? "Choose where this photo was taken" : "Existing story location"
        if !sample, let data, let metadata = PhotoRecognitionService.metadata(from: data) {
            if let gps = metadata.coordinate { coordinate = gps; locationSource = "Location from photo GPS"; locationResolved = true }
            if let date = metadata.takenAt { observedAt = min(date, Date()) }
        }
        do {
            let result = try await PhotoRecognitionService().recognize(image: image)
            guard activeID == selectionID, !Task.isCancelled else { return }
            recognition = result
            kind = parentObservation?.kind ?? result.kind
            name = parentObservation?.name ?? result.kind.friendName
        } catch {
            guard activeID == selectionID, !Task.isCancelled else { return }
            recognitionError = error.localizedDescription
            kind = parentObservation?.kind ?? .other
            name = parentObservation?.name ?? NatureKind.other.friendName
        }
        if let linked = linkedIdentity {
            commonName = linked.commonName ?? (publicSource == nil ? "" : linked.name)
            scientificName = linked.scientificName ?? ""
            identificationMethod = linked.identificationMethod ?? (publicSource == nil ? "Name from existing discovery" : "Name from the original iNaturalist record")
        }
        if let source = publicSource {
            coordinate = source.coordinate
            observedAt = source.observedAt
            locationSource = "Original iNaturalist observation location"
            locationResolved = true
            kind = source.kind
            name = source.kind.friendName
            note = "A companion inspired by \(source.name). iNaturalist observation by \(source.author); original photo credit below."
        }
        isAnalyzing = false
    }
    private func save() {
        guard let image, !isSaving, !isGenerating, !isIdentifying, !isReadingPhotoLocation else { return }
        guard locationResolved, CLLocationCoordinate2DIsValid(coordinate), coordinate.latitude.isFinite, coordinate.longitude.isFinite else {
            showLocation = true
            return
        }
        do {
            let source = try sourceForSaving()
            isSaving = true
            let result = try store.add(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, note: note, author: author, latitude: coordinate.latitude, longitude: coordinate.longitude, observedAt: observedAt, image: image, recognition: recognition, isSample: isSamplePhoto, profileID: parentObservation?.storyID, sourceObservation: source, companion: companion, locationSource: locationSource, commonName: trimmed(commonName), scientificName: trimmed(scientificName), identificationMethod: identificationMethod)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved(result)
        } catch { self.error = error.localizedDescription; isSaving = false }
    }
    private func sourceForSaving() throws -> NatureObservation? {
        if let publicSource { return publicSource }
        guard externalPhotoEnabled else { return nil }
        guard let observer = trimmed(externalObserver), let credit = trimmed(externalPhotoCredit) else {
            throw ExternalPhotoError.incompleteCredit
        }
        guard let link = trimmed(externalSourceURL), link.count <= 2048,
              link.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: link), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              let url = components.url else { throw ExternalPhotoError.invalidURL }
        let originalDate = Calendar.current.startOfDay(for: observedAt)
        var source = NatureObservation(name: trimmed(commonName) ?? trimmed(name) ?? kind.friendName, kind: kind,
                                       note: note, author: observer, latitude: coordinate.latitude,
                                       longitude: coordinate.longitude, observedAt: originalDate)
        source.commonName = trimmed(commonName)
        source.scientificName = trimmed(scientificName)
        source.identificationMethod = identificationMethod == "Chosen by photographer"
            ? "Name chosen manually for imported photo" : (identificationMethod ?? "Name entered for an external photo")
        source.sourceURL = url.absoluteString
        source.sourceAttribution = credit
        source.isSourceArchive = true
        source.locationSource = "Original source location confirmed by you"
        source.hasSourceObservationTime = false
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        source.sourceObservedOn = formatter.string(from: originalDate)
        source.photoLicense = trimmed(externalPhotoLicense)
        if externalPhotoLicense == "cc-by" { source.photoLicenseURL = "https://creativecommons.org/licenses/by/4.0/" }
        else if externalPhotoLicense == "cc0" { source.photoLicenseURL = "https://creativecommons.org/publicdomain/zero/1.0/" }
        return source
    }
    private enum ExternalPhotoError: LocalizedError {
        case incompleteCredit, invalidURL
        var errorDescription: String? {
            switch self {
            case .incompleteCredit: return "Add both the original observer and the photographer / photo credit in Photo source and credit."
            case .invalidURL: return "Add a valid HTTPS link to the original record in Photo source and credit."
            }
        }
    }
    private func clearExternalPhotoCredit() {
        externalPhotoEnabled = false
        externalObserver = ""
        externalPhotoCredit = ""
        externalSourceURL = ""
        externalPhotoLicense = ""
    }
    private func reset() {
        importTask?.cancel()
        generationTask?.cancel()
        cancelIdentification(clearCandidates: true)
        clearIdentity()
        clearExternalPhotoCredit()
        selectionID = UUID()
        selectedPhotoIdentifier = nil
        locationResolved = false
        photoLocationError = nil
        isReadingPhotoLocation = false
        isAnalyzing = false
        isGenerating = false
        image = nil; recognition = nil; recognitionError = nil; photoItem = nil; name = ""; note = ""; isSamplePhoto = false; publicSource = nil; companion = nil; generationError = nil; isSavedAIExample = false
    }
}

private struct CaptureSpeciesChoice: Identifiable {
    let commonName: String
    let scientificName: String
    let kind: NatureKind
    var id: String { scientificName.isEmpty ? commonName : scientificName }
}

/// Selecting a catalog name is a photographer's manual choice, not recognition evidence.
private struct CaptureSpeciesPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var commonName: String
    @State private var scientificName: String
    @State private var query = ""
    let kind: NatureKind
    let onChoose: (CaptureSpeciesChoice) -> Void
    private static let catalog: [CaptureSpeciesChoice] = {
        guard let loaded = try? CaliforniaCatalog.load() else { return [] }
        return loaded.catalog.records
            .map { CaptureSpeciesChoice(commonName: $0.name, scientificName: $0.scientificName ?? "", kind: $0.kind) }
            .sorted { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending }
    }()
    static var catalogCount: Int { catalog.count }
    init(commonName: String, scientificName: String, kind: NatureKind, onChoose: @escaping (CaptureSpeciesChoice) -> Void) {
        _commonName = State(initialValue: commonName)
        _scientificName = State(initialValue: scientificName)
        self.kind = kind
        self.onChoose = onChoose
    }
    private var filteredCatalog: [CaptureSpeciesChoice] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return Self.catalog }
        return Self.catalog.filter { $0.commonName.localizedCaseInsensitiveContains(search) || $0.scientificName.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a species you recognize, or enter a name. This records your choice and shows its pre-created companion artwork.")
                        .font(.subheadline).foregroundStyle(NRTheme.muted)
                }
                Section("Enter another name") {
                    TextField("Common name (optional)", text: $commonName).textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("capture.manualCommonName")
                    TextField("Scientific name (optional)", text: $scientificName).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("capture.manualScientificName")
                    Button("Use these names") {
                        onChoose(CaptureSpeciesChoice(commonName: commonName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                      scientificName: scientificName.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind))
                    }.disabled(commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("capture.useManualSpecies")
                }
                Section("\(Self.catalog.count) nature names · chosen by you") {
                    ForEach(filteredCatalog) { choice in
                        Button { onChoose(choice) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: choice.kind.symbol).frame(width: 24).foregroundStyle(NRTheme.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.commonName).font(.subheadline.weight(.medium)).foregroundStyle(NRTheme.ink)
                                    Text(choice.scientificName).font(.caption).italic().foregroundStyle(NRTheme.muted)
                                }
                            }.padding(.vertical, 3)
                        }.accessibilityIdentifier("capture.manualSpecies.\(choice.scientificName)")
                    }
                    if filteredCatalog.isEmpty { Text("No matching catalog name. You can enter a name above.").font(.caption).foregroundStyle(NRTheme.muted) }
                }
            }
            .scrollContentBackground(.hidden).background(NRTheme.cream)
            .searchable(text: $query, prompt: "Common or scientific name")
            .navigationTitle("Choose a name").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .tint(NRTheme.green)
        }
    }
}

struct CaptureLocationPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var draftCoordinate = NRTheme.campus
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var coordinateEntryError: String?
    @FocusState private var coordinateFieldFocused: Bool
    @StateObject private var location = LocationService()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Move the map to where you saw it.").font(.subheadline).foregroundStyle(NRTheme.muted).padding()
                Map(position: $position) { UserAnnotation() }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .onMapCameraChange(frequency: .onEnd) { context in
                        draftCoordinate = context.region.center
                        if !coordinateFieldFocused { updateCoordinateFields() }
                    }
                    .overlay { Image(systemName: "mappin.circle.fill").font(.system(size: 38)).foregroundStyle(NRTheme.green).background(.white, in: Circle()).offset(y: -19) }
                DisclosureGroup("Enter coordinates") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Decimal latitude −90 to 90, longitude −180 to 180. Apply, then confirm with Use spot.")
                            .font(.caption).foregroundStyle(NRTheme.muted)
                        HStack {
                            TextField("Latitude", text: $latitudeText).focused($coordinateFieldFocused).accessibilityIdentifier("capture.location.latitude")
                            TextField("Longitude", text: $longitudeText).focused($coordinateFieldFocused).accessibilityIdentifier("capture.location.longitude")
                        }.keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Apply coordinates") { applyEnteredCoordinates() }
                            .font(.footnote.weight(.semibold)).accessibilityIdentifier("capture.location.applyCoordinates")
                        if let coordinateEntryError { Text(coordinateEntryError).font(.caption).foregroundStyle(.red) }
                    }.padding(.top, 10)
                }.font(.footnote.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 12).background(NRTheme.cream)
                    .accessibilityIdentifier("capture.location.enterCoordinates")
                HStack {
                    Button { location.requestLocation() } label: { Label(location.isLocating ? "Finding location…" : "Use my location", systemImage: "location.fill") }.disabled(location.isLocating)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.4f, %.4f", draftCoordinate.latitude, draftCoordinate.longitude)).font(.system(size: 11, design: .monospaced))
                        if let description = location.accuracyDescription { Text(description).font(.system(size: 10)).foregroundStyle(NRTheme.muted) }
                    }
                }.font(.footnote).padding(20).background(NRTheme.cream)
            }
            .navigationTitle("Location").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Use spot") { coordinate = draftCoordinate; onDone() } }
            }
            .onAppear {
                draftCoordinate = coordinate
                updateCoordinateFields()
                position = .region(.init(center: coordinate, span: .init(latitudeDelta: 0.003, longitudeDelta: 0.003)))
            }
            .onChange(of: location.lastUpdatedAt) { _, _ in
                if let gps = location.coordinate {
                    draftCoordinate = gps
                    updateCoordinateFields()
                    position = .region(.init(center: gps, span: .init(latitudeDelta: 0.003, longitudeDelta: 0.003)))
                }
            }
            .overlay(alignment: .top) {
                if let message = location.message { Text(message).font(.caption).padding().background(NRTheme.cream, in: RoundedRectangle(cornerRadius: 14)).padding() }
            }
        }.tint(NRTheme.green)
    }
    private func updateCoordinateFields() {
        latitudeText = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), draftCoordinate.latitude)
        longitudeText = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), draftCoordinate.longitude)
    }
    private func applyEnteredCoordinates() {
        guard let latitude = Double(latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let longitude = Double(longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)),
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            coordinateEntryError = "Enter a valid latitude and longitude using decimal points."
            return
        }
        let entered = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        draftCoordinate = entered
        coordinateEntryError = nil
        coordinateFieldFocused = false
        position = .region(.init(center: entered, span: .init(latitudeDelta: 0.003, longitudeDelta: 0.003)))
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { onImage(info[.originalImage] as? UIImage) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}
