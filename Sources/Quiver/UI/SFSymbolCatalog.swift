import Foundation

/// A bundled, categorized list of common SF Symbol names for the icon picker. macOS has no API to
/// enumerate every SF Symbol, so search/browse runs over this curated set (~500 across themed
/// categories). The picker validates each name with `NSImage(systemSymbolName:)`, so any name missing
/// on a given macOS version is silently skipped — nothing broken can be shown or selected.
enum SFSymbolCatalog {
    struct Category: Identifiable {
        let name: String
        let symbols: [String]
        var id: String { name }
    }

    static let categories: [Category] = [
        Category(name: "Windows & Layout", symbols: [
            "macwindow", "macwindow.on.rectangle", "macwindow.badge.plus", "rectangle", "rectangle.fill",
            "rectangle.on.rectangle", "rectangle.split.2x1", "rectangle.split.3x1", "rectangle.split.2x2",
            "rectangle.3.group", "rectangle.3.group.fill", "rectangle.grid.2x2", "rectangle.grid.1x2",
            "square.grid.2x2", "square.grid.3x3", "square.grid.3x2", "sidebar.left", "sidebar.right",
            "sidebar.squares.left", "menubar.rectangle", "menubar.dock.rectangle", "dock.rectangle",
            "squares.below.rectangle", "uiwindow.split.2x1", "rectangle.portrait", "inset.filled.rectangle",
        ]),
        Category(name: "Arrows & Navigation", symbols: [
            "arrow.up", "arrow.down", "arrow.left", "arrow.right", "arrow.up.right", "arrow.up.left",
            "arrow.down.right", "arrow.down.left", "arrow.clockwise", "arrow.counterclockwise",
            "arrow.uturn.left", "arrow.uturn.right", "arrow.uturn.up", "arrow.uturn.down", "arrow.turn.up.right",
            "arrow.2.squarepath", "arrow.triangle.2.circlepath", "arrow.triangle.branch", "arrow.triangle.merge",
            "arrow.triangle.swap", "arrow.left.arrow.right", "arrow.up.arrow.down", "arrowshape.up.fill",
            "arrowshape.right.fill", "arrowshape.turn.up.left.fill", "arrow.up.forward", "arrow.up.right.square",
            "chevron.right", "chevron.left", "chevron.up", "chevron.down", "chevron.up.chevron.down",
            "location", "location.fill", "location.north.line.fill", "location.circle", "scope", "map", "map.fill",
        ]),
        Category(name: "Camera, Photos & Video", symbols: [
            "camera", "camera.fill", "camera.circle", "camera.viewfinder", "camera.aperture", "camera.on.rectangle",
            "camera.macro", "camera.metering.center.weighted", "web.camera", "web.camera.fill", "video", "video.fill",
            "video.circle", "video.badge.plus", "photo", "photo.fill", "photo.on.rectangle", "photo.stack",
            "photo.artframe", "livephoto", "film", "film.fill", "eye", "eye.fill", "eye.slash", "rectangle.dashed",
        ]),
        Category(name: "People & Faces", symbols: [
            "person", "person.fill", "person.circle", "person.circle.fill", "person.2", "person.2.fill",
            "person.3", "person.crop.circle", "person.crop.square", "person.crop.rectangle",
            "person.crop.circle.badge.plus", "person.bust", "person.bust.fill", "person.fill.viewfinder",
            "face.smiling", "face.smiling.fill", "face.dashed", "figure.walk", "figure.stand", "hand.wave",
            "hand.raised", "hand.thumbsup", "hand.thumbsup.fill", "hands.clap",
        ]),
        Category(name: "Communication", symbols: [
            "envelope", "envelope.fill", "envelope.open", "envelope.badge", "bubble.left", "bubble.left.fill",
            "bubble.right", "text.bubble", "text.bubble.fill", "message", "message.fill", "phone", "phone.fill",
            "phone.circle", "bell", "bell.fill", "bell.badge", "bell.slash", "megaphone", "megaphone.fill",
            "paperplane", "paperplane.fill", "at", "quote.bubble",
        ]),
        Category(name: "Media & Audio", symbols: [
            "play", "play.fill", "play.circle", "pause", "pause.fill", "playpause", "playpause.fill", "stop",
            "stop.fill", "forward", "backward", "forward.fill", "backward.fill", "speaker", "speaker.wave.1",
            "speaker.wave.2", "speaker.wave.2.fill", "speaker.slash", "music.note", "music.note.list", "music.mic",
            "waveform", "waveform.circle", "mic", "mic.fill", "mic.slash", "headphones", "radio", "guitars",
        ]),
        Category(name: "Files & Storage", symbols: [
            "folder", "folder.fill", "folder.badge.plus", "folder.circle", "doc", "doc.fill", "doc.text",
            "doc.text.fill", "doc.on.doc", "doc.on.clipboard", "clipboard", "note.text", "tray", "tray.fill",
            "tray.full", "tray.and.arrow.down", "tray.and.arrow.up", "archivebox", "archivebox.fill",
            "externaldrive", "externaldrive.fill", "internaldrive", "square.and.arrow.down", "square.and.arrow.up",
            "shippingbox", "shippingbox.fill", "books.vertical", "book", "book.fill", "bookmark", "bookmark.fill",
        ]),
        Category(name: "Text & Editing", symbols: [
            "textformat", "textformat.size", "bold", "italic", "underline", "strikethrough", "text.alignleft",
            "text.aligncenter", "text.alignright", "text.justify", "list.bullet", "list.number", "list.bullet.indent",
            "pencil", "pencil.tip", "pencil.circle", "square.and.pencil", "highlighter", "eraser", "scissors",
            "paintbrush", "paintbrush.fill", "paintpalette", "character", "textbox",
        ]),
        Category(name: "System & Settings", symbols: [
            "gearshape", "gearshape.fill", "gearshape.2", "gearshape.2.fill", "slider.horizontal.3",
            "slider.vertical.3", "switch.2", "dial.min", "dial.max", "gauge", "gauge.with.dots.needle.50percent",
            "power", "powersleep", "powerplug", "cpu", "memorychip", "command", "option", "control", "escape",
            "capslock", "restart", "lock", "lock.fill", "lock.open", "lock.shield", "key", "key.fill", "touchid", "faceid",
        ]),
        Category(name: "Devices & Hardware", symbols: [
            "desktopcomputer", "laptopcomputer", "macbook", "display", "display.2", "keyboard", "magicmouse",
            "magicmouse.fill", "computermouse", "iphone", "ipad", "applewatch", "airpods", "homepod", "printer",
            "printer.fill", "tv", "tv.fill", "gamecontroller", "gamecontroller.fill", "cursorarrow",
            "cursorarrow.rays", "hifispeaker", "hifispeaker.fill",
        ]),
        Category(name: "Network & Web", symbols: [
            "network", "globe", "globe.americas.fill", "globe.europe.africa.fill", "wifi", "wifi.slash",
            "antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right", "point.3.connected.trianglepath.dotted",
            "link", "link.circle", "personalhotspot", "cable.connector", "server.rack", "cloud", "cloud.fill",
            "icloud", "icloud.fill", "icloud.and.arrow.up", "icloud.and.arrow.down", "safari", "safari.fill",
        ]),
        Category(name: "Shapes & Symbols", symbols: [
            "circle", "circle.fill", "square", "square.fill", "triangle", "triangle.fill", "diamond", "diamond.fill",
            "hexagon", "hexagon.fill", "octagon", "octagon.fill", "seal", "seal.fill", "shield", "shield.fill",
            "shield.lefthalf.filled", "star", "star.fill", "star.circle", "sparkle", "sparkles", "heart", "heart.fill",
            "heart.circle", "suit.heart.fill", "suit.diamond.fill", "suit.club.fill", "suit.spade.fill", "app",
            "app.fill", "app.badge", "capsule", "capsule.fill",
        ]),
        Category(name: "Status & Alerts", symbols: [
            "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.seal", "checkmark.seal.fill",
            "xmark", "xmark.circle", "xmark.circle.fill", "xmark.octagon.fill", "exclamationmark",
            "exclamationmark.triangle", "exclamationmark.triangle.fill", "exclamationmark.circle", "questionmark",
            "questionmark.circle", "info.circle", "info.circle.fill", "plus", "plus.circle", "plus.circle.fill",
            "minus", "minus.circle", "nosign", "hand.raised.fill", "flag", "flag.fill", "flag.checkered",
        ]),
        Category(name: "Nature & Weather", symbols: [
            "sun.max", "sun.max.fill", "sun.min", "sunrise", "sunset", "moon", "moon.fill", "moon.stars",
            "moon.zzz", "moon.zzz.fill", "cloud.rain", "cloud.rain.fill", "cloud.bolt", "cloud.snow", "cloud.sun",
            "cloud.sun.fill", "snowflake", "wind", "tornado", "drop", "drop.fill", "flame", "flame.fill", "leaf",
            "leaf.fill", "tree", "pawprint", "pawprint.fill", "ant", "ladybug", "fish", "bird", "hare", "tortoise",
        ]),
        Category(name: "Time & Calendar", symbols: [
            "clock", "clock.fill", "clock.badge", "alarm", "alarm.fill", "timer", "stopwatch", "stopwatch.fill",
            "hourglass", "hourglass.bottomhalf.filled", "calendar", "calendar.badge.plus", "calendar.badge.clock",
            "calendar.circle", "deskclock", "sunrise.fill", "sunset.fill", "moon.circle",
        ]),
        Category(name: "Commerce & Finance", symbols: [
            "cart", "cart.fill", "cart.badge.plus", "bag", "bag.fill", "creditcard", "creditcard.fill", "banknote",
            "banknote.fill", "dollarsign.circle", "dollarsign.circle.fill", "eurosign.circle", "gift", "gift.fill",
            "tag", "tag.fill", "percent", "chart.bar", "chart.bar.fill", "chart.pie", "chart.line.uptrend.xyaxis",
            "wallet.pass",
        ]),
        Category(name: "Transport & Places", symbols: [
            "car", "car.fill", "bus", "bus.fill", "tram", "tram.fill", "bicycle", "airplane", "airplane.departure",
            "airplane.arrival", "fuelpump", "fuelpump.fill", "parkingsign", "parkingsign.circle", "house",
            "house.fill", "house.circle", "building.2", "building.2.fill", "building.columns", "mappin",
            "mappin.circle", "mappin.and.ellipse", "signpost.right", "signpost.right.fill",
        ]),
        Category(name: "Tools & Objects", symbols: [
            "wrench", "wrench.fill", "wrench.and.screwdriver", "wrench.and.screwdriver.fill", "hammer", "hammer.fill",
            "screwdriver", "screwdriver.fill", "ruler", "ruler.fill", "paperclip", "magnifyingglass",
            "magnifyingglass.circle", "trash", "trash.fill", "trash.circle", "bolt", "bolt.fill", "bolt.circle",
            "bolt.slash", "battery.100", "battery.25", "lightbulb", "lightbulb.fill", "flashlight.on.fill",
            "eyedropper", "cup.and.saucer", "cup.and.saucer.fill", "flame.circle", "wand.and.stars",
        ]),
        Category(name: "Health & Fitness", symbols: [
            "heart.text.square", "cross", "cross.fill", "cross.case", "pills", "pills.fill", "bandage",
            "bandage.fill", "stethoscope", "figure.run", "bed.double", "bed.double.fill", "zzz", "drop.degreesign",
        ]),
    ]

    /// Flattened, de-duplicated list of all catalog names (used for search).
    static let names: [String] = {
        var seen = Set<String>()
        return categories.flatMap { $0.symbols }.filter { seen.insert($0).inserted }
    }()
}
