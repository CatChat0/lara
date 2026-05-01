//
//  ProbeView.swift
//  lara
//

import SwiftUI

// Static log buffer - C callbacks can't capture context
private var probeLogLines: [String] = []
private var probeLogCallback: (() -> Void)? = nil

private let probeLogC: (@convention(c) (UnsafePointer<CChar>?) -> Void) = { msg in
    guard let msg = msg else { return }
    let line = String(cString: msg)
    probeLogLines.append(line)
    DispatchQueue.main.async { probeLogCallback?() }
}

struct ProbeView: View {
    @ObservedObject var mgr: laramgr
    @State private var running = false
    @State private var log = ""
    @State private var results: [(name: String, status: String, color: Color)] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Semi-JB Probe Suite")
                        .font(.headline)
                    Text("Runs 7 probes with full logging. Safe — no permanent changes made.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !mgr.dsready {
                Section {
                    Label("Run exploit first", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results, id: \.name) { r in
                        HStack {
                            Text(r.name).font(.subheadline)
                            Spacer()
                            Text(r.status)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(r.color)
                        }
                    }
                }
            }

            Section {
                Button {
                    runProbes()
                } label: {
                    HStack {
                        if running { ProgressView().tint(.white).padding(.trailing, 4) }
                        Text(running ? "Running probes…" : "Run All Probes")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!mgr.dsready || running)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mgr.dsready && !running ? Color.accentColor : Color.gray)
                )
                .foregroundColor(.white)
            }

            if !log.isEmpty {
                Section("Log") {
                    ScrollView {
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 400)

                    Button("Copy Log") {
                        UIPasteboard.general.string = log
                    }
                    .font(.caption)
                }

                // Debug: read known panic address
                Section {
                    Button("Read Panic Address (0xffffffe10bf6bcf8)") {
                        readPanicAddr()
                    }
                    .foregroundColor(.orange)
                    .disabled(!mgr.dsready)
                }
            }
        }
        .navigationTitle("Probe Suite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runProbes() {
        guard !running else { return }
        running = true
        log = ""
        results = []
        probeLogLines = []

        // Wire up the static callback to update our state
        probeLogCallback = {
            self.log = probeLogLines.joined(separator: "\n")
        }
        probe_set_log(probeLogC)

        DispatchQueue.global(qos: .userInitiated).async {
            let r = probe_run_all()

            DispatchQueue.main.async {
                probe_set_log(nil)
                probeLogCallback = nil
                self.log = probeLogLines.joined(separator: "\n")
                self.results = [
                    ("A: AMFI label slot",    statusStr(r.probe_a), color(r.probe_a)),
                    ("B: mac_proc_enforce",   statusStr(r.probe_b), color(r.probe_b)),
                    ("C: amfid RemoteCall",   statusStr(r.probe_c), color(r.probe_c)),
                    ("D: launchd spawn",      statusStr(r.probe_d), color(r.probe_d)),
                    ("E: /var/jb VFS write",  statusStr(r.probe_e), color(r.probe_e)),
                    ("F: preboot path",       statusStr(r.probe_f), color(r.probe_f)),
                    ("G: launchd AMFI str",   statusStr(r.probe_g), color(r.probe_g)),
                ]
                self.running = false
            }
        }
    }

    private func statusStr(_ r: probe_result_t) -> String {
        if r.skipped { return "SKIP" }
        if r.success { return "OK ✓" }
        if r.write_succeeded { return "PARTIAL" }
        return "FAIL ✗"
    }

    private func color(_ r: probe_result_t) -> Color {
        if r.skipped { return .secondary }
        if r.success { return .green }
        if r.write_succeeded { return .orange }
        return .red
    }
}
