import SwiftUI

struct VoiceJournalView: View {
    @State private var recorder = VoiceJournalRecorder()
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill").font(.system(size: 72)).foregroundStyle(recorder.isRecording ? .red : Theme.Family.sleep)
            Text(recorder.isRecording ? "Listening…" : "Speak a quick journal note").font(.title3.bold())
            Text("Audio is processed on this device and is not saved. The transcript stays here until you copy it into Journal.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Theme.inkSecondary)
            Button(recorder.isRecording ? "Stop recording" : "Start recording") { Task { await recorder.toggle() } }.buttonStyle(.borderedProminent)
            if !recorder.transcript.isEmpty { TextEditor(text: $recorder.transcript).frame(minHeight: 150).glassCard(); ShareLink(item: recorder.transcript) { Label("Share transcript", systemImage: "square.and.arrow.up") } }
            if let error = recorder.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Spacer()
        }.padding().nightBackground().navigationTitle("Voice journal").navigationBarTitleDisplayMode(.inline)
            .onDisappear { recorder.stop() }
    }
}
