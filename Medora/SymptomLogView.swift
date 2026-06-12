//
//  SymptomLogView.swift
//  Medora
//
//  Created by Antigravity on 6/12/26.
//

import SwiftUI

struct SymptomLogView: View {
    @StateObject private var symptomStore = SymptomStore()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var inputText = ""
    @State private var isListening = false
    @State private var showingPermissionAlert = false
    @ObservedObject private var loc = LocalizationManager.shared
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            MedoraBackground()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        inputSection
                        historySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(loc.t("Symptom Journal"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(loc.t("Done")) {
                    dismiss()
                }
            }
        }
        .task {
            await symptomStore.fetchSymptoms()
        }
        .onDisappear {
            speechRecognizer.stopTranscribing()
        }
        .onChange(of: speechRecognizer.transcript) { newTranscript in
            if !newTranscript.isEmpty {
                inputText = newTranscript
            }
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text(loc.t("Permissions Required")),
                message: Text(loc.t("Please enable Speech Recognition and Microphone access in iOS Settings to dictate your symptoms.")),
                dismissButton: .default(Text(loc.t("OK")))
            )
        }
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Describe your symptoms"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            HStack(alignment: .bottom, spacing: 10) {
                // Input TextField
                TextField(loc.t("Type or dictate e.g., Headache, nausea..."), text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.medoraHairline, lineWidth: 1)
                    )
                
                // Dictation Mic Button
                Button(action: toggleListening) {
                    ZStack {
                        Circle()
                            .fill(speechRecognizer.isRecording ? Color.red.opacity(0.15) : Color.medoraBlue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        
                        if speechRecognizer.isRecording {
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 44, height: 44)
                                .scaleEffect(isListening ? 1.25 : 1.0)
                                .opacity(isListening ? 0.0 : 1.0)
                                .animation(
                                    .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: isListening
                                )
                        }
                        
                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(speechRecognizer.isRecording ? .red : Color.medoraBlue)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speechRecognizer.isRecording ? "Stop listening" : "Start dictating")
            }
            
            if speechRecognizer.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(isListening ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isListening)
                    
                    Text(loc.t("Listening... Speak clearly"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.leading, 2)
                .onAppear {
                    isListening = true
                }
                .onDisappear {
                    isListening = false
                }
            }
            
            if let error = speechRecognizer.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 2)
            }
            
            if let storeError = symptomStore.errorMessage {
                Text(storeError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 2)
            }
            
            // Save Button
            Button(action: saveSymptom) {
                HStack {
                    if symptomStore.isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 6)
                    }
                    Text(loc.t("Log Symptom"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || symptomStore.isLoading)
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Recent Logs"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            if symptomStore.symptoms.isEmpty {
                emptyLogsView
            } else {
                VStack(spacing: 10) {
                    ForEach(symptomStore.symptoms) { log in
                        symptomRow(log)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
    
    private func symptomRow(_ log: SymptomRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.medoraBlue)
                .frame(width: 38, height: 38)
                .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(log.symptomText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(formatDate(log.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            Button {
                Task {
                    await symptomStore.deleteSymptom(id: log.id ?? UUID())
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundStyle(.red.opacity(0.78))
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private var emptyLogsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Color.medoraBlue.opacity(0.4))
            Text(loc.t("No symptoms logged yet."))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Actions & Helpers
    
    private func toggleListening() {
        HapticManager.shared.triggerSelection()
        
        if speechRecognizer.isRecording {
            speechRecognizer.stopTranscribing()
        } else {
            Task {
                let isAuthorized = await speechRecognizer.requestPermissions()
                if isAuthorized {
                    speechRecognizer.resetTranscript()
                    speechRecognizer.startTranscribing()
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func saveSymptom() {
        let cleanText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        HapticManager.shared.triggerImpact(style: .medium)
        
        Task {
            let success = await symptomStore.addSymptom(text: cleanText)
            if success {
                inputText = ""
                speechRecognizer.resetTranscript()
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
