# Nature Relay · A character collection

The production roster is the existing 100-species California archive. Completion and unique-image checks are recorded in `validation.json`; a development preview explicitly has `complete: false`. The strict assembler refuses to finalize an incomplete collection.

The user selected `DesignConcepts/poppy-v1/a-flower-cup.png`: the flower itself forms the character's round body, with a friendly face and small organic limbs. This chosen original is adopted as the California poppy asset. Each other species is generated separately through the built-in image tool, using that A image as the style/character-construction reference. The licensed archive photographs guide species traits and are usually also attached as biological references. For California bay, the photograph was inspected separately and the accepted call used only the A image plus a botanical description. The prompt asks for true transparency. No paid app API, model training, stock substitution, image-grid splitting, or programmatic recoloring produces this collection.

Species distinctions are designed into the artwork:

- Flowers: petal number and outline, throat markings, tube shape, stamens, buds and leaves. The two mariposa lilies have distinct three-petal shapes and markings.
- Trees: leaf outline and arrangement, needles, cones/acorns, bark and branch silhouette. Oaks and conifers have individual designs.
- Ferns, mosses and succulents: frond/leaf/rosette structure, growth habit and characteristic colors.
- Birds: bill, crest, body proportions, characteristic feather color regions and tail shape.
- Butterflies: wing outline, tails, color fields, borders and spots, with varying poses.
- Other wildlife: individual body shape, appendages, markings and texture.

The exact accepted prompts and distinguishing traits are saved in `generated-prompts.json`. Per-group generated manifests retain the accepted output's provenance, references and review notes. Some accepted images followed a targeted correction, so the final 100 artwork files are not a claim of exactly 100 generation attempts. The original A prompt is in `adopted-poppy.json`; that prompt was a new generation without reference images. Reference/output paths record the generation machine; the accepted poppy asset is preserved in the bundled character registry and all licensed source photographs are included in this project.

`NatureRelay/SpeciesCharactersA/manifest.json` is the actual app registry. Asset IDs are deterministic hashes of scientific names, and every species gets its own PNG/hash. It retains the source observation ID and reference-photo credit/license. Original photographs, dates, approximate recorded places and attribution remain separate and unchanged. AI art is labeled as AI-generated artwork, not as CC0/Twemoji stock or as identification evidence.

The app resolves known scientific names first, then original source IDs, and known common names only when no scientific identity exists. Map pins, feed, saved Journal cards, details, capture choices and community dispatches share that lookup. Unknown identities retain an honest category fallback; pre-existing per-photo custom artwork remains preserved. Naming a species manually does not establish that the photo has been identified by AI.

Full-resolution transparent PNGs are retained. ImageIO decodes map/detail thumbnails at the size needed, with a 24 MiB canonical-character cache. Showing the bundled collection works offline and makes no image API requests. Built-in image-tool account usage is separate from the app's US$0 paid runtime ledger.

To validate the actual registry, run `zsh Tests/run-species-character-checks.sh` with an iOS Simulator booted. Generate the portable Xcode project with `python3 tools/genproj.py`. Development-only assembly/gallery scripts are not part of this submission snapshot. Local generation-machine paths have been removed from the provenance JSON; prompts, source-photo credits, accepted asset IDs and output hashes are retained.
