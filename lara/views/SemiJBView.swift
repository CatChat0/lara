//
//  SemiJBView.swift
//  lara
//

import SwiftUI

private var sjbLogLines:    [String] = []
private var sjbProgressVal: Double   = 0
private var sjbStatusStr:   String   = ""
private var sjbUpdate: (() -> Void)? = nil

private let sjbCB: (@convention(c) (Double, UnsafePointer<CChar>?) -> Void) = { p, s in
    let str = s.map { String(cString: $0) } ?? ""
    if !str.isEmpty { sjbLogLines.append(str) }
    if p >= 0 { sjbProgressVal = p; sjbStatusStr = str }
    DispatchQueue.main.async { sjbUpdate?() }
}

struct SemiJBView: View {
    @ObservedObject var mgr: laramgr

    @State private var running      = false
    @State private var amfidPatched = false
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

            Section("Steps") {
                stepRow("1. AMFI bypass",     "Write AMFI label = 0",             stAmfi)
                stepRow("2. Root elevation",  "Swap ucred with launchd",          stElev)
                stepRow("3. Bootstrap",       "Extract Procursus to preboot",     stBoot)
                stepRow("4. Daemon",          "Register launchd respring helper", stDaemon)
            }

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

            // Reset button — removes marker so reinstall runs fresh
            Section {
                Button("Reset Bootstrap") {
                    resetBootstrap()
                }
                .foregroundColor(.orange)
                .disabled(running)

                Button(amfidPatched ? "AMFID Patched ✓" : "Patch AMFID") {
                    patchAMFID()
                }
                .foregroundColor(amfidPatched ? .green : .purple)
                .disabled(running || !mgr.dsready)

                Button("Clean /var/jb symlink") {
                    semijb_set_log_callback(sjbCB)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let ok = semijb_clean_varjb()
                        DispatchQueue.main.async {
                            self.logLines.append(ok ? "✓ /var/jb cleaned" : "✗ clean failed")
                            semijb_set_log_callback(nil)
                        }
                    }
                }
                .foregroundColor(.red)
                .disabled(running)
            }

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

    private func patchAMFID() {
        semijb_set_log_callback(sjbCB)
        running = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = amfid_patch()
            DispatchQueue.main.async {
                self.amfidPatched = ok
                self.logLines.append(ok ? "✓ AMFID patched — unsigned binaries enabled!" : "✗ AMFID patch failed — check log")
                semijb_set_log_callback(nil)
                self.running = false
            }
        }
    }

    private func resetBootstrap() {
        sjbLogLines = []
        sjbUpdate = { self.logLines = sjbLogLines }
        semijb_set_log_callback(sjbCB)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = semijb_reset()
            DispatchQueue.main.async {
                self.logLines = sjbLogLines
                self.logLines.append(ok
                    ? "✓ Reset done — tap Install to reinstall"
                    : "✗ Reset failed")
                self.done = false
                semijb_set_log_callback(nil)
                sjbUpdate = nil
            }
        }
    }

    private func runAll() {
        guard !running else { return }
        running = true
        done    = false
        progress = 0
        logLines = []
        sjbLogLines = []
        stAmfi = .running; stElev = .idle; stBoot = .idle; stDaemon = .idle

        sjbUpdate = {
            self.progress = sjbProgressVal
            self.status   = sjbStatusStr
            self.logLines = sjbLogLines
        }
        semijb_set_log_callback(sjbCB)

        DispatchQueue.global(qos: .userInitiated).async {
            let amfi = semijb_amfi_bypass()
            DispatchQueue.main.async {
                self.stAmfi = amfi ? .ok : .failed
                self.stElev = .running
            }

            let elev = semijb_elevate()
            DispatchQueue.main.async {
                self.stElev = elev ? .ok : .failed
                self.stBoot = .running
            }

            let boot = semijb_bootstrap(sjbCB)
            DispatchQueue.main.async {
                self.stBoot   = boot ? .ok : .failed
                self.stDaemon = .running
            }

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
                semijb_set_log_callback(nil)
                sjbUpdate = nil
            }
        }
    }
}
