import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count > 2 else {
    fatalError("Usage: generate_app_icon.swift <output.png> <WorldData.swift>")
}

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create icon drawing context")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func addPolygon(_ points: [CGPoint], to path: CGMutablePath) {
    guard let first = points.first else { return }
    path.move(to: first)
    path.addLines(between: Array(points.dropFirst()))
    path.closeSubpath()
}

func fill(_ path: CGPath, with fillColor: CGColor) {
    context.addPath(path)
    context.setFillColor(fillColor)
    context.fillPath()
}

func stroke(_ path: CGPath, with strokeColor: CGColor, width: CGFloat) {
    context.addPath(path)
    context.setStrokeColor(strokeColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

struct Country: Decodable {
    let p: [[[Double]]]
}

struct Coordinate {
    let lon: Double
    let lat: Double
}

let mapRadius: CGFloat = 335
let centralLongitude = -20.0

func project(lon: Double, lat: Double) -> CGPoint {
    let longitude = (lon - centralLongitude) * .pi / 180
    let latitude = lat * .pi / 180
    let x = cos(latitude) * sin(longitude)
    let y = sin(latitude)
    return CGPoint(x: 512 + mapRadius * x, y: 512 + mapRadius * y)
}

func clip(_ coordinates: [Coordinate], at longitude: Double, keepGreater: Bool) -> [Coordinate] {
    guard let last = coordinates.last else { return [] }
    var result: [Coordinate] = []
    var previous = last
    var previousInside = keepGreater ? previous.lon >= longitude : previous.lon <= longitude

    for current in coordinates {
        let currentInside = keepGreater ? current.lon >= longitude : current.lon <= longitude
        if currentInside != previousInside {
            let fraction = (longitude - previous.lon) / (current.lon - previous.lon)
            result.append(Coordinate(
                lon: longitude,
                lat: previous.lat + fraction * (current.lat - previous.lat)
            ))
        }
        if currentInside { result.append(current) }
        previous = current
        previousInside = currentInside
    }
    return result
}

func visiblePieces(of ring: [Double]) -> [[Coordinate]] {
    guard ring.count >= 6 else { return [] }
    var unwrapped: [Coordinate] = []
    var previousLongitude: Double?
    for index in stride(from: 0, to: ring.count, by: 2) {
        var longitude = ring[index]
        if let previousLongitude {
            while longitude - previousLongitude > 180 { longitude -= 360 }
            while longitude - previousLongitude < -180 { longitude += 360 }
        }
        unwrapped.append(Coordinate(lon: longitude, lat: ring[index + 1]))
        previousLongitude = longitude
    }

    // Unwrap and shift rings across the date line, then keep only the visible hemisphere.
    return [-360.0, 0.0, 360.0].compactMap { offset in
        let shifted = unwrapped.map { Coordinate(lon: $0.lon + offset, lat: $0.lat) }
        let clipped = clip(
            clip(shifted, at: centralLongitude - 90, keepGreater: true),
            at: centralLongitude + 90,
            keepGreater: false
        )
        return clipped.count >= 3 ? clipped : nil
    }
}

let backgroundColors = [
    color(0.035, 0.095, 0.19),
    color(0.035, 0.27, 0.36),
] as CFArray
let background = CGGradient(colorsSpace: colorSpace, colors: backgroundColors, locations: [0, 1])!
context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: size, y: size),
    options: []
)

let globeRect = CGRect(x: 164, y: 164, width: 696, height: 696)
let globe = CGPath(ellipseIn: globeRect, transform: nil)
context.saveGState()
context.addPath(globe)
context.clip()

let oceanColors = [
    color(0.055, 0.31, 0.46),
    color(0.08, 0.57, 0.63),
] as CFArray
let ocean = CGGradient(colorsSpace: colorSpace, colors: oceanColors, locations: [0, 1])!
context.drawLinearGradient(
    ocean,
    start: CGPoint(x: 250, y: 790),
    end: CGPoint(x: 780, y: 250),
    options: []
)

let gridColor = color(0.73, 0.94, 0.94, 0.29)
for longitude in stride(from: -60.0, through: 60.0, by: 30.0) {
    let meridian = CGMutablePath()
    for latitude in stride(from: -90.0, through: 90.0, by: 2.0) {
        let point = project(lon: centralLongitude + longitude, lat: latitude)
        if latitude == -90 { meridian.move(to: point) } else { meridian.addLine(to: point) }
    }
    stroke(meridian, with: gridColor, width: 5)
}
for latitude in [-60.0, -30.0, 0.0, 30.0, 60.0] {
    let parallel = CGMutablePath()
    for longitude in stride(from: centralLongitude - 90, through: centralLongitude + 90, by: 2.0) {
        let point = project(lon: longitude, lat: latitude)
        if longitude == -90 { parallel.move(to: point) } else { parallel.addLine(to: point) }
    }
    stroke(parallel, with: gridColor, width: 5)
}

let source = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
let jsonStart = "static let json = #\"\"\"\n"
let jsonEnd = "\n\"\"\"#"
guard let start = source.range(of: jsonStart)?.upperBound,
      let end = source.range(of: jsonEnd, range: start..<source.endIndex)?.lowerBound else {
    fatalError("Could not find embedded world polygons")
}
let countries = try JSONDecoder().decode([Country].self, from: Data(source[start..<end].utf8))
let landColor = color(0.62, 0.91, 0.77)
let land = CGMutablePath()
for country in countries {
    for polygon in country.p {
        guard let exterior = polygon.first else { continue }
        for piece in visiblePieces(of: exterior) {
            addPolygon(piece.map { project(lon: $0.lon, lat: $0.lat) }, to: land)
        }
    }
}

// The embedded atlas represents Antarctica as a pole-only ring, so add its visible polar cap.
let antarctica = CGMutablePath()
let antarcticCoast: [(Double, Double)] = [
    (-110, -70), (-95, -71), (-80, -70), (-65, -67), (-60, -63),
    (-50, -68), (-35, -71), (-20, -73), (-5, -74), (10, -75),
    (30, -73), (50, -71), (70, -70),
]
addPolygon(
    antarcticCoast.map { project(lon: $0.0, lat: $0.1) } + [project(lon: 0, lat: -90)],
    to: antarctica
)
land.addPath(antarctica)
fill(land, with: landColor)

let routeColor = color(0.93, 0.99, 0.91, 0.9)
let routes = CGMutablePath()
let northAmerica = project(lon: -75, lat: 40)
let europe = project(lon: 10, lat: 50)
let eastAsia = project(lon: 60, lat: 35)
routes.move(to: northAmerica)
routes.addCurve(to: europe, control1: CGPoint(x: 360, y: 810), control2: CGPoint(x: 470, y: 820))
routes.move(to: europe)
routes.addCurve(to: eastAsia, control1: CGPoint(x: 620, y: 820), control2: CGPoint(x: 720, y: 790))
stroke(routes, with: routeColor, width: 8)

for point in [northAmerica, europe, eastAsia] {
    let halo = CGPath(ellipseIn: CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36), transform: nil)
    fill(halo, with: color(0.04, 0.19, 0.28, 0.65))
    let marker = CGPath(ellipseIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20), transform: nil)
    fill(marker, with: color(1, 0.77, 0.36))
    stroke(marker, with: color(1, 1, 0.92), width: 4)
}

for latitude in [-90.0, 90.0] {
    let pole = project(lon: 0, lat: latitude)
    let marker = CGPath(ellipseIn: CGRect(x: pole.x - 7, y: pole.y - 7, width: 14, height: 14), transform: nil)
    fill(marker, with: color(0.83, 0.98, 0.94, 0.9))
}

context.restoreGState()
stroke(globe, with: color(0.78, 0.97, 0.94, 0.9), width: 10)

guard let image = context.makeImage() else {
    fatalError("Could not create icon image")
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Could not create icon file at \(outputURL.path)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write icon file at \(outputURL.path)")
}
