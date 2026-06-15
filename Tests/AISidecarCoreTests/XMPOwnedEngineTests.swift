import Foundation
import XCTest
@testable import AISidecarCore

final class XMPOwnedEngineTests: XCTestCase {
    func testParserReadsCanonicalNewDocument() throws {
        let targetPath = "/tmp/Bird.xmp"
        let parsed = XMPDocumentWriter().makeNewDocument(
            targetPath: targetPath,
            includeHierarchicalBag: true
        )
        _ = try XMPKeywordMerger().merge(
            plan: changePlan(targetPath: targetPath, flat: ["wading bird"], hierarchical: ["wading bird"]),
            into: parsed
        )

        let data = try XMPDocumentWriter().data(for: parsed)
        let reparsed = try XMPDocumentParser().parse(data: data, targetPath: targetPath)
        let reader = XMPKeywordReader()

        XCTAssertEqual(reader.flatKeywords(in: reparsed), ["wading bird"])
        XCTAssertEqual(reader.hierarchicalKeywords(in: reparsed), ["wading bird"])
    }

    func testParserReadsAlternatePrefixesAndExistingKeywords() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(alternatePrefixXMP.utf8),
            targetPath: "/tmp/Alternate.xmp"
        )
        let reader = XMPKeywordReader()

        XCTAssertEqual(reader.flatKeywords(in: parsed), ["existing bird"])
        XCTAssertEqual(reader.hierarchicalKeywords(in: parsed), ["existing habitat"])
    }

    func testParserAcceptsMissingManagedBags() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(noManagedBagXMP.utf8),
            targetPath: "/tmp/MissingBags.xmp"
        )
        let snapshot = XMPMetadataSnapshot.make(targetPath: "/tmp/MissingBags.xmp", exists: true, parsed: parsed)

        XCTAssertEqual(snapshot.flatKeywords, [])
        XCTAssertEqual(snapshot.hierarchicalKeywords, [])
        XCTAssertTrue(snapshot.unmanagedContentFingerprint.canonicalEntries.contains {
            $0.contains("rating") || $0.contains("Exposure2012")
        })
    }

    func testParserClassifiesMalformedXML() throws {
        XCTAssertThrowsError(try XMPDocumentParser().parse(
            data: Data("<x:xmpmeta><rdf:RDF>".utf8),
            targetPath: "/tmp/Malformed.xmp"
        )) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpParseFailed)
        }
    }

    func testParserClassifiesUnsupportedManagedRDFShape() throws {
        XCTAssertThrowsError(try XMPDocumentParser().parse(
            data: Data(unsupportedManagedShapeXMP.utf8),
            targetPath: "/tmp/Unsupported.xmp"
        )) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
        }
    }

    func testKeywordMergerDeduplicatesPreservesExistingCasingAndSeparatesBags() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(alternatePrefixXMP.utf8),
            targetPath: "/tmp/Merge.xmp"
        )
        let outcome = try XMPKeywordMerger().merge(
            plan: changePlan(
                targetPath: "/tmp/Merge.xmp",
                flat: ["Existing Bird", "marsh"],
                hierarchical: ["Existing Habitat", "behavior"]
            ),
            into: parsed
        )

        XCTAssertEqual(outcome.addedFlatKeywords, ["marsh"])
        XCTAssertEqual(outcome.resultingFlatKeywords, ["existing bird", "marsh"])
        XCTAssertEqual(outcome.addedHierarchicalKeywords, ["behavior"])
        XCTAssertEqual(outcome.resultingHierarchicalKeywords, ["existing habitat", "behavior"])
    }

    func testOwnedEngineWritesNewSidecarAndReadsItBack() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Bird.xmp")
        let engine = OwnedXMPSidecarEngine()

        let result = try engine.apply(XMPWriteRequest(plan: changePlan(
            targetPath: target.path,
            flat: ["wading bird"],
            hierarchical: ["wading bird"]
        )))
        let snapshot = try engine.readSnapshot(at: target.path)

        XCTAssertTrue(result.created)
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.addedFlatKeywords, ["wading bird"])
        XCTAssertEqual(result.addedHierarchicalKeywords, ["wading bird"])
        XCTAssertEqual(snapshot.flatKeywords, ["wading bird"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["wading bird"])
    }

    func testOwnedEngineMergesExistingSidecarAndPreservesUnmanagedFingerprint() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Existing.xmp")
        try existingDevelopSettingsXMP.write(to: target, atomically: true, encoding: .utf8)
        let engine = OwnedXMPSidecarEngine()
        let preSnapshot = try engine.readSnapshot(at: target.path)

        let result = try engine.apply(XMPWriteRequest(plan: changePlan(
            targetPath: target.path,
            flat: ["marsh"],
            hierarchical: ["habitat"]
        )))
        let postSnapshot = try engine.readSnapshot(at: target.path)

        XCTAssertFalse(result.created)
        XCTAssertTrue(result.modified)
        XCTAssertEqual(postSnapshot.flatKeywords, ["existing bird", "marsh"])
        XCTAssertEqual(postSnapshot.hierarchicalKeywords, ["existing habitat", "habitat"])
        XCTAssertEqual(
            postSnapshot.unmanagedContentFingerprint,
            preSnapshot.unmanagedContentFingerprint
        )
    }

    func testOwnedEngineCreatesMissingManagedBagsInExistingSidecar() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("NoKeywords.xmp")
        try noManagedBagXMP.write(to: target, atomically: true, encoding: .utf8)
        let engine = OwnedXMPSidecarEngine()
        let preSnapshot = try engine.readSnapshot(at: target.path)

        _ = try engine.apply(XMPWriteRequest(plan: changePlan(
            targetPath: target.path,
            flat: ["landscape"],
            hierarchical: ["landscape"]
        )))
        let postSnapshot = try engine.readSnapshot(at: target.path)

        XCTAssertEqual(postSnapshot.flatKeywords, ["landscape"])
        XCTAssertEqual(postSnapshot.hierarchicalKeywords, ["landscape"])
        XCTAssertEqual(
            postSnapshot.unmanagedContentFingerprint,
            preSnapshot.unmanagedContentFingerprint
        )
    }

    func testOwnedEngineFailuresDoNotReplaceExistingFileOrLeaveTempFile() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Broken.xmp")
        let original = unsupportedManagedShapeXMP
        try original.write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try OwnedXMPSidecarEngine().apply(XMPWriteRequest(plan: changePlan(
            targetPath: target.path,
            flat: ["new keyword"],
            hierarchical: []
        )))) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
        }

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
        let directoryContents = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(directoryContents, ["Broken.xmp"])
    }

    func testMockMetadataWriteEngineReturnsDeterministicValues() throws {
        let targetPath = "/tmp/Mock.xmp"
        let snapshot = XMPMetadataSnapshot(
            targetPath: targetPath,
            exists: true,
            flatKeywords: ["existing"],
            hierarchicalKeywords: [],
            unmanagedContentFingerprint: .empty()
        )
        let engine = MockMetadataWriteEngine(snapshotsByPath: [targetPath: snapshot])
        let plan = changePlan(targetPath: targetPath, flat: ["new"], hierarchical: [])

        let context = try engine.prepare(configuration: .builtInDefaults)
        let preview = try engine.preview(XMPWriteRequest(plan: plan))
        let result = try engine.apply(XMPWriteRequest(plan: plan))
        let validated = try engine.validateReadable(at: targetPath)
        try engine.shutdown()

        XCTAssertEqual(context.engineName, OwnedXMPSidecarEngine.engineName)
        XCTAssertEqual(validated, snapshot)
        XCTAssertEqual(preview.existingFlatKeywords, ["existing"])
        XCTAssertEqual(preview.resultingFlatKeywords, ["existing", "new"])
        XCTAssertEqual(result.preWriteSnapshot, snapshot)
        XCTAssertEqual(result.postWriteSnapshot.flatKeywords, ["existing", "new"])
    }

    private func changePlan(
        targetPath: String,
        flat: [String],
        hierarchical: [String]
    ) -> XMPChangePlan {
        XMPChangePlan(
            status: .planned,
            targetXMPPath: targetPath,
            targetRelativePath: URL(fileURLWithPath: targetPath).lastPathComponent,
            pairScope: .union,
            sourceMembers: [],
            flatKeywordsToAdd: flat.map(plannedKeyword),
            hierarchicalKeywordsToAdd: hierarchical.map(plannedKeyword),
            skippedCandidates: [],
            candidateExtractionIssues: [],
            sourceVerificationWarnings: [],
            groupWarnings: [],
            existingPolicy: .merge,
            backupPlan: BackupPlan(
                backupSidecars: false,
                backupRequiredBeforeMerge: false,
                conflictPolicy: .merge
            ),
            validationPlan: .phase2Default,
            failures: []
        )
    }

    private func plannedKeyword(_ term: String) -> PlannedKeyword {
        let normalized = KeywordTextNormalizer.normalize(term)
        return PlannedKeyword(
            term: normalized,
            normalizedKey: KeywordTextNormalizer.deduplicationKey(for: normalized),
            candidates: []
        )
    }
}

private let alternatePrefixXMP = """
<?xml version="1.0" encoding="UTF-8"?>
<meta:xmpmeta xmlns:meta="adobe:ns:meta/">
  <r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:d="http://purl.org/dc/elements/1.1/"
         xmlns:lightroom="http://ns.adobe.com/lightroom/1.0/">
    <r:Description r:about="">
      <d:subject>
        <r:Bag>
          <r:li>existing bird</r:li>
        </r:Bag>
      </d:subject>
      <lightroom:hierarchicalSubject>
        <r:Bag>
          <r:li>existing habitat</r:li>
        </r:Bag>
      </lightroom:hierarchicalSubject>
    </r:Description>
  </r:RDF>
</meta:xmpmeta>
"""

private let noManagedBagXMP = """
<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
         xmlns:aux="http://ns.adobe.com/exif/1.0/aux/">
  <rdf:Description rdf:about="">
    <crs:Exposure2012>+0.35</crs:Exposure2012>
    <aux:rating>5</aux:rating>
  </rdf:Description>
</rdf:RDF>
"""

private let existingDevelopSettingsXMP = """
<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="fixture">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
           xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">
    <rdf:Description rdf:about="">
      <dc:subject>
        <rdf:Bag>
          <rdf:li>existing bird</rdf:li>
        </rdf:Bag>
      </dc:subject>
      <lr:hierarchicalSubject>
        <rdf:Bag>
          <rdf:li>existing habitat</rdf:li>
        </rdf:Bag>
      </lr:hierarchicalSubject>
      <crs:Exposure2012>+0.35</crs:Exposure2012>
      <crs:Contrast2012>12</crs:Contrast2012>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
"""

private let unsupportedManagedShapeXMP = """
<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
           xmlns:dc="http://purl.org/dc/elements/1.1/">
    <rdf:Description rdf:about="">
      <dc:subject>
        <rdf:Seq>
          <rdf:li>existing bird</rdf:li>
        </rdf:Seq>
      </dc:subject>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
"""
