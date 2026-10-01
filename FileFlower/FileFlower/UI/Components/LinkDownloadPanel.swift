import SwiftUI

/// Inklapbaar paneel bovenin het Downloads-tabblad: plak een link, kies een
/// kwaliteit en de download valt in de watchmap — vanaf daar neemt de normale
/// pijplijn (classificatie → wachtrij → plaatsing) het over.
struct LinkDownloadPanel: View {
    @StateObject private var downloader = LinkDownloader.shared
    @AppStorage("linkDownloadPanelExpanded") private var isExpanded = false
    @State private var linkText = ""
    @State private var format: LinkDownloader.Format = .best
    @State private var showInvalidLink = false
    @FocusState private var linkFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                panelBody
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                if !downloader.jobs.isEmpty {
                    jobsList
                }
            }
            Rectangle()
                .fill(Color.line)
                .frame(height: 1)
        }
    }

    // MARK: - Kop (zelfde idioom als QueueSectionHeader)

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            if isExpanded { downloader.prepareIfNeeded() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.ink3)

                Text(String(localized: "linkdl.header").uppercased())
                    .font(.brandMono(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.ink3)

                if downloader.activeJobCount > 0 {
                    Text("\(downloader.activeJobCount)")
                        .font(.brandMono(size: 10, weight: .semibold))
                        .foregroundColor(.brandBurntPeach)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.ink4)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.popSurfaceAlt.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invoer

    @ViewBuilder
    private var panelBody: some View {
        switch downloader.toolState {
        case .missing:
            Text(String(localized: "linkdl.tool_missing"))
                .font(.system(size: 11))
                .foregroundColor(.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .idle:
            Text(String(localized: "linkdl.preparing"))
                .font(.system(size: 11))
                .foregroundColor(.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ready:
            inputRows
        }
    }

    private var inputRows: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(String(localized: "linkdl.placeholder"), text: $linkText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($linkFieldFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.cardBg))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(showInvalidLink ? Color.statusBad.opacity(0.6) : Color.line2, lineWidth: 1)
                    )
                    .onSubmit { start() }
                    .onChange(of: linkText) { showInvalidLink = false }

                Button {
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        linkText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text(String(localized: "linkdl.paste"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().stroke(Color.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                formatChip(.best, label: String(localized: "linkdl.quality.best"))
                formatChip(.fullHD, label: String(localized: "linkdl.quality.hd"))
                formatChip(.audio, label: String(localized: "linkdl.quality.audio"))

                Spacer()

                Button(action: start) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(localized: "linkdl.start"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(canStart ? .white : .ink4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(canStart ? Color.brandBurntPeach : Color.popSurfaceAlt))
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
            }

            HStack(spacing: 4) {
                Text("→ \(LinkDownloader.destinationFolder.lastPathComponent)")
                if case .ready(let version) = downloader.toolState {
                    Text("· yt-dlp \(version)")
                }
                Spacer()
            }
            .font(.brandMono(size: 9))
            .foregroundColor(.ink4)
        }
    }

    private func formatChip(_ value: LinkDownloader.Format, label: String) -> some View {
        Button {
            format = value
        } label: {
            Text(label)
                .font(.system(size: 10, weight: format == value ? .semibold : .regular))
                .foregroundColor(format == value ? .brandBurntPeach : .ink3)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(format == value ? Color.brandBurntPeach.opacity(0.1) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(format == value ? Color.brandBurntPeach.opacity(0.5) : Color.line2, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var canStart: Bool {
        downloader.isReady && !linkText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func start() {
        guard canStart else { return }
        guard LinkDownloader.isValidLink(linkText) else {
            showInvalidLink = true
            return
        }
        if downloader.startDownload(link: linkText, format: format) {
            linkText = ""
            linkFieldFocused = false
        }
    }

    // MARK: - Lopende en afgeronde downloads

    private var jobsList: some View {
        VStack(spacing: 0) {
            ForEach(downloader.jobs) { job in
                LinkDownloadRow(job: job) {
                    downloader.remove(job)
                }
                Rectangle()
                    .fill(Color.line)
                    .frame(height: 1)
                    .padding(.leading, 12)
            }
        }
    }
}

private struct LinkDownloadRow: View {
    @ObservedObject var job: LinkDownloadJob
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(job.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.ink4)
                        .padding(4)
                        .background(Circle().stroke(Color.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if job.isRunning {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.line)
                        Capsule().fill(Color.brandBurntPeach)
                            .frame(width: max(2, geo.size.width * job.progress))
                            .animation(.easeOut(duration: 0.25), value: job.progress)
                    }
                }
                .frame(height: 3)
            }

            Text(statusText.uppercased())
                .font(.brandMono(size: 9))
                .tracking(0.8)
                .foregroundColor(statusColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch job.statusKind {
        case .starting: return String(localized: "linkdl.status.starting")
        case .downloading: return job.statusDetail
        case .merging: return String(localized: "linkdl.status.merging")
        case .extracting: return String(localized: "linkdl.status.mp3")
        case .done: return String(localized: "linkdl.status.done")
        case .cancelled: return String(localized: "linkdl.status.cancelled")
        case .failed:
            let detail = job.statusDetail
            return detail.isEmpty ? String(localized: "linkdl.status.failed") : detail
        }
    }

    private var statusColor: Color {
        switch job.statusKind {
        case .done: return .statusOk
        case .failed: return .statusBad
        default: return .ink3
        }
    }
}
