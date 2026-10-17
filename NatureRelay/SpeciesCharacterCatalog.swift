import UIKit
import ImageIO

/// Offline companions selected by the source record’s immutable scientific name.
/// Stock/type companions never claim to be exact species illustrations.
@MainActor
enum SpeciesCharacterCatalog {
    struct AssetInfo: Identifiable {
        let id: String
        let title: String
        let credit: String
        let sourceURL: String
        let licenseName: String
        let licenseURL: String
        let isSpeciesSpecific: Bool
        let isAdapted: Bool
        let matchDescription: String
        var isAIGenerated = false
        var attribution: String { "\(credit) · \(licenseName)" }
    }

    private struct Match {
        let assetID: String
        let isSpeciesSpecific: Bool
    }

    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    /// Includes both exact scientific-name matches and explicit type fallbacks.
    static func artwork(for observation: NatureObservation, targetSize: CGFloat = 180) -> UIImage? {
        let info = assetInfo(for: observation)
        let folder = info.isAIGenerated ? SpeciesACollection.directory : "SpeciesCharacters"
        let pixels = min(1024, max(96, Int(targetSize * 3)))
        let key = "\(folder)/\(info.id)/\(pixels)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let url = Bundle.main.url(forResource: info.id, withExtension: "png", subdirectory: folder),
              let image = decodeArtwork(at: url, maximumPixels: pixels), let cgImage = image.cgImage else { return nil }
        images.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// Decode only the resolution the view needs, rather than all full-size PNGs.
    static func decodeArtwork(at url: URL, maximumPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(1024, max(96, maximumPixels))
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func assetInfo(for observation: NatureObservation) -> AssetInfo {
        if let generated = SpeciesACollection.assetInfo(for: observation) { return generated }
        let match = observation.scientificName.flatMap { scientificNameMapping[$0] }
        let assetID = match?.assetID ?? fallbackAssetID(for: observation.kind)
        let base = assets[assetID] ?? assets["twemoji-seedling"]!
        return AssetInfo(id: base.id, title: base.title, credit: base.credit, sourceURL: base.sourceURL,
                         licenseName: base.licenseName, licenseURL: base.licenseURL,
                         isSpeciesSpecific: match?.isSpeciesSpecific ?? false, isAdapted: base.isAdapted,
                         matchDescription: base.matchDescription)
    }

    static var allAssetCredits: [AssetInfo] { assets.values.sorted { $0.id < $1.id } }
    static let creditSummary = "Twemoji graphics © Twitter, Inc. and other contributors · CC BY 4.0. Modified by Nature Relay. Original Nature Relay vectors · CC0 1.0."

    private static func fallbackAssetID(for kind: NatureKind) -> String {
        switch kind {
        case .flower: return "twemoji-blossom"
        case .tree: return "twemoji-tree"
        case .bird: return "twemoji-bird"
        case .butterfly: return "twemoji-butterfly"
        case .plant: return "twemoji-herb"
        case .other: return "twemoji-seedling"
        }
    }

    // Every stock fallback is marked false, even when its broad animal type matches.
    // A true value means a manually tailored stylized companion, not validated ID art.
    private static let scientificNameMapping: [String: Match] = [
        "Eschscholzia californica": Match(assetID: "california-poppy", isSpeciesSpecific: true),
        "Epilobium canum": Match(assetID: "california-fuchsia", isSpeciesSpecific: true),
        "Collomia heterophylla": Match(assetID: "twemoji-blossom", isSpeciesSpecific: false),
        "Quercus douglasii": Match(assetID: "oak", isSpeciesSpecific: false),
        "Calochortus argillosus": Match(assetID: "mariposa-lily", isSpeciesSpecific: false),
        "Quercus berberidifolia": Match(assetID: "oak", isSpeciesSpecific: false),
        "Dactylis glomerata": Match(assetID: "grass", isSpeciesSpecific: false),
        "Dendroalsia abietina": Match(assetID: "moss", isSpeciesSpecific: false),
        "Woodwardia fimbriata": Match(assetID: "fern", isSpeciesSpecific: false),
        "Aesculus californica": Match(assetID: "twemoji-tree", isSpeciesSpecific: false),
        "Corvus corax": Match(assetID: "bird-black", isSpeciesSpecific: false),
        "Icaricia saepiolus": Match(assetID: "twemoji-butterfly", isSpeciesSpecific: false),
        "Ursus americanus": Match(assetID: "bear-dark", isSpeciesSpecific: false),
        "Buteo jamaicensis": Match(assetID: "bird-brown", isSpeciesSpecific: false),
        "Nymphalis antiopa": Match(assetID: "butterfly-dark", isSpeciesSpecific: false),
        "Campylorhynchus brunneicapillus": Match(assetID: "bird-brown", isSpeciesSpecific: false),
        "Canis latrans": Match(assetID: "canine", isSpeciesSpecific: false),
        "Adelpha californica": Match(assetID: "butterfly-dark", isSpeciesSpecific: false),
        "Pinus ponderosa": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Astur cooperii": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Rosa californica": Match(assetID: "california-wild-rose", isSpeciesSpecific: true),
        "Quercus wislizeni": Match(assetID: "oak", isSpeciesSpecific: false),
        "Neckera menziesii": Match(assetID: "moss", isSpeciesSpecific: false),
        "Cinclus mexicanus": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Parnassius clodius": Match(assetID: "butterfly-cream", isSpeciesSpecific: false),
        "Sceloporus occidentalis": Match(assetID: "twemoji-lizard", isSpeciesSpecific: false),
        "Geraea canescens": Match(assetID: "twemoji-sunflower", isSpeciesSpecific: false),
        "Chilopsis linearis": Match(assetID: "twemoji-tree", isSpeciesSpecific: false),
        "Meleagris gallopavo": Match(assetID: "twemoji-turkey", isSpeciesSpecific: false),
        "Sedum rubiginosum": Match(assetID: "stonecrop", isSpeciesSpecific: false),
        "Parnassius smintheus behrii": Match(assetID: "butterfly-cream", isSpeciesSpecific: false),
        "Umbellularia californica": Match(assetID: "twemoji-tree", isSpeciesSpecific: false),
        "Calochortus invenustus": Match(assetID: "mariposa-lily", isSpeciesSpecific: false),
        "Geococcyx californianus": Match(assetID: "bird-brown", isSpeciesSpecific: false),
        "Phidippus comatus": Match(assetID: "twemoji-spider", isSpeciesSpecific: false),
        "Selaginella oregana": Match(assetID: "moss", isSpeciesSpecific: false),
        "Icaricia acmon": Match(assetID: "twemoji-butterfly", isSpeciesSpecific: false),
        "Trillium ovatum": Match(assetID: "pacific-trillium", isSpeciesSpecific: true),
        "Notholithocarpus densiflorus": Match(assetID: "oak", isSpeciesSpecific: false),
        "Dipterostemon capitatus": Match(assetID: "blue-dicks", isSpeciesSpecific: true),
        "Pinus lambertiana": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Hesperoyucca whipplei": Match(assetID: "yucca", isSpeciesSpecific: false),
        "Bubo virginianus": Match(assetID: "twemoji-owl", isSpeciesSpecific: false),
        "Vanessa cardui": Match(assetID: "butterfly-orange", isSpeciesSpecific: false),
        "Otospermophilus beecheyi": Match(assetID: "twemoji-squirrel", isSpeciesSpecific: false),
        "Trichostema lanatum": Match(assetID: "twemoji-herb", isSpeciesSpecific: false),
        "Quercus garryana": Match(assetID: "oak", isSpeciesSpecific: false),
        "Setophaga coronata auduboni": Match(assetID: "bird-yellow", isSpeciesSpecific: false),
        "Arctostaphylos glandulosa": Match(assetID: "manzanita", isSpeciesSpecific: false),
        "Brephidium exilis": Match(assetID: "twemoji-butterfly", isSpeciesSpecific: false),
        "Nemacladus tenuis aliformis": Match(assetID: "twemoji-blossom", isSpeciesSpecific: false),
        "Abies grandis": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Cathartes aura": Match(assetID: "bird-black", isSpeciesSpecific: false),
        "Thamnophis couchii": Match(assetID: "twemoji-snake", isSpeciesSpecific: false),
        "Pellaea bridgesii": Match(assetID: "fern", isSpeciesSpecific: false),
        "Papilio polyxenes": Match(assetID: "butterfly-dark", isSpeciesSpecific: false),
        "Baileya multiradiata": Match(assetID: "twemoji-sunflower", isSpeciesSpecific: false),
        "Quercus kelloggii": Match(assetID: "oak", isSpeciesSpecific: false),
        "Molothrus ater": Match(assetID: "bird-black", isSpeciesSpecific: false),
        "Asclepias cordifolia": Match(assetID: "twemoji-herb", isSpeciesSpecific: false),
        "Toxicodendron diversilobum": Match(assetID: "twemoji-herb", isSpeciesSpecific: false),
        "Platanus racemosa": Match(assetID: "twemoji-tree", isSpeciesSpecific: false),
        "Auriparus flaviceps": Match(assetID: "bird-yellow", isSpeciesSpecific: false),
        "Vanessa atalanta": Match(assetID: "butterfly-red", isSpeciesSpecific: false),
        "Procyon lotor": Match(assetID: "twemoji-raccoon", isSpeciesSpecific: false),
        "Aquilegia formosa": Match(assetID: "twemoji-blossom", isSpeciesSpecific: false),
        "Quercus john-tuckeri": Match(assetID: "oak", isSpeciesSpecific: false),
        "Calypte anna": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Arctostaphylos glauca": Match(assetID: "manzanita", isSpeciesSpecific: false),
        "Nymphalis californica": Match(assetID: "butterfly-orange", isSpeciesSpecific: false),
        "Trifolium depauperatum": Match(assetID: "twemoji-blossom", isSpeciesSpecific: false),
        "Pinus contorta": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Pandion haliaetus carolinensis": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Fissurella volcano": Match(assetID: "limpet", isSpeciesSpecific: false),
        "Sedum spathulifolium": Match(assetID: "stonecrop", isSpeciesSpecific: false),
        "Danaus gilippus": Match(assetID: "butterfly-orange", isSpeciesSpecific: false),
        "Adelinia grandis": Match(assetID: "twemoji-herb", isSpeciesSpecific: false),
        "Melanerpes formicivorus bairdi": Match(assetID: "bird-black", isSpeciesSpecific: false),
        "Butorides virescens": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Pinus sabiniana": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Lupinus bicolor": Match(assetID: "miniature-lupine", isSpeciesSpecific: true),
        "Larrea tridentata": Match(assetID: "twemoji-herb", isSpeciesSpecific: false),
        "Arbutus menziesii": Match(assetID: "twemoji-tree", isSpeciesSpecific: false),
        "Mimus polyglottos": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Papilio zelicaon": Match(assetID: "butterfly-yellow", isSpeciesSpecific: false),
        "Lepus californicus": Match(assetID: "twemoji-rabbit", isSpeciesSpecific: false),
        "Hemitomes congestum": Match(assetID: "twemoji-blossom", isSpeciesSpecific: false),
        "Pseudotsuga menziesii": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Callipepla californica": Match(assetID: "bird-gray", isSpeciesSpecific: false),
        "Eriogonum fasciculatum polifolium": Match(assetID: "twemoji-herb", isSpeciesSpecific: false),
        "Hesperopsis libya": Match(assetID: "butterfly-dark", isSpeciesSpecific: false),
        "Claytonia perfoliata": Match(assetID: "miners-lettuce", isSpeciesSpecific: true),
        "Aphelocoma californica": Match(assetID: "bird-blue", isSpeciesSpecific: false),
        "Lasiurus cinereus cinereus": Match(assetID: "twemoji-bat", isSpeciesSpecific: false),
        "Pinus monophylla": Match(assetID: "twemoji-conifer", isSpeciesSpecific: false),
        "Ferocactus cylindraceus": Match(assetID: "barrel-cactus", isSpeciesSpecific: true),
        "Argynnis callippe comstocki": Match(assetID: "butterfly-orange", isSpeciesSpecific: false),
        "Papaver californicum": Match(assetID: "fire-poppy", isSpeciesSpecific: true),
        "Acer negundo": Match(assetID: "twemoji-tree", isSpeciesSpecific: false),
        "Icterus bullockii": Match(assetID: "bird-yellow", isSpeciesSpecific: false),
    ]

    private static let assets: [String: AssetInfo] = [
        "barrel-cactus": AssetInfo(id: "barrel-cactus", title: "Barrel cactus companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "One rounded ribbed stem with spines and a warm yellow bloom."),
        "bear-dark": AssetInfo(id: "bear-dark", title: "Bear dark type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f43b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "bird-black": AssetInfo(id: "bird-black", title: "Bird black type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f426.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "bird-blue": AssetInfo(id: "bird-blue", title: "Bird blue type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f426.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "bird-brown": AssetInfo(id: "bird-brown", title: "Bird brown type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f426.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "bird-gray": AssetInfo(id: "bird-gray", title: "Bird gray type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f426.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "bird-yellow": AssetInfo(id: "bird-yellow", title: "Bird yellow type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f426.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "blue-dicks": AssetInfo(id: "blue-dicks", title: "Blue dicks companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Violet star-flower cluster on a tall stem."),
        "butterfly-cream": AssetInfo(id: "butterfly-cream", title: "Butterfly cream type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "butterfly-dark": AssetInfo(id: "butterfly-dark", title: "Butterfly dark type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "butterfly-orange": AssetInfo(id: "butterfly-orange", title: "Butterfly orange type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "butterfly-red": AssetInfo(id: "butterfly-red", title: "Butterfly red type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "butterfly-yellow": AssetInfo(id: "butterfly-yellow", title: "Butterfly yellow type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. Color is a broad family cue; it does not reproduce species-specific markings."),
        "california-fuchsia": AssetInfo(id: "california-fuchsia", title: "California fuchsia companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Coral tubular blooms and narrow leaves."),
        "california-poppy": AssetInfo(id: "california-poppy", title: "California poppy companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Four-petal orange cup; simplified green leaves."),
        "california-wild-rose": AssetInfo(id: "california-wild-rose", title: "California wild rose companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f33c.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "Five pink petals with a yellow center."),
        "canine": AssetInfo(id: "canine", title: "Wild canine type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "A broad canine companion; not a species illustration."),
        "fern": AssetInfo(id: "fern", title: "Fern type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Curved frond with paired leaflets; shared fern type."),
        "fire-poppy": AssetInfo(id: "fire-poppy", title: "Fire poppy companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Orange cup-shaped bloom; a stylized plant character."),
        "grass": AssetInfo(id: "grass", title: "Grass type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "A tuft of slender leaves; shared grass type."),
        "limpet": AssetInfo(id: "limpet", title: "Limpet type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "A low cap-shaped shell, replacing an unrelated spiral-shell stock icon."),
        "manzanita": AssetInfo(id: "manzanita", title: "Manzanita type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Reddish branches, rounded green leaves, and small berries."),
        "mariposa-lily": AssetInfo(id: "mariposa-lily", title: "Mariposa lily type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f33c.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "Three pale petals and colored petal-base marks; shared by two lily species."),
        "miners-lettuce": AssetInfo(id: "miners-lettuce", title: "Miner’s lettuce companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Small white blooms above a round, pierced leaf."),
        "miniature-lupine": AssetInfo(id: "miniature-lupine", title: "Miniature lupine companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Purple flower spire and palm-shaped leaf arrangement."),
        "moss": AssetInfo(id: "moss", title: "Moss type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Low cushion and short shoots; shared moss type."),
        "oak": AssetInfo(id: "oak", title: "Oak type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Lobed canopy with a small acorn; shared by multiple oak species."),
        "pacific-trillium": AssetInfo(id: "pacific-trillium", title: "Pacific trillium companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Three white petals above three broad green leaves."),
        "stonecrop": AssetInfo(id: "stonecrop", title: "Stonecrop type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Fleshy green leaf rosette; shared stonecrop type."),
        "twemoji-bat": AssetInfo(id: "twemoji-bat", title: "Bat type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f987.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-bird": AssetInfo(id: "twemoji-bird", title: "Bird type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f426.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-blossom": AssetInfo(id: "twemoji-blossom", title: "Small flower type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f33c.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-butterfly": AssetInfo(id: "twemoji-butterfly", title: "Blue butterfly type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-conifer": AssetInfo(id: "twemoji-conifer", title: "Conifer type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f332.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-herb": AssetInfo(id: "twemoji-herb", title: "Leafy plant type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f33f.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-lizard": AssetInfo(id: "twemoji-lizard", title: "Lizard type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f98e.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-owl": AssetInfo(id: "twemoji-owl", title: "Owl type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f989.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-rabbit": AssetInfo(id: "twemoji-rabbit", title: "Rabbit type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f407.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-raccoon": AssetInfo(id: "twemoji-raccoon", title: "Raccoon type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f99d.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-seedling": AssetInfo(id: "twemoji-seedling", title: "Seedling type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f331.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-snake": AssetInfo(id: "twemoji-snake", title: "Snake type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f40d.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-spider": AssetInfo(id: "twemoji-spider", title: "Spider type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f577.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-squirrel": AssetInfo(id: "twemoji-squirrel", title: "Squirrel type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f43f.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-sunflower": AssetInfo(id: "twemoji-sunflower", title: "Yellow daisy type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f33b.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-tree": AssetInfo(id: "twemoji-tree", title: "Broadleaf tree type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f333.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "twemoji-turkey": AssetInfo(id: "twemoji-turkey", title: "Turkey type companion",
            credit: "Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.", sourceURL: "https://raw.githubusercontent.com/twitter/twemoji/v14.0.2/assets/svg/1f983.svg",
            licenseName: "CC BY 4.0", licenseURL: "https://creativecommons.org/licenses/by/4.0/",
            isSpeciesSpecific: false, isAdapted: true, matchDescription: "General type character. It does not depict diagnostic features of this species."),
        "yucca": AssetInfo(id: "yucca", title: "Yucca type companion",
            credit: "Nature Relay original vector artwork.", sourceURL: "",
            licenseName: "CC0 1.0", licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
            isSpeciesSpecific: false, isAdapted: false, matchDescription: "Spiky leaf rosette and a tall cream bloom stalk."),
    ]
}
