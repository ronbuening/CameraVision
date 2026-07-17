import Foundation
import XCTest

@testable import AISidecarCore

final class XMPMergeValidatorTests: XCTestCase {
    func testValidatesKeywordAdditionsAndUnmanagedPreservation() throws {
        let pre = try snapshot(from: existingDevelopSettingsXMP, path: "/tmp/Bird.xmp")
        let post = try snapshot(
            from: existingDevelopSettingsXMP.replacingOccurrences(
                of: "<rdf:li>existing bird</rdf:li>",
                with: "<rdf:li>existing bird</rdf:li><rdf:li>marsh</rdf:li>"
            )
            .replacingOccurrences(
                of: "<rdf:li>existing habitat</rdf:li>",
                with: "<rdf:li>existing habitat</rdf:li><rdf:li>marsh</rdf:li>"
            ),
            path: "/tmp/Bird.xmp"
        )

        let result = XMPMergeValidator().validate(
            plan: changePlan(targetPath: "/tmp/Bird.xmp", flat: ["marsh"], hierarchical: ["marsh"]),
            preWriteSnapshot: pre,
            postWriteSnapshot: post
        )

        XCTAssertTrue(result.valid)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.unmanagedContentPreserved)
        XCTAssertEqual(result.preservedFlatKeywords, ["existing bird"])
        XCTAssertEqual(result.preservedHierarchicalKeywords, ["existing habitat"])
    }

    func testDetectsMissingKeywordAndUnmanagedFingerprintChange() throws {
        let pre = try snapshot(from: existingDevelopSettingsXMP, path: "/tmp/Bird.xmp")
        let post = try snapshot(
            from:
                existingDevelopSettingsXMP
                .replacingOccurrences(of: "<rdf:li>existing bird</rdf:li>", with: "")
                .replacingOccurrences(of: "<crs:Contrast2012>12</crs:Contrast2012>", with: ""),
            path: "/tmp/Bird.xmp"
        )

        let result = XMPMergeValidator().validate(
            plan: changePlan(targetPath: "/tmp/Bird.xmp", flat: ["marsh"], hierarchical: []),
            preWriteSnapshot: pre,
            postWriteSnapshot: post
        )

        XCTAssertFalse(result.valid)
        XCTAssertEqual(result.errors.map(\.code), [.validationFailed, .validationFailed, .validationFailed])
        XCTAssertFalse(result.unmanagedContentPreserved)
    }

    func testScalarValidationAcceptsEveryPlannedValue() {
        for scalarCase in scalarCases {
            let result = validateScalar(
                scalarCase.scalar,
                plannedValue: scalarCase.newValue,
                preWriteValue: scalarCase.oldValue,
                postWriteValue: scalarCase.newValue
            )

            XCTAssertTrue(result.valid, scalarCase.scalar.qualifiedPropertyName)
            XCTAssertTrue(result.errors.isEmpty, scalarCase.scalar.qualifiedPropertyName)
        }
    }

    func testScalarValidationRejectsEveryMissingPlannedValue() {
        for scalarCase in scalarCases {
            let result = validateScalar(
                scalarCase.scalar,
                plannedValue: scalarCase.newValue,
                preWriteValue: scalarCase.oldValue,
                postWriteValue: scalarCase.oldValue
            )

            XCTAssertFalse(result.valid, scalarCase.scalar.qualifiedPropertyName)
            XCTAssertEqual(result.errors.map(\.code), [.validationFailed])
            XCTAssertTrue(result.errors[0].message.contains(scalarCase.scalar.qualifiedPropertyName))
        }
    }

    func testScalarValidationAcceptsEveryPreservedUnplannedValue() {
        for scalarCase in scalarCases {
            let result = validateScalar(
                scalarCase.scalar,
                plannedValue: nil,
                preWriteValue: scalarCase.oldValue,
                postWriteValue: scalarCase.oldValue
            )

            XCTAssertTrue(result.valid, scalarCase.scalar.qualifiedPropertyName)
            XCTAssertTrue(result.errors.isEmpty, scalarCase.scalar.qualifiedPropertyName)
        }
    }

    func testScalarValidationRejectsEveryChangedUnplannedValue() {
        for scalarCase in scalarCases {
            let result = validateScalar(
                scalarCase.scalar,
                plannedValue: nil,
                preWriteValue: scalarCase.oldValue,
                postWriteValue: scalarCase.newValue
            )

            XCTAssertFalse(result.valid, scalarCase.scalar.qualifiedPropertyName)
            XCTAssertEqual(result.errors.map(\.code), [.validationFailed])
            XCTAssertTrue(result.errors[0].message.contains(scalarCase.scalar.qualifiedPropertyName))
        }
    }

    private func snapshot(from xml: String, path: String) throws -> XMPMetadataSnapshot {
        let parsed = try XMPDocumentParser().parse(data: Data(xml.utf8), targetPath: path)
        return try XMPMetadataSnapshot.make(targetPath: path, exists: true, parsed: parsed)
    }

    private func validateScalar(
        _ scalar: XMPManagedScalar,
        plannedValue: String?,
        preWriteValue: String?,
        postWriteValue: String?
    ) -> XMPMergeValidationResult {
        let path = "/tmp/ScalarValidation.xmp"
        let pre = scalarSnapshot(path: path, scalar: scalar, value: preWriteValue)
        let post = scalarSnapshot(path: path, scalar: scalar, value: postWriteValue)
        let plan = changePlan(targetPath: path, flat: [], hierarchical: [])

        switch scalar {
        case .rating:
            return XMPMergeValidator().validate(
                plan: plan,
                preWriteSnapshot: pre,
                postWriteSnapshot: post,
                plannedRating: plannedValue
            )
        case .label:
            return XMPMergeValidator().validate(
                plan: plan,
                preWriteSnapshot: pre,
                postWriteSnapshot: post,
                plannedLabel: plannedValue
            )
        case .urgency:
            return XMPMergeValidator().validate(
                plan: plan,
                preWriteSnapshot: pre,
                postWriteSnapshot: post,
                plannedUrgency: plannedValue
            )
        }
    }

    private func scalarSnapshot(path: String, scalar: XMPManagedScalar, value: String?) -> XMPMetadataSnapshot {
        var snapshot = XMPMetadataSnapshot(
            targetPath: path,
            exists: true,
            flatKeywords: [],
            hierarchicalKeywords: [],
            unmanagedContentFingerprint: .empty()
        )
        switch scalar {
        case .rating:
            snapshot.rating = value
        case .label:
            snapshot.label = value
        case .urgency:
            snapshot.urgency = value
        }
        return snapshot
    }
}

private let scalarCases: [(scalar: XMPManagedScalar, oldValue: String, newValue: String)] = [
    (.rating, "3", "4"),
    (.label, "Red", "Green"),
    (.urgency, "1", "2"),
]

private func changePlan(targetPath: String, flat: [String], hierarchical: [String]) -> XMPChangePlan {
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
        backupPlan: BackupPlan(backupSidecars: false, backupRequiredBeforeMerge: false, conflictPolicy: .merge),
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
