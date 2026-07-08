import AISidecarCore
import AppKit
import SwiftUI

/// Wizard Step 5 — candidate review (design doc §6 Step 5): per-image rows
/// with keyword chips, batch operations, session save/import, and the
/// FR4-046a recovery banner.
struct Step5ReviewView: View {
    @Bindable var review: ReviewModel
    var runOutcome: RunOutcome?

    @Environment(\.cvTheme) private var theme
    @State private var thumbnails = ThumbnailStore()
    @State private var editing: ReviewModel.Chip?
    @State private var editText = ""
    @State private var editEverywhere = false
    @State private var batchEditNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if review.recoveryAvailable, review.session == nil {
                recoveryBanner
                    .padding(.top, 14)
            }

            if let error = review.buildError ?? review.fileError {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.danger)
                    .padding(.top, 12)
            }

            if let batchEditNotice {
                Text(batchEditNotice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.accent.accent)
                    .padding(.top, 12)
            }

            if review.building {
                HStack(spacing: 10) {
                    ApertureView(size: 28, running: true, spin: true)
                    Text("Preparing candidates from the analysis sidecars…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textDim)
                }
                .padding(.top, 16)
            }

            LazyVStack(spacing: 10) {
                ForEach(review.assetRows) { row in
                    assetRow(row)
                }
            }
            .padding(.top, 16)
        }
        .padding(EdgeInsets(top: 24, leading: 34, bottom: 40, trailing: 34))
        .alert("Edit keyword", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField("Keyword", text: $editText)
            Button("Apply") {
                if let chip = editing {
                    batchEditNotice = nil
                    review.editKeyword(chip.decisionID, to: editText)
                }
                editing = nil
            }
            Button("Apply to all photos with “\(editing?.keyword ?? "")”") {
                if let chip = editing {
                    let applied = review.editEverywhere(keyword: chip.keyword, to: editText)
                    batchEditNotice = "Applied to \(applied) photo(s)"
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text("Replaces the keyword text; the original stays recorded in the session (source_text).")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(theme.green)
                Text("✓").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review AI keywords")
                    .font(.system(size: 20, weight: .bold))
                    .kerning(-0.3)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textDim)
            }
            Spacer()
            headerButton("Reject all", enabled: review.canSaveSession) {
                batchEditNotice = nil
                review.setAllVisible(.rejected)
            }
            headerButton("Approve all", enabled: review.canSaveSession) {
                batchEditNotice = nil
                review.setAllVisible(.approved)
            }
            headerButton("Import session…") { importSession() }
            headerButton("Save session only", filled: true, enabled: review.canSaveSession) { saveSession() }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let runOutcome {
            parts.append("\(runOutcome.written + runOutcome.skipped) analyzed")
        }
        parts.append("\(review.approvedCount) approved · \(review.rejectedCount) rejected · \(review.deferredCount) deferred")
        return parts.joined(separator: " · ")
    }

    private func headerButton(
        _ label: String,
        filled: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(filled ? theme.text : theme.textDim)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(filled ? AnyShapeStyle(theme.panel2) : AnyShapeStyle(.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.borderStrong))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private var recoveryBanner: some View {
        HStack(spacing: 10) {
            ApertureView(size: 20)
            Text("An unsaved review from a previous session was recovered.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.text)
            Spacer()
            headerButton("Discard") { review.discardRecovery() }
            headerButton("Restore", filled: true) {
                do { try review.restoreFromRecovery(); review.clearFileError() }
                catch { review.reportFileError("Restore recovered review", error) }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
        .background(theme.accent.soft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.accent.accent.opacity(0.5)))
    }

    // MARK: - Rows

    private func assetRow(_ row: ReviewModel.AssetRow) -> some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(spacing: 5) {
                RowThumbnail(path: row.sourcePath, fallback: row.fileExtension, thumbnails: thumbnails)
                Text(row.fileName)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 70)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(row.fileExtension)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent.accent)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(theme.accent.soft)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("\(row.chips.count { $0.verdict == .approved }) of \(row.chips.count) approved")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.textFaint)
                    Spacer()
                    Button("Accept all") {
                        batchEditNotice = nil
                        review.acceptAll(assetID: row.assetID)
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.borderStrong))
                }
                FlowLayout(spacing: 7) {
                    ForEach(row.chips) { chip in
                        chipView(chip)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border))
    }

    private func chipView(_ chip: ReviewModel.Chip) -> some View {
        let (mark, fg, bg, border): (String, Color, Color, Color) = switch chip.verdict {
        case .approved: ("✓", theme.green, theme.greenSoft, theme.green)
        case .rejected: ("+", theme.textDim, theme.panel2, theme.borderStrong)
        case .deferred: ("~", theme.accent.accent, theme.accent.soft, theme.accent.accent)
        }
        return Button {
            batchEditNotice = nil
            review.toggle(chip.decisionID)
        } label: {
            HStack(spacing: 6) {
                Text(mark).font(.system(size: 11))
                Text(chip.keyword)
                    .font(.system(size: 12, weight: .semibold))
                if let confidence = chip.confidence {
                    Text(confidence.rawValue)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(fg)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(bg)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(border))
        }
        .buttonStyle(.plain)
        .help(chip.detail)
        .contextMenu {
            Button("Approve") {
                batchEditNotice = nil
                review.setVerdict(.approved, for: chip.decisionID)
            }
            Button("Reject") {
                batchEditNotice = nil
                review.setVerdict(.rejected, for: chip.decisionID)
            }
            Button("Defer") {
                batchEditNotice = nil
                review.setVerdict(.deferred, for: chip.decisionID)
            }
            Divider()
            Button("Edit…") {
                editText = chip.keyword
                editing = chip
            }
        }
    }

    // MARK: - Save / import panels

    private func saveSession() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "review-session.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try review.saveSession(to: url); review.clearFileError() }
            catch { review.reportFileError("Save session", error) }
        }
    }

    private func importSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try review.importSession(from: url); review.clearFileError() }
            catch { review.reportFileError("Import session", error) }
        }
    }
}

/// Thumbnail cell reusing the M3 store; falls back to the extension label.
private struct RowThumbnail: View {
    let path: String?
    let fallback: String
    let thumbnails: ThumbnailStore

    @Environment(\.cvTheme) private var theme
    @State private var thumbnail: Thumbnail?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(theme.panel2)
                    .overlay(
                        Text(fallback)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.textFaint)
                    )
            }
        }
        .frame(width: 70, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
        .task(id: path) {
            guard let path else { return }
            thumbnail = await thumbnails.thumbnail(for: path)
        }
    }
}

/// Minimal wrapping layout for keyword chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for (subview, position) in zip(subviews, arrangement.positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}
