//
//  DesktopControlEvidenceTimeline.swift
//  CodeAgent
//
//  Product-only Timeline extension. MCP lifecycle and calls belong to the Go
//  runtime; this extension only projects Agent Wire tool_finished events.
//

#if os(macOS)
import AgentKit
import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class DesktopControlEvidenceTimeline: WebTimelineExtension {
    let id = "com.objc.codeagent.desktop-control-evidence"

    private var cards: [DesktopEvidenceCard] = []

    func handle(_ event: AgentEvent) async {
        guard case .toolFinished(let turnID, let callID, let result) = event else { return }

        switch result.toolName {
        case "mcp__desktop_control__action_commit":
            registerActionCommit(
                callID: callID,
                turnID: turnID,
                output: result.output
            )

        case "mcp__desktop_control__evidence_timeline_item_get":
            registerTimelineItem(turnID: turnID, output: result.output)

        case "mcp__desktop_control__evidence_bundle_export":
            registerBundle(output: result.output)

        default:
            break
        }
    }

    func makeContent(for turnID: String) -> AnyView? {
        let turnCards = cards.filter { $0.turnID == turnID }
        guard !turnCards.isEmpty else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(turnCards) { card in
                    DesktopEvidenceTimelineCard(card: card)
                }
            }
        )
    }

    func makeWebNodes(for turnID: String) -> [TimelineWebNode] {
        cards.filter { $0.turnID == turnID }.map { card in
            guard let item = card.item else {
                return TimelineWebNode(
                    id: card.id,
                    title: "正在等待 Evidence Timeline…",
                    summary: card.auditEventID,
                    status: "pending",
                    tone: .neutral
                )
            }

            var documentActions: [TimelineWebNode.ActionReference] = []
            if let markdown = item.documents.markdown {
                documentActions.append(.document(
                    id: "\(markdown.id).open",
                    title: "Markdown",
                    tooltip: markdown.title,
                    document: TimelineWebDocument(
                        id: markdown.id,
                        title: markdown.title,
                        format: .markdown,
                        body: markdown.body
                    )
                ))
            }
            if let html = item.documents.html {
                documentActions.append(.document(
                    id: "\(html.id).open",
                    title: "HTML",
                    tooltip: html.title,
                    document: TimelineWebDocument(
                        id: html.id,
                        title: html.title,
                        format: .html,
                        body: html.body
                    )
                ))
            }

            return TimelineWebNode(
                id: card.id,
                title: item.title,
                summary: item.summary,
                status: item.status,
                tone: webTone(for: item.status),
                badges: [
                    .init(id: "action", text: item.actionType, tone: .info),
                    .init(id: "target", text: item.target),
                    .init(id: "risk", text: item.risk, tone: item.risk == "high" ? .warning : .neutral),
                ],
                sections: item.sections.map { section in
                    .init(
                        id: section.id,
                        title: section.title,
                        summary: section.summary,
                        status: section.status,
                        rows: section.rows.map {
                            .init(id: $0.id, label: $0.label, value: $0.displayValue)
                        }
                    )
                },
                actions: documentActions,
                footer: card.bundle.map { "证据 bundle 已导出 · \($0.artifact.uri)" }
            )
        }
    }

    private func webTone(for status: String) -> TimelineWebNode.Tone {
        switch status {
        case "passed": return .success
        case "failed", "error": return .danger
        case "observed": return .info
        case "unavailable": return .warning
        default: return .neutral
        }
    }

    private func registerActionCommit(callID: String, turnID: String?, output: JSONValue?) {
        guard let auditEventID = output?["evidence"]["auditEventID"].string,
              !auditEventID.isEmpty,
              !cards.contains(where: { $0.callID == callID })
        else { return }

        cards.append(DesktopEvidenceCard(
            callID: callID,
            turnID: turnID,
            auditEventID: auditEventID,
            item: nil,
            bundle: nil
        ))
    }

    private func registerTimelineItem(turnID: String?, output: JSONValue?) {
        guard let item = decode(DesktopEvidenceTimelineItem.self, from: output),
              item.isSupported
        else { return }

        if let index = cards.firstIndex(where: { $0.auditEventID == item.auditEventID }) {
            cards[index].item = item
        } else {
            // History may have been pruned before the action_commit event, but
            // a Timeline item alone is still enough to render a card.
            cards.append(DesktopEvidenceCard(
                callID: item.itemID,
                turnID: turnID,
                auditEventID: item.auditEventID,
                item: item,
                bundle: nil
            ))
        }
    }

    private func registerBundle(output: JSONValue?) {
        guard let bundle = decode(DesktopEvidenceBundle.self, from: output),
              !bundle.artifact.uri.isEmpty,
              let index = cards.firstIndex(where: { $0.auditEventID == bundle.manifest.auditEventID })
        else { return }
        cards[index].bundle = bundle
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: JSONValue?) -> T? {
        guard let output, let data = try? JSONEncoder().encode(output) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - desktop-control render model (plugin-private)

private struct DesktopEvidenceTimelineItem: Decodable, Equatable, Identifiable {
    let schemaVersion: String
    let type: String
    let itemID: String
    let auditEventID: String
    let title: String
    let status: String
    let summary: String
    let actionType: String
    let target: String
    let risk: String
    let sections: [DesktopEvidenceSection]
    let documents: DesktopEvidenceDocuments

    var id: String { itemID }
    var isSupported: Bool {
        schemaVersion == "desktop-control.timeline-evidence.v1"
            && type == "desktop_action_evidence"
    }
}

private struct DesktopEvidenceSection: Decodable, Equatable, Identifiable {
    let sectionID: String
    let kind: String
    let title: String
    let status: String
    let summary: String
    let rows: [DesktopEvidenceRow]
    var id: String { sectionID }
}

private struct DesktopEvidenceRow: Decodable, Equatable, Identifiable {
    let label: String
    let value: JSONValue
    var id: String { label }
    var displayValue: String { value.prettyJSONString ?? value.stringValue }
}

private struct DesktopEvidenceDocuments: Decodable, Equatable {
    let markdown: DesktopEvidenceDocument?
    let html: DesktopEvidenceDocument?
}

private struct DesktopEvidenceDocument: Decodable, Equatable, Identifiable {
    let body: String
    let format: String
    let reportID: String
    let title: String
    var id: String { "\(reportID).\(format)" }
}

private struct DesktopEvidenceBundle: Decodable, Equatable {
    let artifact: Artifact
    let manifest: Manifest

    struct Artifact: Decodable, Equatable {
        let uri: String
    }

    struct Manifest: Decodable, Equatable {
        let auditEventID: String
    }
}

private struct DesktopEvidenceCard: Identifiable, Equatable {
    let callID: String
    let turnID: String?
    let auditEventID: String
    var item: DesktopEvidenceTimelineItem?
    var bundle: DesktopEvidenceBundle?
    var id: String { callID }
}

// MARK: - Card and document fallbacks

private struct DesktopEvidenceTimelineCard: View {
    let card: DesktopEvidenceCard
    @State private var fallbackDocument: DesktopEvidenceDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item = card.item {
                itemContent(item)
            } else {
                Label("正在等待 Evidence Timeline…", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(card.auditEventID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(item: $fallbackDocument) { DesktopEvidenceFallbackDocument(document: $0) }
    }

    @ViewBuilder
    private func itemContent(_ item: DesktopEvidenceTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(for: item.status)).foregroundStyle(color(for: item.status))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(item.status).font(.caption2.weight(.medium)).foregroundStyle(color(for: item.status))
        }

        HStack(spacing: 6) {
            tag(item.actionType, icon: "cursorarrow.click")
            tag(item.target, icon: "viewfinder")
            tag(item.risk, icon: "shield")
        }

        ForEach(item.sections) { section in
            DisclosureGroup {
                if !section.rows.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                        ForEach(section.rows) { row in
                            GridRow {
                                Text(row.label).foregroundStyle(.secondary)
                                Text(row.displayValue).textSelection(.enabled)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: icon(for: section.status)).foregroundStyle(color(for: section.status))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title).font(.caption.weight(.medium))
                        Text(section.summary).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }

        HStack(spacing: 12) {
            if let markdown = item.documents.markdown {
                Button("Markdown") { fallbackDocument = markdown }.buttonStyle(.plain)
            }
            if let html = item.documents.html {
                Button("HTML") { fallbackDocument = html }.buttonStyle(.plain)
            }
            Spacer()
            if let bundle = card.bundle {
                Label("证据 bundle 已导出", systemImage: "link")
                    .help(bundle.artifact.uri)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func tag(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3)
            .background(.quaternary).clipShape(Capsule())
    }

    private func icon(for status: String) -> String {
        switch status {
        case "passed": return "checkmark.seal.fill"
        case "failed", "error": return "xmark.octagon.fill"
        case "observed": return "eye.fill"
        case "unavailable": return "questionmark.circle.fill"
        default: return "circle.fill"
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "passed": return .green
        case "failed", "error": return .red
        case "observed": return .blue
        default: return .secondary
        }
    }
}

private struct DesktopEvidenceFallbackDocument: View {
    let document: DesktopEvidenceDocument

    var body: some View {
        NavigationStack {
            Group {
                if document.format.lowercased() == "html" {
                    DesktopEvidenceHTMLView(html: document.body)
                } else {
                    ScrollView {
                        Text(document.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
            .navigationTitle(document.title)
        }
    }
}

private struct DesktopEvidenceHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#endif
