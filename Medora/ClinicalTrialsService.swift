//
//  ClinicalTrialsService.swift
//  Medora
//
//  Turns a user-typed location into coordinates (Apple CLGeocoder, no
//  third-party API needed) and queries the public ClinicalTrials.gov v2 API
//  for nearby trials that are upcoming / recruiting.
//
//  API docs: https://clinicaltrials.gov/data-api/api
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Display model

/// A flattened, view-friendly representation of one study.
struct ClinicalTrial: Identifiable, Hashable {
    let id: String          // NCT number, e.g. "NCT01234567"
    let title: String
    let status: String      // e.g. "RECRUITING"
    let conditions: [String]
    let nearestLocation: String?

    /// Canonical public page for the study.
    var url: URL? {
        URL(string: "https://clinicaltrials.gov/study/\(id)")
    }

    /// Human-friendly status label.
    var statusLabel: String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Errors

enum ClinicalTrialsError: LocalizedError {
    case emptyLocation
    case locationNotFound
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyLocation:    return "Please enter a city, state, or ZIP code."
        case .locationNotFound: return "We couldn't find that location. Try being more specific."
        case .requestFailed:    return "Couldn't reach ClinicalTrials.gov. Check your connection and try again."
        case .decodingFailed:   return "We got an unexpected response from ClinicalTrials.gov."
        }
    }
}

// MARK: - Service

struct ClinicalTrialsService {

    /// Geocodes the typed location, then fetches nearby trials.
    /// - Parameters:
    ///   - locationText: A free-form location like "Boston, MA" or "94103".
    ///   - radiusMiles: Search radius around the location.
    func searchTrials(near locationText: String, radiusMiles: Int = 100) async throws -> [ClinicalTrial] {
        let trimmed = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClinicalTrialsError.emptyLocation }

        let coordinate = try await geocode(trimmed)
        return try await fetchTrials(latitude: coordinate.latitude,
                                     longitude: coordinate.longitude,
                                     radiusMiles: radiusMiles)
    }

    // MARK: Geocoding (Apple MapKit — free, no API key)

    private func geocode(_ text: String) async throws -> CLLocationCoordinate2D {
        guard let request = MKGeocodingRequest(addressString: text) else {
            throw ClinicalTrialsError.locationNotFound
        }
        let mapItems: [MKMapItem]
        do {
            mapItems = try await request.mapItems
        } catch {
            throw ClinicalTrialsError.locationNotFound
        }
        guard let coordinate = mapItems.first?.location.coordinate else {
            throw ClinicalTrialsError.locationNotFound
        }
        return coordinate
    }

    // MARK: ClinicalTrials.gov v2 request

    private func fetchTrials(latitude: Double,
                             longitude: Double,
                             radiusMiles: Int) async throws -> [ClinicalTrial] {
        var components = URLComponents(string: "https://clinicaltrials.gov/api/v2/studies")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            // Limit to upcoming / actively enrolling trials.
            URLQueryItem(name: "filter.overallStatus",
                         value: "RECRUITING,NOT_YET_RECRUITING,ENROLLING_BY_INVITATION"),
            // Geo filter does the "near me" work server-side.
            URLQueryItem(name: "filter.geo",
                         value: "distance(\(latitude),\(longitude),\(radiusMiles)mi)"),
            // Only ask for the fields we display, to keep responses small.
            URLQueryItem(name: "fields",
                         value: "protocolSection.identificationModule.nctId,protocolSection.identificationModule.briefTitle,protocolSection.statusModule.overallStatus,protocolSection.conditionsModule.conditions,protocolSection.contactsLocationsModule.locations"),
            URLQueryItem(name: "pageSize", value: "30"),
            URLQueryItem(name: "sort", value: "@relevance")
        ]

        guard let url = components.url else { throw ClinicalTrialsError.requestFailed }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClinicalTrialsError.requestFailed
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ClinicalTrialsError.requestFailed
        }

        do {
            let decoded = try JSONDecoder().decode(StudiesResponse.self, from: data)
            return decoded.studies.compactMap { $0.asClinicalTrial }
        } catch {
            throw ClinicalTrialsError.decodingFailed
        }
    }
}

// MARK: - Raw API response (only the pieces we decode)

private struct StudiesResponse: Decodable {
    let studies: [RawStudy]
}

private struct RawStudy: Decodable {
    let protocolSection: ProtocolSection?

    struct ProtocolSection: Decodable {
        let identificationModule: IdentificationModule?
        let statusModule: StatusModule?
        let conditionsModule: ConditionsModule?
        let contactsLocationsModule: ContactsLocationsModule?
    }

    struct IdentificationModule: Decodable {
        let nctId: String?
        let briefTitle: String?
    }

    struct StatusModule: Decodable {
        let overallStatus: String?
    }

    struct ConditionsModule: Decodable {
        let conditions: [String]?
    }

    struct ContactsLocationsModule: Decodable {
        let locations: [Location]?
    }

    struct Location: Decodable {
        let facility: String?
        let city: String?
        let state: String?
        let country: String?
    }

    /// Flattens the nested API shape into our display model.
    var asClinicalTrial: ClinicalTrial? {
        guard
            let id = protocolSection?.identificationModule?.nctId,
            let title = protocolSection?.identificationModule?.briefTitle
        else { return nil }

        let status = protocolSection?.statusModule?.overallStatus ?? "UNKNOWN"
        let conditions = protocolSection?.conditionsModule?.conditions ?? []
        let nearest = protocolSection?.contactsLocationsModule?.locations?.first.flatMap { loc in
            [loc.facility, loc.city, loc.state, loc.country]
                .compactMap { $0 }
                .joined(separator: ", ")
        }

        return ClinicalTrial(
            id: id,
            title: title,
            status: status,
            conditions: conditions,
            nearestLocation: (nearest?.isEmpty == false) ? nearest : nil
        )
    }
}
