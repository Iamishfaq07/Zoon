import AppIntents

/// Soundscape names Siri can say. Duplicates `SoundscapeEngine.Sound` labels
/// rather than importing the engine: App Intents metadata is analysed at
/// build time and cannot see a computed dictionary the way the compiler can.
enum SoundscapeSound: String, AppEnum {
    case brownNoise, pinkNoise, whiteNoise
    case rain, rainfall, window, tent, storm, thunder, drizzle, street
    case ocean, harbor, waterfall, wind, blizzard, stream, brook
    case forest, jungle, evening, garden, crickets, insects, pond, mountain
    case fan, fire, embers, purr

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sleep Sound" }

    static var caseDisplayRepresentations: [SoundscapeSound: DisplayRepresentation] {
        [
            .brownNoise: DisplayRepresentation(title: "Brown Noise"),
            .pinkNoise: DisplayRepresentation(title: "Pink Noise"),
            .whiteNoise: DisplayRepresentation(title: "White Noise"),
            .rain: DisplayRepresentation(title: "Rain"),
            .rainfall: DisplayRepresentation(title: "Shower"),
            .window: DisplayRepresentation(title: "Window"),
            .tent: DisplayRepresentation(title: "Tent"),
            .storm: DisplayRepresentation(title: "Storm"),
            .thunder: DisplayRepresentation(title: "Thunder"),
            .drizzle: DisplayRepresentation(title: "Drizzle"),
            .street: DisplayRepresentation(title: "Street"),
            .ocean: DisplayRepresentation(title: "Ocean"),
            .harbor: DisplayRepresentation(title: "Harbor"),
            .waterfall: DisplayRepresentation(title: "Falls"),
            .wind: DisplayRepresentation(title: "Wind"),
            .blizzard: DisplayRepresentation(title: "Blizzard"),
            .stream: DisplayRepresentation(title: "Stream"),
            .brook: DisplayRepresentation(title: "Brook"),
            .forest: DisplayRepresentation(title: "Forest"),
            .jungle: DisplayRepresentation(title: "Jungle"),
            .evening: DisplayRepresentation(title: "Evening"),
            .garden: DisplayRepresentation(title: "Garden"),
            .crickets: DisplayRepresentation(title: "Crickets"),
            .insects: DisplayRepresentation(title: "Insects"),
            .pond: DisplayRepresentation(title: "Pond"),
            .mountain: DisplayRepresentation(title: "Ridge"),
            .fan: DisplayRepresentation(title: "Fan"),
            .fire: DisplayRepresentation(title: "Fire"),
            .embers: DisplayRepresentation(title: "Embers"),
            .purr: DisplayRepresentation(title: "Purr")
        ]
    }

    var label: String {
        switch self {
        case .brownNoise: "Brown Noise"
        case .pinkNoise: "Pink Noise"
        case .whiteNoise: "White Noise"
        case .rain: "Rain"
        case .rainfall: "Shower"
        case .window: "Window"
        case .tent: "Tent"
        case .storm: "Storm"
        case .thunder: "Thunder"
        case .drizzle: "Drizzle"
        case .street: "Street"
        case .ocean: "Ocean"
        case .harbor: "Harbor"
        case .waterfall: "Falls"
        case .wind: "Wind"
        case .blizzard: "Blizzard"
        case .stream: "Stream"
        case .brook: "Brook"
        case .forest: "Forest"
        case .jungle: "Jungle"
        case .evening: "Evening"
        case .garden: "Garden"
        case .crickets: "Crickets"
        case .insects: "Insects"
        case .pond: "Pond"
        case .mountain: "Ridge"
        case .fan: "Fan"
        case .fire: "Fire"
        case .embers: "Embers"
        case .purr: "Purr"
        }
    }
}
