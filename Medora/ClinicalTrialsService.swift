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

// MARK: - Geocoding Suggestion Model

struct GeocodeSuggestion: Identifiable, Hashable {
    let id: UUID
    let formattedAddress: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), formattedAddress: String, latitude: Double, longitude: Double) {
        self.id = id
        self.formattedAddress = formattedAddress
        self.latitude = latitude
        self.longitude = longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(formattedAddress)
        hasher.combine(latitude)
        hasher.combine(longitude)
    }

    static func == (lhs: GeocodeSuggestion, rhs: GeocodeSuggestion) -> Bool {
        lhs.formattedAddress == rhs.formattedAddress &&
        lhs.latitude == rhs.latitude &&
        lhs.longitude == rhs.longitude
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

    func getPlacesAutocompleteSuggestions(for text: String) async -> [GeocodeSuggestion] {
        let apiKey = Config.mapboxAPIKey
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        
        let urlString = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(escaped).json?access_token=\(apiKey)&autocomplete=true&limit=5"
        guard let url = URL(string: urlString) else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        
        struct MapboxGeocodeResponse: Decodable {
            let features: [Feature]
            
            struct Feature: Decodable {
                let place_name: String
                let center: [Double]
            }
        }
        
        guard let decoded = try? JSONDecoder().decode(MapboxGeocodeResponse.self, from: data) else {
            return []
        }
        
        return decoded.features.compactMap { feature in
            guard feature.center.count >= 2 else { return nil }
            return GeocodeSuggestion(
                formattedAddress: feature.place_name,
                latitude: feature.center[1],
                longitude: feature.center[0]
            )
        }
    }

    /// Geocodes the typed location, then fetches nearby trials.
    /// - Parameters:
    ///   - locationText: A free-form location like "Boston, MA" or "94103".
    ///   - radiusMiles: Search radius around the location.
    ///   - condition: Optional medical condition to filter.
    func searchTrials(near locationText: String, radiusMiles: Int = 100, condition: String? = nil) async throws -> [ClinicalTrial] {
        let trimmed = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClinicalTrialsError.emptyLocation }

        let coordinate = try await geocode(trimmed)
        return try await fetchTrials(latitude: coordinate.latitude,
                                     longitude: coordinate.longitude,
                                     radiusMiles: radiusMiles,
                                     condition: condition)
    }

    /// Fetches trials using coordinates directly (e.g. from device GPS).
    /// - Parameters:
    ///   - latitude: Coordinate latitude.
    ///   - longitude: Coordinate longitude.
    ///   - radiusMiles: Search radius around the location.
    ///   - condition: Optional medical condition to filter.
    func searchTrials(latitude: Double, longitude: Double, radiusMiles: Int = 100, condition: String? = nil) async throws -> [ClinicalTrial] {
        return try await fetchTrials(latitude: latitude,
                                     longitude: longitude,
                                     radiusMiles: radiusMiles,
                                     condition: condition)
    }

    // MARK: Geocoding (Mapbox Geocoding API)

    func geocode(_ text: String) async throws -> CLLocationCoordinate2D {
        let apiKey = Config.mapboxAPIKey
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ClinicalTrialsError.locationNotFound
        }
        
        let urlString = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(escaped).json?access_token=\(apiKey)&limit=1"
        guard let url = URL(string: urlString) else {
            throw ClinicalTrialsError.locationNotFound
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClinicalTrialsError.locationNotFound
        }
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClinicalTrialsError.locationNotFound
        }
        
        struct MapboxGeocodeResponse: Decodable {
            let features: [Feature]
            
            struct Feature: Decodable {
                let place_name: String
                let center: [Double]
            }
        }
        
        do {
            let decoded = try JSONDecoder().decode(MapboxGeocodeResponse.self, from: data)
            guard let firstResult = decoded.features.first, firstResult.center.count >= 2 else {
                throw ClinicalTrialsError.locationNotFound
            }
            
            return CLLocationCoordinate2D(latitude: firstResult.center[1],
                                           longitude: firstResult.center[0])
        } catch {
            throw ClinicalTrialsError.locationNotFound
        }
    }

    // MARK: ClinicalTrials.gov v2 request

    private func fetchTrials(latitude: Double,
                             longitude: Double,
                             radiusMiles: Int,
                             condition: String? = nil) async throws -> [ClinicalTrial] {
        var components = URLComponents(string: "https://clinicaltrials.gov/api/v2/studies")!
        var queryItems = [
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

        if let condition = condition?.trimmingCharacters(in: .whitespacesAndNewlines), !condition.isEmpty {
            queryItems.append(URLQueryItem(name: "query.cond", value: condition))
        }

        components.queryItems = queryItems

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
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return decoded.studies.compactMap { $0.toClinicalTrial(near: center) }
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
        let geoPoint: GeoPoint?
    }

    struct GeoPoint: Decodable {
        let lat: Double?
        let lon: Double?
    }

    /// Flattens the nested API shape into our display model.
    func toClinicalTrial(near center: CLLocationCoordinate2D?) -> ClinicalTrial? {
        guard
            let id = protocolSection?.identificationModule?.nctId,
            let title = protocolSection?.identificationModule?.briefTitle
        else { return nil }

        let status = protocolSection?.statusModule?.overallStatus ?? "UNKNOWN"
        let conditions = protocolSection?.conditionsModule?.conditions ?? []
        
        var nearest: String? = nil
        var minDistance: Double = Double.infinity
        
        if let center = center, let locations = protocolSection?.contactsLocationsModule?.locations {
            for loc in locations {
                if let lat = loc.geoPoint?.lat, let lon = loc.geoPoint?.lon {
                    let loc1 = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    let loc2 = CLLocation(latitude: lat, longitude: lon)
                    let dist = loc1.distance(from: loc2) / 1609.344 // meters to miles
                    
                    if dist < minDistance {
                        minDistance = dist
                        nearest = [loc.facility, loc.city, loc.state, loc.country]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                        
                        if dist < 1000 {
                            let formattedDist = String(format: "%.1f", dist)
                            nearest = (nearest ?? "") + " (\(formattedDist) miles away)"
                        }
                    }
                }
            }
        }
        
        // Fallback to first location if no distance matching succeeded
        if nearest == nil {
            nearest = protocolSection?.contactsLocationsModule?.locations?.first.flatMap { loc in
                [loc.facility, loc.city, loc.state, loc.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
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
