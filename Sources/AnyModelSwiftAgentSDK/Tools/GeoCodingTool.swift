import Foundation
import CoreLocation
import AnyLanguageModel

/// Resolves a city name or street address to coordinates using CoreLocation.
///
/// Returns every match Apple's geocoder finds, with its place name, region and
/// country, so the model can pick the right one or ask the user when a name is
/// ambiguous. Forward geocoding needs a network connection but no location permission.
public struct GeoCodingTool: Tool {

    public let name = "geocode"

    public let description = """
        Look up the latitude and longitude of a city, place or street address. \
        Use this before calling tools that need coordinates. \
        If several places match, pick the one that fits the user's request or ask the user.
        """

    @Generable
    public struct Arguments {
        @Guide(description: "City name or address, e.g. \"Berlin\", \"Neustadt, Rheinland-Pfalz\" or \"1 Infinite Loop, Cupertino\".")
        public var address: String
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> String {
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().geocodeAddressString(arguments.address)
        } catch let error as CLError where error.code == .geocodeFoundNoResult {
            return "No location found for \"\(arguments.address)\"."
        }

        let matches = placemarks.compactMap { placemark -> String? in
            guard let coordinate = placemark.location?.coordinate else { return nil }
            let place = [
                placemark.name,
                placemark.locality,
                placemark.administrativeArea,
                placemark.country,
            ]
            .compactMap(\.self)
            .reduce(into: [String]()) { parts, part in
                // CoreLocation often repeats the locality as the name; list each part once.
                if !parts.contains(part) { parts.append(part) }
            }
            .joined(separator: ", ")
            return "\(place): latitude \(coordinate.latitude.rounded(toPlaces: 4)), longitude \(coordinate.longitude.rounded(toPlaces: 4))"
        }

        guard !matches.isEmpty else {
            return "No location found for \"\(arguments.address)\"."
        }
        return matches.joined(separator: "\n")
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
