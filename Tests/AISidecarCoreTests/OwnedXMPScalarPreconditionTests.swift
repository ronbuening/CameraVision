import Foundation
import XCTest

@testable import AISidecarCore

final class OwnedXMPScalarPreconditionTests: XCTestCase {
    func testPreviewAndApplyRejectStaleMutatingScalarPlansWithoutChangingBytes() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let originalData = Data(existingScalarsXMP.utf8)
        let cases: [(XMPManagedScalar, PlannedScalarWrite.Action, String?)] = [
            (.rating, .write, nil),
            (.label, .overwrite, "Red"),
            (.urgency, .overwrite, "1"),
        ]

        for (index, scalarCase) in cases.enumerated() {
            let (scalar, action, plannedExistingValue) = scalarCase
            let target = root.appendingPathComponent("Stale-\(index).xmp")
            try originalData.write(to: target)
            let plan = changePlan(
                targetPath: target.path,
                scalar: scalar,
                plannedValue: "5",
                existingValue: plannedExistingValue,
                action: action
            )
            let request = XMPWriteRequest(plan: plan)
            let engine = OwnedXMPSidecarEngine()

            for operation: () throws -> Void in [
                { _ = try engine.preview(request) },
                { _ = try engine.apply(request) },
            ] {
                XCTAssertThrowsError(try operation()) { error in
                    let sidecarError = (error as? XMPScalarWritePreconditionFailure)?.sidecarError
                    XCTAssertEqual(sidecarError?.code, .validationFailed)
                    XCTAssertEqual(sidecarError?.stage, .write)
                    XCTAssertEqual(sidecarError?.recoverable, true)
                    XCTAssertTrue(sidecarError?.message.contains(scalar.qualifiedPropertyName) == true)
                }
                XCTAssertEqual(try? Data(contentsOf: target), originalData)
            }
        }
    }

    func testPreviewAndApplyRejectPlanThatExpectedScalarOnMissingTarget() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Missing.xmp")
        let plan = changePlan(
            targetPath: target.path,
            scalar: .rating,
            plannedValue: "5",
            existingValue: "4",
            action: .overwrite
        )
        let request = XMPWriteRequest(plan: plan)
        let engine = OwnedXMPSidecarEngine()

        XCTAssertThrowsError(try engine.preview(request)) { error in
            XCTAssertEqual(
                (error as? XMPScalarWritePreconditionFailure)?.sidecarError.code, .validationFailed)
        }
        XCTAssertThrowsError(try engine.apply(request)) { error in
            XCTAssertEqual(
                (error as? XMPScalarWritePreconditionFailure)?.sidecarError.code, .validationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testStaleSkipExistingScalarDoesNotTriggerMutatingPrecondition() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Skipped.xmp")
        let originalData = Data(existingScalarsXMP.utf8)
        try originalData.write(to: target)
        let plan = changePlan(
            targetPath: target.path,
            scalar: .rating,
            plannedValue: "5",
            existingValue: "3",
            action: .skipExisting
        )
        let request = XMPWriteRequest(plan: plan)
        let engine = OwnedXMPSidecarEngine()

        let preview = try engine.preview(request)
        let result = try engine.apply(request)

        XCTAssertEqual(preview.resultingRating, "4")
        XCTAssertFalse(result.modified)
        XCTAssertEqual(try Data(contentsOf: target), originalData)
    }

    func testPipelineDoesNotRestoreBackupOverPostPlanUserScalarEdit() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("User-Edited.xmp")
        try Data(existingRatingThreeXMP.utf8).write(to: target)
        let userEditedData = Data(existingRatingFiveXMP.utf8)
        var plan = changePlan(
            targetPath: target.path,
            scalar: .rating,
            plannedValue: "4",
            existingValue: "3",
            action: .overwrite
        )
        plan.backupPlan = BackupPlan(
            backupSidecars: true,
            backupRequiredBeforeMerge: false,
            conflictPolicy: .merge
        )
        let pipeline = XMPExportPipeline(
            afterBackup: {
                try! userEditedData.write(to: target)
            }
        )

        let result = try pipeline.runChangePlan(
            XMPChangePlanDocument(dryRun: false, targetPlans: [plan], inputFailures: []),
            inputPath: root.path,
            configuration: .builtInDefaults
        )

        XCTAssertEqual(result.report?.targetReports.first?.status, .failed)
        XCTAssertEqual(result.report?.targetReports.first?.errors.first?.code, .validationFailed)
        XCTAssertEqual(try Data(contentsOf: target), userEditedData)
    }

    func testUrgencyMutationRejectsStaleSkippedLabelInPreviewAndApply() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Stale-Label.xmp")
        let staleData = Data(blueLabelUrgencyOneXMP.utf8)
        try staleData.write(to: target)
        let request = XMPWriteRequest(plan: coupledUrgencyPlan(targetPath: target.path))
        let engine = OwnedXMPSidecarEngine()

        XCTAssertThrowsError(try engine.preview(request)) { error in
            XCTAssertTrue(error is XMPScalarWritePreconditionFailure)
        }
        XCTAssertThrowsError(try engine.apply(request)) { error in
            XCTAssertTrue(error is XMPScalarWritePreconditionFailure)
        }
        XCTAssertEqual(try Data(contentsOf: target), staleData)
    }

    func testPipelinePreservesLabelEditMadeAfterBackupInsteadOfWritingUrgency() throws {
        let root = try temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Post-Backup-Label.xmp")
        try Data(greenLabelUrgencyOneXMP.utf8).write(to: target)
        let userEditedData = Data(blueLabelUrgencyOneXMP.utf8)
        var plan = coupledUrgencyPlan(targetPath: target.path)
        plan.backupPlan = BackupPlan(
            backupSidecars: true,
            backupRequiredBeforeMerge: false,
            conflictPolicy: .merge
        )
        let pipeline = XMPExportPipeline(
            logger: Logger(sink: { _ in }),
            afterBackup: {
                try! userEditedData.write(to: target)
            }
        )

        let result = try pipeline.runChangePlan(
            XMPChangePlanDocument(dryRun: false, targetPlans: [plan], inputFailures: []),
            inputPath: root.path,
            configuration: .builtInDefaults
        )

        XCTAssertEqual(result.report?.targetReports.first?.status, .failed)
        XCTAssertEqual(try Data(contentsOf: target), userEditedData)
        let snapshot = try OwnedXMPSidecarEngine().readSnapshot(at: target.path)
        XCTAssertEqual(snapshot.label, "Blue")
        XCTAssertEqual(snapshot.urgency, "1")
    }

    private func changePlan(
        targetPath: String,
        scalar: XMPManagedScalar,
        plannedValue: String,
        existingValue: String?,
        action: PlannedScalarWrite.Action
    ) -> XMPChangePlan {
        var plan = XMPChangePlan(
            status: .planned,
            targetXMPPath: targetPath,
            targetRelativePath: URL(fileURLWithPath: targetPath).lastPathComponent,
            pairScope: .union,
            sourceMembers: [],
            flatKeywordsToAdd: [],
            hierarchicalKeywordsToAdd: [],
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
        let write = PlannedScalarWrite(
            field: scalar.qualifiedPropertyName,
            plannedValue: plannedValue,
            existingValue: existingValue,
            action: action
        )
        switch scalar {
        case .rating:
            plan.ratingWrite = write
        case .label:
            plan.labelWrite = write
        case .urgency:
            plan.urgencyWrite = write
        }
        return plan
    }

    private func coupledUrgencyPlan(targetPath: String) -> XMPChangePlan {
        var plan = changePlan(
            targetPath: targetPath,
            scalar: .urgency,
            plannedValue: "2",
            existingValue: "1",
            action: .overwrite
        )
        plan.labelWrite = PlannedScalarWrite(
            field: XMPManagedScalar.label.qualifiedPropertyName,
            plannedValue: "Green",
            existingValue: "Green",
            action: .skipExisting
        )
        return plan
    }
}

private let existingScalarsXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/"
             xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="" xmp:Rating="4" xmp:Label="Green" photoshop:Urgency="2"/>
    </rdf:RDF>
    """

private let existingRatingThreeXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/">
      <rdf:Description rdf:about="" xmp:Rating="3"/>
    </rdf:RDF>
    """

private let existingRatingFiveXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/">
      <rdf:Description rdf:about="" xmp:Rating="5"/>
    </rdf:RDF>
    """

private let greenLabelUrgencyOneXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/"
             xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="" xmp:Label="Green" photoshop:Urgency="1"/>
    </rdf:RDF>
    """

private let blueLabelUrgencyOneXMP = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:xmp="http://ns.adobe.com/xap/1.0/"
             xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
      <rdf:Description rdf:about="" xmp:Label="Blue" photoshop:Urgency="1"/>
    </rdf:RDF>
    """
