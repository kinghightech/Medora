//
//  SymptomStore.swift
//  Medora
//
//  Created by Antigravity on 6/12/26.
//

import Foundation
import Supabase
import Combine

struct SymptomRecord: Codable, Identifiable, Equatable {
    let id: UUID?
    let userId: UUID
    let symptomText: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case symptomText = "symptom_text"
        case createdAt = "created_at"
    }
}

@MainActor
final class SymptomStore: ObservableObject {
    @Published var symptoms: [SymptomRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    /// Fetch all symptoms logged by the authenticated user.
    func fetchSymptoms() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let session = try? await supabase.auth.session else {
                isLoading = false
                return
            }
            
            let userId = session.user.id
            
            let records: [SymptomRecord] = try await supabase
                .from("symptoms")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            self.symptoms = records
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }

    /// Add a new symptom log for the currently signed-in user.
    func addSymptom(text: String) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        errorMessage = nil
        isLoading = true
        
        do {
            guard let session = try? await supabase.auth.session else {
                errorMessage = "No active session. Please sign in again."
                isLoading = false
                return false
            }
            
            let userId = session.user.id
            let record = SymptomRecord(
                id: nil,
                userId: userId,
                symptomText: text,
                createdAt: nil
            )
            
            try await supabase
                .from("symptoms")
                .insert(record)
                .execute()
            
            isLoading = false
            await fetchSymptoms()
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    /// Delete a symptom log from the database.
    func deleteSymptom(id: UUID) async {
        errorMessage = nil
        isLoading = true
        
        do {
            try await supabase
                .from("symptoms")
                .delete()
                .eq("id", value: id)
                .execute()
            
            isLoading = false
            await fetchSymptoms()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
