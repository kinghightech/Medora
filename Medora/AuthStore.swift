//
//  AuthStore.swift
//  Medora
//
//  Handles secure account creation through Supabase Auth.
//

import Combine
import Foundation
import Supabase

struct MedoraProfile: Equatable {
    let fullName: String
    let email: String
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var currentProfile: MedoraProfile?

    func signUp(
        name: String,
        email: String,
        password: String,
        age: Int?,
        managing: [String],
        medicationReminders: Bool,
        carePartnerName: String?,
        carePartnerEmail: String?,
        carePartnerRelationship: String?
    ) async throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var metadata: [String: AnyJSON] = [
            "full_name": .string(cleanName),
            "managing": .array(managing.map { .string($0) }),
            "medication_reminders": .bool(medicationReminders)
        ]

        if let age {
            metadata["age"] = .integer(age)
        }

        let cleanCPName = carePartnerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanCPName.isEmpty {
            metadata["care_partner"] = .object([
                "name": .string(cleanCPName),
                "email": .string(carePartnerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
                "relationship": .string(carePartnerRelationship ?? "Family Member")
            ])
        }

        try await supabase.auth.signUp(
            email: cleanEmail,
            password: password,
            data: metadata
        )

        currentProfile = MedoraProfile(fullName: cleanName, email: cleanEmail)
    }
}
