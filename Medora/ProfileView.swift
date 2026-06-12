//
//  ProfileView.swift
//  Medora
//
//  Profile tab. Lets the user pick the app language; the whole app
//  (everything after onboarding) re-renders in the chosen language.
//

import SwiftUI

struct ProfileView: View {
    let userName: String
    @ObservedObject private var loc = LocalizationManager.shared

    private var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Medora" : trimmed
    }

    var body: some View {
        ZStack {
            MedoraBackground()

            ScrollView {
                VStack(spacing: 16) {
                    profileHeader
                    languageCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(loc.t("Profile"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Text(initials)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Color.medoraBlue, in: Circle())

            Text(displayName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    // MARK: Language

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("App Language"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(loc.t("Choose your language"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(AppLanguage.allCases) { language in
                    languageRow(language)
                }
            }

            Text(loc.t("The whole app updates instantly."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let isSelected = loc.language == language
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                loc.setLanguage(language)
            }
        } label: {
            HStack(spacing: 12) {
                Text(language.flag)
                    .font(.system(size: 24))

                Text(language.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.medoraBlue)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.medoraBlue.opacity(0.10) : Color.medoraField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.medoraBlue.opacity(0.4) : Color.medoraHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    NavigationStack {
        ProfileView(userName: "Aahish Abbani")
    }
}
#endif
