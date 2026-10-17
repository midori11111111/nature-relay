#!/usr/bin/env python3
"""Write the immutable, reviewable scientific-name artwork manifest and Swift catalog."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent.parent
records=json.loads((PROJECT/'Resources/CaliforniaCatalog/catalog.json').read_text())['records']
# The key is the source record's scientific name, never a random index, a display name,
# an image filename, or a mutable observation ID. Shared assets remain type companions.
by_species={
'Eschscholzia californica':('california-poppy',True),
'Epilobium canum':('california-fuchsia',True),
'Collomia heterophylla':('twemoji-blossom',False),
'Quercus douglasii':('oak',False),
'Calochortus argillosus':('mariposa-lily',False),
'Quercus berberidifolia':('oak',False),
'Dactylis glomerata':('grass',False),
'Dendroalsia abietina':('moss',False),
'Woodwardia fimbriata':('fern',False),
'Aesculus californica':('twemoji-tree',False),
'Corvus corax':('bird-black',False),
'Icaricia saepiolus':('twemoji-butterfly',False),
'Ursus americanus':('bear-dark',False),
'Buteo jamaicensis':('bird-brown',False),
'Nymphalis antiopa':('butterfly-dark',False),
'Campylorhynchus brunneicapillus':('bird-brown',False),
'Canis latrans':('twemoji-fox',False),
'Adelpha californica':('butterfly-dark',False),
'Pinus ponderosa':('twemoji-conifer',False),
'Astur cooperii':('bird-gray',False),
'Rosa californica':('california-wild-rose',True),
'Quercus wislizeni':('oak',False),
'Neckera menziesii':('moss',False),
'Cinclus mexicanus':('bird-gray',False),
'Parnassius clodius':('butterfly-cream',False),
'Sceloporus occidentalis':('twemoji-lizard',False),
'Geraea canescens':('twemoji-sunflower',False),
'Chilopsis linearis':('twemoji-tree',False),
'Meleagris gallopavo':('twemoji-turkey',False),
'Sedum rubiginosum':('stonecrop',False),
'Parnassius smintheus behrii':('butterfly-cream',False),
'Umbellularia californica':('twemoji-tree',False),
'Calochortus invenustus':('mariposa-lily',False),
'Geococcyx californianus':('bird-brown',False),
'Phidippus comatus':('twemoji-spider',False),
'Selaginella oregana':('moss',False),
'Icaricia acmon':('twemoji-butterfly',False),
'Trillium ovatum':('pacific-trillium',True),
'Notholithocarpus densiflorus':('oak',False),
'Dipterostemon capitatus':('blue-dicks',True),
'Pinus lambertiana':('twemoji-conifer',False),
'Hesperoyucca whipplei':('yucca',False),
'Bubo virginianus':('twemoji-owl',False),
'Vanessa cardui':('butterfly-orange',False),
'Otospermophilus beecheyi':('twemoji-squirrel',False),
'Trichostema lanatum':('miniature-lupine',False),
'Quercus garryana':('oak',False),
'Setophaga coronata auduboni':('bird-yellow',False),
'Arctostaphylos glandulosa':('manzanita',False),
'Brephidium exilis':('twemoji-butterfly',False),
'Nemacladus tenuis aliformis':('twemoji-blossom',False),
'Abies grandis':('twemoji-conifer',False),
'Cathartes aura':('bird-black',False),
'Thamnophis couchii':('twemoji-snake',False),
'Pellaea bridgesii':('fern',False),
'Papilio polyxenes':('butterfly-dark',False),
'Baileya multiradiata':('twemoji-sunflower',False),
'Quercus kelloggii':('oak',False),
'Molothrus ater':('bird-black',False),
'Asclepias cordifolia':('twemoji-herb',False),
'Toxicodendron diversilobum':('twemoji-herb',False),
'Platanus racemosa':('twemoji-tree',False),
'Auriparus flaviceps':('bird-yellow',False),
'Vanessa atalanta':('butterfly-red',False),
'Procyon lotor':('twemoji-raccoon',False),
'Aquilegia formosa':('twemoji-blossom',False),
'Quercus john-tuckeri':('oak',False),
'Calypte anna':('bird-gray',False),
'Arctostaphylos glauca':('manzanita',False),
'Nymphalis californica':('butterfly-orange',False),
'Trifolium depauperatum':('twemoji-blossom',False),
'Pinus contorta':('twemoji-conifer',False),
'Pandion haliaetus carolinensis':('bird-gray',False),
'Fissurella volcano':('twemoji-shell',False),
'Sedum spathulifolium':('stonecrop',False),
'Danaus gilippus':('butterfly-orange',False),
'Adelinia grandis':('blue-dicks',False),
'Melanerpes formicivorus bairdi':('bird-black',False),
'Butorides virescens':('bird-gray',False),
'Pinus sabiniana':('twemoji-conifer',False),
'Lupinus bicolor':('miniature-lupine',True),
'Larrea tridentata':('twemoji-herb',False),
'Arbutus menziesii':('twemoji-tree',False),
'Mimus polyglottos':('bird-gray',False),
'Papilio zelicaon':('butterfly-yellow',False),
'Lepus californicus':('twemoji-rabbit',False),
'Hemitomes congestum':('twemoji-blossom',False),
'Pseudotsuga menziesii':('twemoji-conifer',False),
'Callipepla californica':('bird-gray',False),
'Eriogonum fasciculatum polifolium':('twemoji-herb',False),
'Hesperopsis libya':('butterfly-dark',False),
'Claytonia perfoliata':('miners-lettuce',True),
'Aphelocoma californica':('bird-blue',False),
'Lasiurus cinereus cinereus':('twemoji-bat',False),
'Pinus monophylla':('twemoji-conifer',False),
'Ferocactus cylindraceus':('barrel-cactus',True),
'Argynnis callippe comstocki':('butterfly-orange',False),
'Papaver californicum':('fire-poppy',True),
'Acer negundo':('twemoji-tree',False),
'Icterus bullockii':('bird-yellow',False)
}
assert len(by_species)==100
assert set(by_species)=={r['scientificName'] for r in records}
# Correct broad-type choices where a stock silhouette would misleadingly imply another
# flower structure: use an honest herb fallback for species without a tailored design.
for scientific in ['Trichostema lanatum','Adelinia grandis']:
 by_species[scientific]=('twemoji-herb',False)
by_species['Canis latrans']=('canine',False)
by_species['Fissurella volcano']=('limpet',False)
# Source stock + documented manual modifications. No source observation photo was edited.
sources=json.loads((ROOT/'sources.json').read_text())
manual_names={
'california-poppy':('California poppy companion','Four-petal orange cup; simplified green leaves.'),
'california-fuchsia':('California fuchsia companion','Coral tubular blooms and narrow leaves.'),
'california-wild-rose':('California wild rose companion','Five pink petals with a yellow center.'),
'blue-dicks':('Blue dicks companion','Violet star-flower cluster on a tall stem.'),
'pacific-trillium':('Pacific trillium companion','Three white petals above three broad green leaves.'),
'miniature-lupine':('Miniature lupine companion','Purple flower spire and palm-shaped leaf arrangement.'),
'miners-lettuce':("Miner’s lettuce companion",'Small white blooms above a round, pierced leaf.'),
'barrel-cactus':('Barrel cactus companion','One rounded ribbed stem with spines and a warm yellow bloom.'),
'fire-poppy':('Fire poppy companion','Orange cup-shaped bloom; a stylized plant character.'),
'mariposa-lily':('Mariposa lily type companion','Three pale petals and colored petal-base marks; shared by two lily species.'),
'oak':('Oak type companion','Lobed canopy with a small acorn; shared by multiple oak species.'),
'fern':('Fern type companion','Curved frond with paired leaflets; shared fern type.'),
'moss':('Moss type companion','Low cushion and short shoots; shared moss type.'),
'grass':('Grass type companion','A tuft of slender leaves; shared grass type.'),
'stonecrop':('Stonecrop type companion','Fleshy green leaf rosette; shared stonecrop type.'),
'yucca':('Yucca type companion','Spiky leaf rosette and a tall cream bloom stalk.'),
'manzanita':('Manzanita type companion','Reddish branches, rounded green leaves, and small berries.'),
'canine':('Wild canine type companion','A broad canine companion; not a species illustration.'),
'limpet':('Limpet type companion','A low cap-shaped shell, replacing an unrelated spiral-shell stock icon.')
}
stock_titles={'bird':'Bird','bear':'Bear','raccoon':'Raccoon','rabbit':'Rabbit','squirrel':'Squirrel','bat':'Bat','lizard':'Lizard','snake':'Snake','spider':'Spider','shell':'Spiral shell','turkey':'Turkey','owl':'Owl','raptor':'Raptor','fox':'Fox','tree':'Broadleaf tree','conifer':'Conifer','cactus':'Cactus','herb':'Leafy plant','seedling':'Seedling','sunflower':'Yellow daisy','rose':'Closed rose','blossom':'Small flower','hibiscus':'Hibiscus','tulip':'Tulip','butterfly':'Blue butterfly'}
used={v[0] for v in by_species.values()}|{'twemoji-bird','twemoji-butterfly','twemoji-blossom','twemoji-tree','twemoji-herb','twemoji-seedling'}
assets=[]
for asset in sorted(used):
 if asset.startswith('twemoji-'):
  source=asset[8:];title=stock_titles[source]+' type companion';note='General type character. It does not depict diagnostic features of this species.'
  changes='Added a white sticker edge and transparent padding. '+('Added a simple face.' if source in ['sunflower','blossom','tree','conifer','cactus','rose'] else 'Original stock shape and colors retained.')
 elif asset in manual_names:
  source='blossom' if asset in ['california-wild-rose','mariposa-lily'] else None
  title,note=manual_names[asset];changes='Manually drawn vector character.'+(' Includes the stem and paired leaf element from Twemoji Blossom.' if source else ' Uses original Nature Relay vector paths; no borrowed stock geometry.')
 else:
  source='bird' if asset.startswith('bird-') else ('butterfly' if asset.startswith('butterfly-') else 'bear')
  title=(asset.replace('-',' ').capitalize())+' type companion';note='General type character. Color is a broad family cue; it does not reproduce species-specific markings.'
  changes='Recolored the stock vector; added a white sticker edge and transparent padding.'
 assets.append({'id':asset,'title':title,'credit':'Twemoji graphics © Twitter, Inc. and other contributors; Nature Relay adaptations.' if source else 'Nature Relay original vector artwork.', 'sourceURL':sources[source] if source else '', 'licenseName':'CC BY 4.0' if source else 'CC0 1.0', 'licenseURL':'https://creativecommons.org/licenses/by/4.0/' if source else 'https://creativecommons.org/publicdomain/zero/1.0/', 'isAdapted':bool(source),'matchDescription':note,'modifications':changes})
manifest={'schemaVersion':1,'retrievedAt':'2026-10-17','package':'Nature Relay species companions','imageGeneration':'No image generation service was used. Stock vector art is credited as stock; custom paths were drawn in SVG code.','identificationPolicy':'Companions are stylized illustrations. Only the source photo and source observation provide identification evidence. Shared type characters are explicitly marked and do not claim species-level accuracy.','attribution':'Twemoji graphics © Twitter, Inc. and other contributors, CC BY 4.0. Modified by Nature Relay. https://github.com/twitter/twemoji/tree/v14.0.2; https://creativecommons.org/licenses/by/4.0/. Original Nature Relay vector paths are dedicated to CC0 1.0.','sourcePackageURL':'https://github.com/twitter/twemoji/tree/v14.0.2','assets':assets,'scientificNameMapping':[{'scientificName':r['scientificName'],'assetID':by_species[r['scientificName']][0],'isSpeciesSpecific':by_species[r['scientificName']][1]} for r in records]}
(PROJECT/'Resources/character-asset-credits.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
(ROOT/'character-asset-credits.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')

def q(s):return json.dumps(s,ensure_ascii=False)
lines=['import UIKit','','/// Offline companions selected by the source record’s immutable scientific name.','/// Stock/type companions never claim to be exact species illustrations.','@MainActor','enum SpeciesCharacterCatalog {','    struct AssetInfo: Identifiable {','        let id: String','        let title: String','        let credit: String','        let sourceURL: String','        let licenseName: String','        let licenseURL: String','        let isSpeciesSpecific: Bool','        let isAdapted: Bool','        let matchDescription: String','        var attribution: String { "\\(credit) · \\(licenseName)" }','    }','','    private struct Match {','        let assetID: String','        let isSpeciesSpecific: Bool','    }','','    private static let images: NSCache<NSString, UIImage> = {', '        let cache = NSCache<NSString, UIImage>()', '        cache.countLimit = 32', '        cache.totalCostLimit = 16 * 1024 * 1024', '        return cache', '    }()','','    /// Includes both exact scientific-name matches and explicit type fallbacks.','    static func artwork(for observation: NatureObservation) -> UIImage? {','        let info = assetInfo(for: observation)','        if let cached = images.object(forKey: info.id as NSString) { return cached }','        guard let url = Bundle.main.url(forResource: info.id, withExtension: "png", subdirectory: "SpeciesCharacters"),','              let image = UIImage(contentsOfFile: url.path) else { return nil }','        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? (512 * 512 * 4)', '        images.setObject(image, forKey: info.id as NSString, cost: cost)','        return image','    }','','    static func assetInfo(for observation: NatureObservation) -> AssetInfo {','        let match = observation.scientificName.flatMap { scientificNameMapping[$0] }','        let assetID = match?.assetID ?? fallbackAssetID(for: observation.kind)','        let base = assets[assetID] ?? assets["twemoji-seedling"]!','        return AssetInfo(id: base.id, title: base.title, credit: base.credit, sourceURL: base.sourceURL,','                         licenseName: base.licenseName, licenseURL: base.licenseURL,','                         isSpeciesSpecific: match?.isSpeciesSpecific ?? false, isAdapted: base.isAdapted,','                         matchDescription: base.matchDescription)','    }','','    static var allAssetCredits: [AssetInfo] { assets.values.sorted { $0.id < $1.id } }','    static let creditSummary = "Twemoji graphics © Twitter, Inc. and other contributors · CC BY 4.0. Modified by Nature Relay. Original Nature Relay vectors · CC0 1.0."','','    private static func fallbackAssetID(for kind: NatureKind) -> String {','        switch kind {','        case .flower: return "twemoji-blossom"','        case .tree: return "twemoji-tree"','        case .bird: return "twemoji-bird"','        case .butterfly: return "twemoji-butterfly"','        case .plant: return "twemoji-herb"','        case .other: return "twemoji-seedling"','        }','    }','','    // Every stock fallback is marked false, even when its broad animal type matches.','    // A true value means a manually tailored stylized companion, not validated ID art.','    private static let scientificNameMapping: [String: Match] = [']
for s,(a,specific) in by_species.items(): lines.append(f'        {q(s)}: Match(assetID: {q(a)}, isSpeciesSpecific: {str(specific).lower()}),')
lines+=['    ]','','    private static let assets: [String: AssetInfo] = [']
for a in assets:
 lines.append('        '+q(a['id'])+': AssetInfo(id: '+q(a['id'])+', title: '+q(a['title'])+',')
 lines.append('            credit: '+q(a['credit'])+', sourceURL: '+q(a['sourceURL'])+',')
 lines.append('            licenseName: '+q(a['licenseName'])+', licenseURL: '+q(a['licenseURL'])+',')
 lines.append('            isSpeciesSpecific: false, isAdapted: '+str(a['isAdapted']).lower()+', matchDescription: '+q(a['matchDescription'])+'),')
lines+=['    ]','}']
(ROOT.parent/'SpeciesCharacterCatalog.swift').write_text('\n'.join(lines)+'\n')
print(f'Wrote {len(assets)} asset definitions and {len(by_species)} scientific-name mappings.')
