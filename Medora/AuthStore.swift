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
    let managing: [String]
    let age: Int?
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

        currentProfile = MedoraProfile(fullName: cleanName, email: cleanEmail, managing: managing, age: age)
    }

    /// Restores a previously signed-in user from the Supabase session stored
    /// on this device, so returning users skip onboarding. Returns nil when
    /// nobody is signed in (or the session can't be refreshed).
    func restoreSession() async -> MedoraProfile? {
        guard let session = try? await supabase.auth.session else {
            return nil
        }

        let user = session.user
        var name = ""
        if case let .string(value)? = user.userMetadata["full_name"] {
            name = value
        }

        var managing: [String] = []
        if case let .array(values)? = user.userMetadata["managing"] {
            managing = values.compactMap {
                if case let .string(val) = $0 { return val }
                return nil
            }
        }

        var age: Int?
        switch user.userMetadata["age"] {
        case .integer(let value)?:
            age = value
        case .double(let value)?:
            age = Int(value)
        default:
            break
        }

        let profile = MedoraProfile(fullName: name, email: user.email ?? "", managing: managing, age: age)
        currentProfile = profile
        return profile
    }

    /// Signs out of Supabase and clears the in-memory profile.
    func signOut() async {
        try? await supabase.auth.signOut()
        currentProfile = nil
    }
}
