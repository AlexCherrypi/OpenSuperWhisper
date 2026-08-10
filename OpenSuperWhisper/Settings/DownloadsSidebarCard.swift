import SwiftUI

/// A download indicator that lives in the sidebar rather than in the list being downloaded from.
///
/// Progress used to be shown twice: once inside the model's own row and again in a block under
/// the list. Both carried a bar, a name and a Cancel button, so a single download looked like
/// two. Worse, either could scroll out of sight, and a model takes long enough that people
/// wander off to another settings page while it runs.
///
/// The card sits with the navigation, so it stays put wherever the user goes. It says only that
/// something is downloading; the detail is one click away.
struct DownloadsSidebarCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var showingDetail = false

    var body: some View {
        if viewModel.isDownloading {
            Button { showingDetail.toggle() } label: {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)

                    Text("Downloading")
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundColor(STheme.text)

                    Spacer(minLength: 0)

                    if let percent = percentText {
                        Text(percent)
                            .scaledFont(size: 10, design: .monospaced)
                            .foregroundColor(STheme.hint)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(STheme.accentSoft))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(STheme.accent.opacity(0.35),
                                                                  lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Show what's downloading")
            .popover(isPresented: $showingDetail, arrowEdge: .trailing) {
                detail
            }
        }
    }

    /// No percentage until the first bytes land: an empty "0%" reads as stalled.
    private var percentText: String? {
        guard viewModel.downloadProgress > 0 else { return nil }
        return "\(Int(viewModel.downloadProgress * 100))%"
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Downloads")
                .scaledFont(size: 9, weight: .bold)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(STheme.sectionTitle)

            // A list, though the downloader takes one model at a time: it refuses a second while
            // one is running. Shaped this way so a queue would need no new screen.
            ForEach(active, id: \.name) { download in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(download.name)
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundColor(STheme.textBright)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Button("Cancel") { viewModel.cancelDownload() }
                            .controlSize(.small)
                    }

                    if download.progress > 0 {
                        ProgressView(value: download.progress)
                            .progressViewStyle(.linear)
                            .tint(STheme.accent)
                    } else {
                        // Indeterminate until the first bytes: the request is out, nothing has
                        // come back yet.
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(STheme.accent)
                    }
                }
            }

            if active.isEmpty {
                Text("Nothing downloading")
                    .scaledFont(size: 11)
                    .foregroundColor(STheme.hint)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var active: [(name: String, progress: Double)] {
        guard viewModel.isDownloading else { return [] }
        return [(viewModel.downloadingModelName ?? "Model", viewModel.downloadProgress)]
    }
}
