//
//  SemiJBView.swift
//  lara
//

import SwiftUI

// Static C callback for progress — can't capture context in C function ptr
private var sjbLogLines: [String] = []
private var sjbProgressVal: Double = 0
private var sjbStatusStr: String = ""
private var sjbUpdateCallback: (() -> Void)? = nil

private let sjbProgressC: (@convention(c) (Double, UnsafePointer<CChar>?) -> Void) = { p, s in
    let str = s.map { String(cString: $0) } ?? ""
    if !str.isEmpty { sjbLogLines.append(str) }
    if p >= 0 {  // -1.0 = log-only, don't update progress bar
        sjbProgressVal = p
        sjbStatusStr   = str
    }
    DispatchQueue.main.async { sjbUpdateCallback?() }
}

struct SemiJBView: View {
    @ObservedObject var mgr: laramgr

    @State private var running   = false
    @State private var done      = false
    @State private var progress  = 0.0
    @State private var status    = ""
    @State private var logLines  = [String]()

    @State private var stAmfi   = StepState.idle
    @State private var stElev   = StepState.idle
    @State private var stBoot   = StepState.idle
    @State private var stDaemon = StepState.idle

    enum StepState {
        case idle, running, ok, failed
        var color: Color {
            switch self {
            case .idle:    return .secondary
            case .running: return .orange
            case .ok:      return .green
            case .failed:  return .red
            }
        }
        var icon: String {
            switch self {
            case .idle:    return "circle"
            case .running: return "arrow.trianglehead.2.clockwise"
            case .ok:      return "checkmark.circle.fill"
            case .failed:  return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Semi-Jailbreak")
                        .font(.title2.bold())
                    Text("Installs Procursus bootstrap via launchd RemoteCall.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !mgr.dsready {
                Section {
                    Label("Run exploit first", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }
            if mgr.dsready && !mgr.sbxready {
                Section {
                    Label("Run sandbox escape first", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            Section("Steps") {
                stepRow("1. AMFI bypass",     "Write AMFI label slot = 0",              stAmfi)
                stepRow("2. Root elevation",  "Swap ucred with launchd",                stElev)
                stepRow("3. Bootstrap",       "Extract Procursus to /private/preboot",  stBoot)
                stepRow("4. Daemon",          "Register launchd helper",                stDaemon)
            }

            if running || done {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress).tint(done ? .green : .accentColor)
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Section {
                if done {
                    Label("Done! Respring to finish.", systemImage: "party.popper.fill")
                        .foregroundColor(.green)
                    Button("Respring") { mgr.respring() }
                        .foregroundColor(.red)
                } else {
                    Button { runAll() } label: {
                        HStack {
                            if running { ProgressView().tint(.white).padding(.trailing, 4) }
                            Text(running ? "Working…" : "Install Semi-Jailbreak").bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!mgr.dsready || !mgr.sbxready || running)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(mgr.dsready && mgr.sbxready && !running
                                  ? Color.accentColor : Color.gray)
                    )
                    .foregroundColor(.white)
                }
            }

            if !logLines.isEmpty {
                Section("Log") {
                    ScrollView {
                        Text(logLines.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                    Button("Copy Log") {
                        UIPasteboard.general.string = logLines.joined(separator: "\n")
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Semi-Jailbreak")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func stepRow(_ title: String, _ sub: String, _ state: StepState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.icon).foregroundColor(state.color).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func runAll() {
        guard !running else { return }
        running = true; done = false; progress = 0
        logLines = []; sjbLogLines = []
        stAmfi = .running; stElev = .idle; stBoot = .idle; stDaemon = .idle

        sjbUpdateCallback = {
            self.progress = sjbProgressVal
            self.status   = sjbStatusStr
            self.logLines = sjbLogLines
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Step 1: AMFI
            let amfi = semijb_amfi_bypass()
            DispatchQueue.main.async {
                self.stAmfi = amfi ? .ok : .failed
                self.stElev = .running
            }

            // Step 2: Elevate
            let elev = semijb_elevate()
            DispatchQueue.main.async {
                self.stElev = elev ? .ok : .failed
                self.stBoot = .running
            }

            // Step 3: Bootstrap
            let boot = semijb_bootstrap(sjbProgressC)
            DispatchQueue.main.async {
                self.stBoot   = boot ? .ok : .failed
                self.stDaemon = .running
            }

            // Step 4: Daemon
            let daemon = semijb_daemon()
            DispatchQueue.main.async {
                self.stDaemon = daemon ? .ok : .failed
                self.running  = false
                self.done     = boot
                self.progress = 1.0
                self.status   = boot ? "Done! Respring to finish." : "Incomplete — check log"
                self.logLines = sjbLogLines
                sjbUpdateCallback = nil
            }
        }
    }
}
