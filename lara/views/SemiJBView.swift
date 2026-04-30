//
//  SemiJBView.swift
//  lara
//

import SwiftUI

// Static globals for C callback — cannot capture context
private var sjbLogLines:   [String] = []
private var sjbProgressVal: Double  = 0
private var sjbStatusStr:   String  = ""
private var sjbUpdate: (() -> Void)? = nil

// C-compatible callback — handles both log lines (p == -1) and progress updates
private let sjbCB: (@convention(c) (Double, UnsafePointer<CChar>?) -> Void) = { p, s in
    let str = s.map { String(cString: $0) } ?? ""
    if !str.isEmpty { sjbLogLines.append(str) }
    if p >= 0 {
        sjbProgressVal = p
        sjbStatusStr   = str
    }
    DispatchQueue.main.async { sjbUpdate?() }
}

struct SemiJBView: View {
    @ObservedObject var mgr: laramgr

    @State private var running   = false
    @State private var done      = false
    @State private var progress  = 0.0
    @State private var status    = ""
    @State private var logLines  = [String]()

    @State private var stAmfi   = Step.idle
    @State private var stElev   = Step.idle
    @State private var stBoot   = Step.idle
    @State private var stDaemon = Step.idle

    enum Step {
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
            // Header
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Semi-Jailbreak")
                        .font(.title2.bold())
                    Text("Installs Procursus bootstrap via launchd RemoteCall.")
                        .font(.caption).foregroundColor(.secondary)
                    if !semijb_is_bootstrapped() {
                        Text("⚠️ Bundle bootstrap.tar in app first — see README")
                            .font(.caption).foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            // Prerequisites
            if !mgr.dsready {
                Section {
                    Label("Run exploit first",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }
            if mgr.dsready && !mgr.sbxready {
                Section {
                    Label("Run sandbox escape first",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            // Steps
            Section("Steps") {
                stepRow("1. AMFI bypass",      "Write AMFI label = 0",               stAmfi)
                stepRow("2. Root elevation",   "Swap ucred with launchd",            stElev)
                stepRow("3. Bootstrap",        "Extract Procursus to preboot",       stBoot)
                stepRow("4. Daemon",           "Register launchd respring helper",   stDaemon)
            }

            // Progress bar
            if running || done {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress)
                            .tint(done ? .green : .accentColor)
                        Text(status)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            // Action
            Section {
                if done {
                    Label("Done! Respring to finish.",
                          systemImage: "party.popper.fill")
                        .foregroundColor(.green)
                    Button("Respring") { mgr.respring() }
                        .foregroundColor(.red)
                } else {
                    Button { runAll() } label: {
                        HStack {
                            if running {
                                ProgressView().tint(.white).padding(.trailing, 4)
                            }
                            Text(running ? "Working…" : "Install Semi-Jailbreak")
                                .bold()
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

            // Log
            if !logLines.isEmpty {
                Section("Log") {
                    ScrollView {
                        Text(logLines.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 400)

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
    private func stepRow(_ title: String, _ sub: String, _ state: Step) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.icon)
                .foregroundColor(state.color)
                .frame(width: 22)
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
        running = true
        done    = false
        progress = 0
        logLines = []
        sjbLogLines = []
        stAmfi = .running; stElev = .idle; stBoot = .idle; stDaemon = .idle

        // Wire update callback to refresh our @State
        sjbUpdate = {
            self.progress = sjbProgressVal
            self.status   = sjbStatusStr
            self.logLines = sjbLogLines
        }

        // Set global C callback BEFORE calling anything
        semijb_set_log_callback(sjbCB)

        DispatchQueue.global(qos: .userInitiated).async {

            // Step 1: AMFI bypass
            let amfi = semijb_amfi_bypass()
            DispatchQueue.main.async {
                self.stAmfi = amfi ? .ok : .failed
                self.stElev = .running
            }

            // Step 2: Root elevation
            let elev = semijb_elevate()
            DispatchQueue.main.async {
                self.stElev = elev ? .ok : .failed
                self.stBoot = .running
            }

            // Step 3: Bootstrap
            let boot = semijb_bootstrap(sjbCB)
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
                self.status   = boot
                    ? "Done! Respring to finish."
                    : "Incomplete — check log"
                self.logLines = sjbLogLines

                // Clear callback
                semijb_set_log_callback(nil)
                sjbUpdate = nil
            }
        }
    }
}
