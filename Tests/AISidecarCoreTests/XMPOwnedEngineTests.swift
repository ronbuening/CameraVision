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
        let snapshot = try XMPMetadataSnapshot.make(
            targetPath: "/tmp/MissingBags.xmp",
            exists: true,
            parsed: parsed
        )

        XCTAssertEqual(snapshot.flatKeywords, [])
        XCTAssertEqual(snapshot.hierarchicalKeywords, [])
        XCTAssertNil(snapshot.rating)
        XCTAssertNil(snapshot.label)
        XCTAssertNil(snapshot.urgency)
        XCTAssertTrue(snapshot.unmanagedContentFingerprint.canonicalEntries.contains { $0.contains("aux") })
        XCTAssertTrue(snapshot.unmanagedContentFingerprint.canonicalEntries.contains { $0.contains("Exposure2012") })
    }

    func testSnapshotReadsManagedScalarsFromAttributeAndElementForms() throws {
        for (xml, path) in [
            (attributeScalarXMP, "/tmp/AttributeSnapshot.xmp"),
            (elementScalarXMP, "/tmp/ElementSnapshot.xmp"),
        ] {
            let parsed = try XMPDocumentParser().parse(data: Data(xml.utf8), targetPath: path)
            let snapshot = try XMPMetadataSnapshot.make(targetPath: path, exists: true, parsed: parsed)

            XCTAssertEqual(snapshot.rating, "4")
            XCTAssertEqual(snapshot.label, "Green")
            XCTAssertEqual(snapshot.urgency, "2")
        }
    }

    func testSnapshotRejectsConflictingManagedScalars() throws {
        let path = "/tmp/ConflictingSnapshot.xmp"
        let parsed = try XMPDocumentParser().parse(data: Data(conflictingScalarXMP.utf8), targetPath: path)

        XCTAssertThrowsError(try XMPMetadataSnapshot.make(targetPath: path, exists: true, parsed: parsed)) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
        }
    }

    func testFingerprintIgnoresManagedScalarValuesInBothForms() throws {
        XCTAssertEqual(
            XMPUnmanagedContentFingerprint.algorithmVersion,
            "xmp-unmanaged-content-fingerprint/2.0"
        )
        let attribute = try XMPDocumentParser().parse(
            data: Data(attributeScalarXMP.utf8),
            targetPath: "/tmp/AttributeFingerprint.xmp"
        )
        let changedAttribute = try XMPDocumentParser().parse(
            data: Data(
                attributeScalarXMP
                    .replacingOccurrences(of: "xmp:Rating=\"4\"", with: "xmp:Rating=\"5\"")
                    .replacingOccurrences(of: "xmp:Label=\"Green\"", with: "xmp:Label=\"Red\"")
                    .replacingOccurrences(of: "photoshop:Urgency=\"2\"", with: "photoshop:Urgency=\"1\"")
                    .utf8
            ),
            targetPath: "/tmp/ChangedAttributeFingerprint.xmp"
        )
        let element = try XMPDocumentParser().parse(
            data: Data(elementScalarXMP.utf8),
            targetPath: "/tmp/ElementFingerprint.xmp"
        )
        let changedElement = try XMPDocumentParser().parse(
            data: Data(
                elementScalarXMP
                    .replacingOccurrences(of: ">4</quality:Rating>", with: ">5</quality:Rating>")
                    .replacingOccurrences(of: ">Green</quality:Label>", with: ">Red</quality:Label>")
                    .replacingOccurrences(of: ">2</ps:Urgency>", with: ">1</ps:Urgency>")
                    .utf8
            ),
            targetPath: "/tmp/ChangedElementFingerprint.xmp"
        )

        XCTAssertEqual(
            XMPUnmanagedContentFingerprint.make(from: attribute),
            XMPUnmanagedContentFingerprint.make(from: changedAttribute)
        )
        XCTAssertEqual(
            XMPUnmanagedContentFingerprint.make(from: element),
            XMPUnmanagedContentFingerprint.make(from: changedElement)
        )
    }

    func testFingerprintStillChangesForUnmanagedContent() throws {
        let original = try XMPDocumentParser().parse(
            data: Data(existingDevelopSettingsXMP.utf8),
            targetPath: "/tmp/OriginalDevelopSettings.xmp"
        )
        let changed = try XMPDocumentParser().parse(
            data: Data(
                existingDevelopSettingsXMP
                    .replacingOccurrences(of: ">+0.35</crs:Exposure2012>", with: ">+1.00</crs:Exposure2012>")
                    .utf8
            ),
            targetPath: "/tmp/ChangedDevelopSettings.xmp"
        )

        XCTAssertNotEqual(
            XMPUnmanagedContentFingerprint.make(from: original),
            XMPUnmanagedContentFingerprint.make(from: changed)
        )
    }

    func testFingerprintRetainsNestedAndForeignNamespaceScalarLookalikes() throws {
        let xmp = """
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                     xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                     xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
                     xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
                     xmlns:foreign="urn:example:foreign">
              <rdf:Description rdf:about="" foreign:Rating="4">
                <foreign:Label>Green</foreign:Label>
                <crs:Container xmp:Rating="4">
                  <xmp:Label>Green</xmp:Label>
                  <photoshop:Urgency>2</photoshop:Urgency>
                </crs:Container>
              </rdf:Description>
            </rdf:RDF>
            """
        let original = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/ScalarLookalikes.xmp"
        )
        let originalFingerprint = XMPUnmanagedContentFingerprint.make(from: original)
        let replacements = [
            ("foreign:Rating=\"4\"", "foreign:Rating=\"5\""),
            (">Green</foreign:Label>", ">Red</foreign:Label>"),
            ("xmp:Rating=\"4\"", "xmp:Rating=\"5\""),
            (">Green</xmp:Label>", ">Red</xmp:Label>"),
            (">2</photoshop:Urgency>", ">1</photoshop:Urgency>"),
        ]

        XCTAssertNil(try XMPScalarReader.read(.rating, in: original))
        XCTAssertNil(try XMPScalarReader.read(.label, in: original))
        XCTAssertNil(try XMPScalarReader.read(.urgency, in: original))
        for (oldValue, newValue) in replacements {
            let changed = try XMPDocumentParser().parse(
                data: Data(xmp.replacingOccurrences(of: oldValue, with: newValue).utf8),
                targetPath: "/tmp/ChangedScalarLookalikes.xmp"
            )
            XCTAssertNotEqual(originalFingerprint, XMPUnmanagedContentFingerprint.make(from: changed))
        }
    }

    func testFingerprintRetainsScalarsOutsideTheLocatedRDFIsland() throws {
        let xmp = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="" xmp:Rating="4"/>
              </rdf:RDF>
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="" xmp:Rating="2"/>
              </rdf:RDF>
            </x:xmpmeta>
            """
        let original = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/SecondIsland.xmp"
        )
        let changedSecondIsland = try XMPDocumentParser().parse(
            data: Data(xmp.replacingOccurrences(of: "xmp:Rating=\"2\"", with: "xmp:Rating=\"1\"").utf8),
            targetPath: "/tmp/ChangedSecondIsland.xmp"
        )
        let changedLocatedIsland = try XMPDocumentParser().parse(
            data: Data(xmp.replacingOccurrences(of: "xmp:Rating=\"4\"", with: "xmp:Rating=\"5\"").utf8),
            targetPath: "/tmp/ChangedLocatedIsland.xmp"
        )

        // The reader sees only the located island, so the second island's
        // lookalike must stay under fingerprint protection.
        XCTAssertEqual(try XMPScalarReader.read(.rating, in: original)?.value, "4")
        XCTAssertNotEqual(
            XMPUnmanagedContentFingerprint.make(from: original),
            XMPUnmanagedContentFingerprint.make(from: changedSecondIsland)
        )
        XCTAssertEqual(
            XMPUnmanagedContentFingerprint.make(from: original),
            XMPUnmanagedContentFingerprint.make(from: changedLocatedIsland)
        )
    }

    func testScalarReaderReadsAttributeFormForEveryManagedScalar() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(attributeScalarXMP.utf8),
            targetPath: "/tmp/AttributeScalars.xmp"
        )
        let expected: [(XMPManagedScalar, String)] = [
            (.rating, "4"),
            (.label, "Green"),
            (.urgency, "2"),
        ]

        for (scalar, value) in expected {
            let occurrence = try XCTUnwrap(try XMPScalarReader.read(scalar, in: parsed))
            XCTAssertEqual(occurrence.scalar, scalar)
            XCTAssertEqual(occurrence.value, value)
            XCTAssertEqual(occurrence.form, .attribute)
        }
    }

    func testScalarReaderReadsElementFormForEveryManagedScalar() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(elementScalarXMP.utf8),
            targetPath: "/tmp/ElementScalars.xmp"
        )
        let expected: [(XMPManagedScalar, String)] = [
            (.rating, "4"),
            (.label, "Green"),
            (.urgency, "2"),
        ]

        for (scalar, value) in expected {
            let occurrence = try XCTUnwrap(try XMPScalarReader.read(scalar, in: parsed.document))
            XCTAssertEqual(occurrence.scalar, scalar)
            XCTAssertEqual(occurrence.value, value)
            XCTAssertEqual(occurrence.form, .element)
        }
    }

    func testScalarReaderReturnsNilWhenManagedScalarsAreAbsent() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(noManagedBagXMP.utf8),
            targetPath: "/tmp/NoScalars.xmp"
        )

        for scalar in XMPManagedScalar.allCases {
            XCTAssertNil(try XMPScalarReader.read(scalar, in: parsed))
        }
    }

    func testScalarReaderToleratesEqualOccurrencesAcrossDescriptionsAndForms() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(equalDuplicateScalarXMP.utf8),
            targetPath: "/tmp/EqualScalarDuplicates.xmp"
        )
        let expected: [(XMPManagedScalar, String)] = [
            (.rating, "4"),
            (.label, "Green"),
            (.urgency, "2"),
        ]

        for (scalar, value) in expected {
            XCTAssertEqual(try XMPScalarReader.read(scalar, in: parsed)?.value, value)
        }
    }

    func testScalarReaderRejectsConflictingOccurrencesForEveryManagedScalar() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(conflictingScalarXMP.utf8),
            targetPath: "/tmp/ConflictingScalars.xmp"
        )

        for scalar in XMPManagedScalar.allCases {
            XCTAssertThrowsError(try XMPScalarReader.read(scalar, in: parsed)) { error in
                XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
                XCTAssertTrue((error as? SidecarError)?.message.contains(scalar.qualifiedPropertyName) == true)
            }
        }
    }

    func testScalarReaderRejectsStructuredScalarElement() throws {
        let xmp = """
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                     xmlns:xmp="http://ns.adobe.com/xap/1.0/">
              <rdf:Description rdf:about="">
                <xmp:Rating><rdf:Description rdf:about="nested"/></xmp:Rating>
              </rdf:Description>
            </rdf:RDF>
            """
        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/StructuredScalar.xmp"
        )

        XCTAssertThrowsError(try XMPScalarReader.read(.rating, in: parsed)) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
        }
    }

    func testScalarMergerCreatesAttributeScalarsAndDeclaresNamespacesOnce() throws {
        let parsed = XMPDocumentWriter().makeNewDocument(
            targetPath: "/tmp/NewScalars.xmp",
            includeHierarchicalBag: true
        )
        let merger = XMPScalarMerger()

        try merger.setScalar(.rating, to: "4", in: parsed)
        try merger.setScalar(.label, to: "Green", in: parsed)
        try merger.setScalar(.urgency, to: "2", in: parsed)
        try merger.setScalar(.rating, to: "5", in: parsed)

        XCTAssertEqual(
            (parsed.rdfElement.namespaces ?? []).filter {
                $0.name == "xmp" && $0.stringValue == XMPNamespace.xmp
            }.count,
            1
        )
        XCTAssertEqual(
            (parsed.rdfElement.namespaces ?? []).filter {
                $0.name == "photoshop" && $0.stringValue == XMPNamespace.photoshop
            }.count,
            1
        )
        let data = try XMPDocumentWriter().data(for: parsed)
        let reparsed = try XMPDocumentParser().parse(data: data, targetPath: parsed.targetPath)
        XCTAssertEqual(try XMPScalarReader.read(.rating, in: reparsed)?.value, "5")
        XCTAssertEqual(try XMPScalarReader.read(.rating, in: reparsed)?.form, .attribute)
        XCTAssertEqual(try XMPScalarReader.read(.label, in: reparsed)?.value, "Green")
        XCTAssertEqual(try XMPScalarReader.read(.label, in: reparsed)?.form, .attribute)
        XCTAssertEqual(try XMPScalarReader.read(.urgency, in: reparsed)?.value, "2")
        XCTAssertEqual(try XMPScalarReader.read(.urgency, in: reparsed)?.form, .attribute)

        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(xml.components(separatedBy: "xmlns:xmp=").count - 1, 1)
        XCTAssertEqual(xml.components(separatedBy: "xmlns:photoshop=").count - 1, 1)
    }

    func testScalarMergerUpdatesAttributeFormInPlace() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(attributeScalarXMP.utf8),
            targetPath: "/tmp/AttributeScalars.xmp"
        )

        try XMPScalarMerger().setScalar(.rating, to: "5", in: parsed)

        let data = try XMPDocumentWriter().data(for: parsed)
        let reparsed = try XMPDocumentParser().parse(data: data, targetPath: parsed.targetPath)
        let occurrence = try XCTUnwrap(try XMPScalarReader.read(.rating, in: reparsed))
        XCTAssertEqual(occurrence.value, "5")
        XCTAssertEqual(occurrence.form, .attribute)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("xmp:Rating=\"5\""))
    }

    func testScalarMergerUpdatesElementFormInPlace() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(elementScalarXMP.utf8),
            targetPath: "/tmp/ElementScalars.xmp"
        )

        try XMPScalarMerger().setScalar(.label, to: "Red", in: parsed)

        let data = try XMPDocumentWriter().data(for: parsed)
        let reparsed = try XMPDocumentParser().parse(data: data, targetPath: parsed.targetPath)
        let occurrence = try XCTUnwrap(try XMPScalarReader.read(.label, in: reparsed))
        XCTAssertEqual(occurrence.value, "Red")
        XCTAssertEqual(occurrence.form, .element)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("<quality:Label>Red</quality:Label>"))
    }

    func testScalarMergerUpdatesEveryEqualDuplicateOccurrence() throws {
        let parsed = try XMPDocumentParser().parse(
            data: Data(equalDuplicateScalarXMP.utf8),
            targetPath: "/tmp/EqualScalarDuplicates.xmp"
        )
        let merger = XMPScalarMerger()

        try merger.setScalar(.rating, to: "5", in: parsed)
        try merger.setScalar(.label, to: "Red", in: parsed)
        try merger.setScalar(.urgency, to: "1", in: parsed)

        XCTAssertEqual(try XMPScalarReader.read(.rating, in: parsed)?.value, "5")
        XCTAssertEqual(try XMPScalarReader.read(.label, in: parsed)?.value, "Red")
        XCTAssertEqual(try XMPScalarReader.read(.urgency, in: parsed)?.value, "1")
        let xml = try XCTUnwrap(String(data: XMPDocumentWriter().data(for: parsed), encoding: .utf8))
        XCTAssertEqual(xml.components(separatedBy: "Rating=\"5\"").count - 1, 1)
        XCTAssertEqual(xml.components(separatedBy: ">5</xmp:Rating>").count - 1, 1)
    }

    func testParserPrefersDescriptionWhoseAboutMatchesSourceFile() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="file:///photos/Other.JPG">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="file:///photos/Bird.JPG">
                  <xmp:Label>Green</xmp:Label>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/Bird.xmp",
            sourceFileNames: ["Bird.JPG"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            "file:///photos/Bird.JPG"
        )
    }

    func testParserMatchesPlainAboutContainingPercentLiterally() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="Other.JPG">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="IMG%20001.jpg">
                  <xmp:Label>Green</xmp:Label>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/IMG%20001.xmp",
            sourceFileNames: ["IMG%20001.jpg"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            "IMG%20001.jpg"
        )
    }

    func testParserDoesNotTreatLongerFilenameAsSourceMatch() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="file:///photos/NotBird.JPG">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="file:///photos/Bird.JPG">
                  <xmp:Label>Green</xmp:Label>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/Bird.xmp",
            sourceFileNames: ["Bird.JPG"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            "file:///photos/Bird.JPG"
        )
    }

    func testParserDecodesSourceFilenameAndPrefersItOverEmptyAbout() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="file:///photos/Great%20Bird.JPG">
                  <xmp:Label>Green</xmp:Label>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/Great Bird.xmp",
            sourceFileNames: ["Great Bird.JPG"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            "file:///photos/Great%20Bird.JPG"
        )
    }

    func testParserMatchesWindowsAboutPathByTerminalComponent() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="C:\\photos\\Bird.JPG">
                  <xmp:Label>Green</xmp:Label>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/Bird.xmp",
            sourceFileNames: ["Bird.JPG"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            "C:\\photos\\Bird.JPG"
        )
    }

    func testParserPrefersManagedDescriptionOverSourceMatch() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:dc="http://purl.org/dc/elements/1.1/"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="file:///photos/Bird.JPG">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="file:///photos/Other.JPG">
                  <dc:subject><rdf:Bag><rdf:li>existing</rdf:li></rdf:Bag></dc:subject>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/Bird.xmp",
            sourceFileNames: ["Bird.JPG"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            "file:///photos/Other.JPG"
        )
    }

    func testParserPrefersEmptyAboutOverUnrelatedFirstDescription() throws {
        let xmp = """
            <?xml version="1.0" encoding="UTF-8"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       xmlns:xmp="http://ns.adobe.com/xap/1.0/">
                <rdf:Description rdf:about="file:///photos/Other.JPG">
                  <xmp:Rating>1</xmp:Rating>
                </rdf:Description>
                <rdf:Description rdf:about="">
                  <xmp:Label>Green</xmp:Label>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            """

        let parsed = try XMPDocumentParser().parse(
            data: Data(xmp.utf8),
            targetPath: "/tmp/Bird.xmp",
            sourceFileNames: ["Bird.JPG"]
        )

        XCTAssertEqual(
            XMPXML.firstAttributeValue(
                on: parsed.descriptionElement,
                namespaceURI: XMPNamespace.rdf,
                localName: "about"
            ),
            ""
        )
    }

    func testParserClassifiesMalformedXML() throws {
        XCTAssertThrowsError(
            try XMPDocumentParser().parse(
                data: Data("<x:xmpmeta><rdf:RDF>".utf8),
                targetPath: "/tmp/Malformed.xmp"
            )
        ) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpParseFailed)
        }
    }

    func testParserClassifiesUnsupportedManagedRDFShape() throws {
        XCTAssertThrowsError(
            try XMPDocumentParser().parse(
                data: Data(unsupportedManagedShapeXMP.utf8),
                targetPath: "/tmp/Unsupported.xmp"
            )
        ) { error in
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

        let result = try engine.apply(
            XMPWriteRequest(
                plan: changePlan(
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

    func testOwnedEngineWritesNewSidecarWithKeywordsAndManagedScalars() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Graded.xmp")
        let engine = OwnedXMPSidecarEngine()
        let plan = changePlan(
            targetPath: target.path,
            flat: ["AI Quality good"],
            hierarchical: ["AI Quality|good"],
            ratingWrite: scalarWrite(.rating, value: "4", existingValue: nil, action: .write),
            labelWrite: scalarWrite(.label, value: "Green", existingValue: nil, action: .write),
            urgencyWrite: scalarWrite(.urgency, value: "2", existingValue: nil, action: .write)
        )

        let preview = try engine.preview(XMPWriteRequest(plan: plan))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertNil(preview.existingRating)
        XCTAssertEqual(preview.resultingRating, "4")
        XCTAssertEqual(preview.resultingLabel, "Green")
        XCTAssertEqual(preview.resultingUrgency, "2")

        let result = try engine.apply(XMPWriteRequest(plan: plan))
        let snapshot = try engine.readSnapshot(at: target.path)
        XCTAssertTrue(result.created)
        XCTAssertFalse(result.modified)
        XCTAssertEqual(snapshot.flatKeywords, ["AI Quality good"])
        XCTAssertEqual(snapshot.hierarchicalKeywords, ["AI Quality|good"])
        XCTAssertEqual(snapshot.rating, "4")
        XCTAssertEqual(snapshot.label, "Green")
        XCTAssertEqual(snapshot.urgency, "2")
        XCTAssertEqual(result.existingRating, result.preWriteSnapshot.rating)
        XCTAssertEqual(result.resultingRating, result.postWriteSnapshot.rating)
        XCTAssertEqual(result.existingLabel, result.preWriteSnapshot.label)
        XCTAssertEqual(result.resultingLabel, result.postWriteSnapshot.label)
        XCTAssertEqual(result.existingUrgency, result.preWriteSnapshot.urgency)
        XCTAssertEqual(result.resultingUrgency, result.postWriteSnapshot.urgency)
        XCTAssertEqual(snapshot.unmanagedContentFingerprint, result.postWriteSnapshot.unmanagedContentFingerprint)

        let xml = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(xml.contains("xmp:Rating=\"4\""))
        XCTAssertTrue(xml.contains("xmp:Label=\"Green\""))
        XCTAssertTrue(xml.contains("photoshop:Urgency=\"2\""))
    }

    func testOwnedEnginePreservesForeignRatingWhileWritingOtherScalarsAndKeywords() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Foreign.xmp")
        try foreignScalarXMP.write(to: target, atomically: true, encoding: .utf8)
        let engine = OwnedXMPSidecarEngine()
        let preSnapshot = try engine.readSnapshot(at: target.path)
        let originalBytes = try Data(contentsOf: target)
        let plan = changePlan(
            targetPath: target.path,
            flat: ["AI Quality good"],
            hierarchical: ["AI Quality|good"],
            ratingWrite: scalarWrite(.rating, value: "4", existingValue: "3", action: .skipExisting),
            labelWrite: scalarWrite(.label, value: "Green", existingValue: nil, action: .write),
            urgencyWrite: scalarWrite(.urgency, value: "2", existingValue: nil, action: .write)
        )

        let preview = try engine.preview(XMPWriteRequest(plan: plan))
        XCTAssertEqual(try Data(contentsOf: target), originalBytes)
        XCTAssertEqual(preview.existingRating, "3")
        XCTAssertEqual(preview.resultingRating, "3")
        XCTAssertEqual(preview.resultingLabel, "Green")
        XCTAssertEqual(preview.resultingUrgency, "2")

        let result = try engine.apply(XMPWriteRequest(plan: plan))
        let postSnapshot = try engine.readSnapshot(at: target.path)
        XCTAssertTrue(result.modified)
        XCTAssertEqual(postSnapshot.rating, "3")
        XCTAssertEqual(postSnapshot.label, "Green")
        XCTAssertEqual(postSnapshot.urgency, "2")
        XCTAssertEqual(postSnapshot.flatKeywords, ["existing bird", "AI Quality good"])
        XCTAssertEqual(postSnapshot.hierarchicalKeywords, ["existing habitat", "AI Quality|good"])
        XCTAssertEqual(postSnapshot.unmanagedContentFingerprint, preSnapshot.unmanagedContentFingerprint)
    }

    func testOwnedEngineScalarOnlyWriteBypassesKeywordNoChangeExit() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("ScalarOnly.xmp")
        try attributeScalarXMP.write(to: target, atomically: true, encoding: .utf8)
        let engine = OwnedXMPSidecarEngine()
        let plan = changePlan(
            targetPath: target.path,
            flat: [],
            hierarchical: [],
            ratingWrite: scalarWrite(.rating, value: "5", existingValue: "4", action: .overwrite)
        )

        let result = try engine.apply(XMPWriteRequest(plan: plan))

        XCTAssertFalse(result.created)
        XCTAssertTrue(result.modified)
        XCTAssertEqual(result.existingRating, "4")
        XCTAssertEqual(result.resultingRating, "5")
        XCTAssertEqual(try engine.readSnapshot(at: target.path).rating, "5")
    }

    func testOwnedEngineSkipOnlyScalarPlanLeavesBytesUnchanged() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("SkippedScalars.xmp")
        try attributeScalarXMP.write(to: target, atomically: true, encoding: .utf8)
        let originalBytes = try Data(contentsOf: target)
        let engine = OwnedXMPSidecarEngine()
        let plan = changePlan(
            targetPath: target.path,
            flat: [],
            hierarchical: [],
            ratingWrite: scalarWrite(.rating, value: "1", existingValue: "4", action: .skipExisting),
            labelWrite: scalarWrite(.label, value: "Red", existingValue: "Green", action: .skipExisting),
            urgencyWrite: scalarWrite(.urgency, value: "1", existingValue: "2", action: .skipExisting)
        )

        let preview = try engine.preview(XMPWriteRequest(plan: plan))
        let result = try engine.apply(XMPWriteRequest(plan: plan))

        XCTAssertEqual(preview.resultingRating, "4")
        XCTAssertEqual(preview.resultingLabel, "Green")
        XCTAssertEqual(preview.resultingUrgency, "2")
        XCTAssertFalse(result.created)
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.preWriteSnapshot, result.postWriteSnapshot)
        XCTAssertEqual(try Data(contentsOf: target), originalBytes)
    }

    func testOwnedEngineRejectsUrgencyWriteWithoutResultingLabel() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("UrgencyWithoutLabel.xmp")
        let plan = changePlan(
            targetPath: target.path,
            flat: [],
            hierarchical: [],
            urgencyWrite: scalarWrite(.urgency, value: "2", existingValue: nil, action: .write)
        )
        let engine = OwnedXMPSidecarEngine()

        for operation in [
            { try engine.preview(XMPWriteRequest(plan: plan)) as Any },
            { try engine.apply(XMPWriteRequest(plan: plan)) as Any },
        ] {
            XCTAssertThrowsError(try operation()) { error in
                XCTAssertEqual((error as? SidecarError)?.code, .validationFailed)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testOwnedEngineRejectsConflictingScalarsWithoutReplacingFile() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("ConflictingScalars.xmp")
        try conflictingScalarXMP.write(to: target, atomically: true, encoding: .utf8)
        let originalBytes = try Data(contentsOf: target)
        let plan = changePlan(
            targetPath: target.path,
            flat: [],
            hierarchical: [],
            ratingWrite: scalarWrite(.rating, value: "5", existingValue: nil, action: .overwrite)
        )

        XCTAssertThrowsError(try OwnedXMPSidecarEngine().apply(XMPWriteRequest(plan: plan))) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
        }
        XCTAssertEqual(try Data(contentsOf: target), originalBytes)
    }

    func testOwnedEnginePreviewRejectsIncompatiblePreferredPrefixWithoutWriting() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("BadPrefix.xmp")
        let original = """
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xmp="urn:foreign">
              <rdf:Description rdf:about=""/>
            </rdf:RDF>
            """
        try original.write(to: target, atomically: true, encoding: .utf8)
        let plan = changePlan(
            targetPath: target.path,
            flat: [],
            hierarchical: [],
            labelWrite: scalarWrite(.label, value: "Green", existingValue: nil, action: .write)
        )

        XCTAssertThrowsError(try OwnedXMPSidecarEngine().preview(XMPWriteRequest(plan: plan))) { error in
            XCTAssertEqual((error as? SidecarError)?.code, .xmpUnsupportedRDF)
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
    }

    func testOwnedEngineMergesExistingSidecarAndPreservesUnmanagedFingerprint() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Existing.xmp")
        try existingDevelopSettingsXMP.write(to: target, atomically: true, encoding: .utf8)
        let engine = OwnedXMPSidecarEngine()
        let preSnapshot = try engine.readSnapshot(at: target.path)

        let result = try engine.apply(
            XMPWriteRequest(
                plan: changePlan(
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

        _ = try engine.apply(
            XMPWriteRequest(
                plan: changePlan(
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

        XCTAssertThrowsError(
            try OwnedXMPSidecarEngine().apply(
                XMPWriteRequest(
                    plan: changePlan(
                        targetPath: target.path,
                        flat: ["new keyword"],
                        hierarchical: [],
                        ratingWrite: scalarWrite(.rating, value: "4", existingValue: nil, action: .write)
                    )))
        ) { error in
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
        hierarchical: [String],
        ratingWrite: PlannedScalarWrite? = nil,
        labelWrite: PlannedScalarWrite? = nil,
        urgencyWrite: PlannedScalarWrite? = nil
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
            failures: [],
            ratingWrite: ratingWrite,
            labelWrite: labelWrite,
            urgencyWrite: urgencyWrite
        )
    }

    private func scalarWrite(
        _ scalar: XMPManagedScalar,
        value: String,
        existingValue: String?,
        action: PlannedScalarWrite.Action
    ) -> PlannedScalarWrite {
        PlannedScalarWrite(
            field: scalar.qualifiedPropertyName,
            plannedValue: value,
            existingValue: existingValue,
            action: action
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

private let attributeScalarXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/"
             xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="" xmp:Rating="4" xmp:Label="Green" photoshop:Urgency="2"/>
    </rdf:RDF>
    """

private let elementScalarXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:quality="http://ns.adobe.com/xap/1.0/"
             xmlns:ps="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="">
        <quality:Rating>4</quality:Rating>
        <quality:Label>Green</quality:Label>
        <ps:Urgency>2</ps:Urgency>
      </rdf:Description>
    </rdf:RDF>
    """

private let equalDuplicateScalarXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/"
             xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="first" xmp:Rating="4" xmp:Label="Green" photoshop:Urgency="2"/>
      <rdf:Description rdf:about="second">
        <xmp:Rating> 4 </xmp:Rating>
        <xmp:Label> Green </xmp:Label>
        <photoshop:Urgency> 2 </photoshop:Urgency>
      </rdf:Description>
    </rdf:RDF>
    """

private let conflictingScalarXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/"
             xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="first" xmp:Rating="4" xmp:Label="Green" photoshop:Urgency="2"/>
      <rdf:Description rdf:about="second">
        <xmp:Rating>3</xmp:Rating>
        <xmp:Label>Red</xmp:Label>
        <photoshop:Urgency>1</photoshop:Urgency>
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

private let foreignScalarXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="foreign-fixture">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:dc="http://purl.org/dc/elements/1.1/"
               xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
               xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
               xmlns:xmp="http://ns.adobe.com/xap/1.0/"
               xmlns:foreign="urn:example:foreign">
        <rdf:Description rdf:about="" xmp:Rating="3" foreign:Preserve="yes">
          <dc:subject><rdf:Bag><rdf:li>existing bird</rdf:li></rdf:Bag></dc:subject>
          <lr:hierarchicalSubject><rdf:Bag><rdf:li>existing habitat</rdf:li></rdf:Bag></lr:hierarchicalSubject>
          <crs:Exposure2012>+0.35</crs:Exposure2012>
          <foreign:Custom>keep me</foreign:Custom>
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
