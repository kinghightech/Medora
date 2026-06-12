//
//  SpeechRecognizer.swift
//  Medora
//
//  Helper class to transcribe microphone input into text using Apple's Speech framework.
//

import Speech
import AVFoundation
import Combine

@MainActor
public class SpeechRecognizer: ObservableObject {
    enum RecognizerError: Error {
        case nilRecognizer
        case notAuthorizedToRecognize
        case notAuthorizedToRecord
        case recognizerUnavailable
        case executionFailed
        
        var localizedDescription: String {
            switch self {
            case .nilRecognizer: return "Speech recognizer is not available for this locale."
            case .notAuthorizedToRecognize: return "Speech recognition is not authorized."
            case .notAuthorizedToRecord: return "Microphone access is not authorized."
            case .recognizerUnavailable: return "Speech recognizer is currently unavailable."
            case .executionFailed: return "Failed to start speech recognition."
            }
        }
    }
    
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String? = nil
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    
    public init() {
        self.recognizer = SFSpeechRecognizer()
    }
    
    /// Request speech recognition and microphone permissions
    public func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        let micAuthorized = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        return speechAuthorized && micAuthorized
    }
    
    /// Start recording and transcribing
    public func startTranscribing() {
        errorMessage = nil
        
        guard let recognizer = recognizer else {
            errorMessage = RecognizerError.nilRecognizer.localizedDescription
            return
        }
        
        guard recognizer.isAvailable else {
            errorMessage = RecognizerError.recognizerUnavailable.localizedDescription
            return
        }
        
        do {
            let (audioEngine, request) = try prepareEngine()
            self.audioEngine = audioEngine
            self.request = request
            
            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let result = result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    
                    if error != nil {
                        self.stopTranscribing()
                    }
                }
            }
            
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            stopTranscribing()
        }
    }
    
    /// Stop recording and transcribing
    public func stopTranscribing() {
        task?.finish()
        task = nil
        request = nil
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        isRecording = false
    }
    
    /// Reset the transcript
    public func resetTranscript() {
        transcript = ""
    }
    
    private func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return (audioEngine, request)
    }
}
