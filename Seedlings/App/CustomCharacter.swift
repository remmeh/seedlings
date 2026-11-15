import SwiftUI
import ImagePlayground
import Vision
import CoreImage

struct CustomCharacter: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var pngData: Data
    var territoryHex: Int
    var image: UIImage? { UIImage(data: pngData) }
    var color: UIColor { UIColor(hex: territoryHex) }
    var darkColor: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.52, green: g * 0.52, blue: b * 0.52, alpha: 1)
    }
}

struct CustomCharacterStore {
    var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SeedlingsCharacters", isDirectory: true)
    private var file: URL { directory.appendingPathComponent("character.json") }
    func load() throws -> CustomCharacter {
        let character = try JSONDecoder().decode(CustomCharacter.self, from: Data(contentsOf: file))
        guard let image = character.image, image.size.width == 64, image.size.height == 64,
              !character.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...0xFFFFFF).contains(character.territoryHex) else { throw CharacterError.invalidImage }
        return character
    }
    func save(_ character: CustomCharacter) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(character).write(to: file, options: .atomic)
    }
}

enum CharacterError: LocalizedError {
    case invalidImage, noSubject
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "This image couldn’t be prepared. Please try another character."
        case .noSubject: return "We couldn’t separate the character from its background. Try a single character on a plain background."
        }
    }
}

enum CharacterProcessor {
    static func create(from data: Data, name: String) throws -> CustomCharacter {
        guard let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw CharacterError.invalidImage }
        let context = CIContext()
        guard let image = context.createCGImage(input, from: input.extent) else { throw CharacterError.invalidImage }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw CharacterError.noSubject }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        let cutout = CIImage(cvPixelBuffer: buffer)
        guard let foreground = context.createCGImage(cutout, from: cutout.extent) else { throw CharacterError.invalidImage }
        return try pixelCharacter(from: foreground, name: name)
    }

    /// Separate from Vision so sizing, transparency, palette and storage are testable offline.
    static func pixelCharacter(from image: CGImage, name: String) throws -> CustomCharacter {
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !cleanName.isEmpty else { throw CharacterError.invalidImage }
        let size = 64
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterError.invalidImage }
        let scale = min(56.0 / Double(image.width), 56.0 / Double(image.height))
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (64 - width) / 2, y: (64 - height) / 2, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { throw CharacterError.invalidImage }
        var colors: [Int: Int] = [:]
        for index in 0..<(size * size) {
            let offset = index * 4
            let alpha = Int(pixels[offset + 3])
            guard alpha >= 128 else {
                for channel in 0..<4 { pixels[offset + channel] = 0 }
                continue
            }
            var hex = 0
            for channel in 0..<3 {
                let straight = min(255, Int(pixels[offset + channel]) * 255 / alpha)
                let quantized = min(255, ((straight + 8) / 17) * 17)
                pixels[offset + channel] = UInt8(quantized)
                hex = (hex << 8) | quantized
            }
            pixels[offset + 3] = 255
            colors[hex, default: 0] += 1
        }
        guard !colors.isEmpty, let output = context.makeImage(), let png = UIImage(cgImage: output).pngData() else { throw CharacterError.invalidImage }
        let accent = colors.max { score($0.key, count: $0.value) < score($1.key, count: $1.value) }!.key
        return CustomCharacter(name: cleanName, pngData: png, territoryHex: territoryColor(UIColor(hex: accent)))
    }

    private static func score(_ hex: Int, count: Int) -> Double {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(count) * (0.2 + Double(s)) * (b > 0.2 && b < 0.96 ? 1 : 0.15)
    }

    static func territoryColor(_ color: UIColor) -> Int {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let readable = UIColor(hue: h, saturation: min(0.65, max(0.25, s)), brightness: min(0.88, max(0.65, b)), alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, blue: CGFloat = 0
        readable.getRed(&r, green: &g, blue: &blue, alpha: &a)
        return Int(r * 255) << 16 | Int(g * 255) << 8 | Int(blue * 255)
    }
}

@available(iOS 18.2, *)
struct CustomCharacterCreator: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.supportsImagePlayground) private var supported
    @State private var description = ""
    @State private var name = ""
    @State private var presentingPlayground = false
    @State private var processing = false
    @State private var draft: CustomCharacter?
    @State private var accent = Color.orange
    @State private var savedToPicker = false
    @State private var errorMessage: String?
    let onSave: (CustomCharacter) throws -> Void

    init(character: CustomCharacter? = nil, onSave: @escaping (CustomCharacter) throws -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: character)
        _savedToPicker = State(initialValue: character != nil)
        _name = State(initialValue: character?.name ?? "")
        _description = State(initialValue: character?.name ?? "")
        _accent = State(initialValue: character.map { Color($0.color) } ?? .orange)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Meet your little self.").font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("Describe a character—like a smiling dumpling—then choose an image in Image Playground.")
                        .foregroundStyle(Color.moss)
                    TextField("A cute dumpling", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .onChange(of: description) { _, value in description = String(value.prefix(500)) }
                    Button { presentingPlayground = true } label: {
                        Label(draft == nil ? "Create with Image Playground" : "Try another image", systemImage: "sparkles")
                            .fontWeight(.bold).frame(maxWidth: .infinity).padding()
                    }.buttonStyle(.borderedProminent).tint(Color.ink)
                        .disabled(!supported || processing || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !supported {
                        Text("Image Playground isn’t available right now. Enable Apple Intelligence in Settings and make sure its image creation features are available for this device and language.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if processing { ProgressView("Preparing your pixel character…").frame(maxWidth: .infinity) }
                    if let draft, let image = draft.image {
                        VStack(spacing: 16) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 160, height: 160)
                                .padding(32).frame(maxWidth: .infinity)
                                .background(Color(UIColor(hex: CharacterProcessor.territoryColor(UIColor(accent)))), in: RoundedRectangle(cornerRadius: 24))
                            TextField("Character name", text: $name).textFieldStyle(.roundedBorder)
                                .onChange(of: name) { _, value in name = String(value.prefix(30)) }
                            ColorPicker("Territory color", selection: $accent, supportsOpacity: false)
                            Text("Your territory, trail and seeds use this color. We adjust lightness for visibility.")
                                .font(.caption).foregroundStyle(.secondary)
                            if savedToPicker {
                                Label("Saved and selected in your character picker", systemImage: "checkmark.circle.fill")
                                    .font(.callout).foregroundStyle(Color.moss)
                            }
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
                    Text("Your saved character stays on this iPad. You can always switch back to the fruit characters.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(28)
            }
            .background(Color.paper)
            .navigationTitle("Custom character").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(processing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use character") { if let draft { save(draft) } }
                        .fontWeight(.bold)
                        .disabled(draft == nil || processing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(processing)
        .imagePlaygroundSheet(isPresented: $presentingPlayground, concepts: [
            .text(description), .text("One cute game mascot, full body, centered, simple plain background, no text")
        ]) { url in
            presentingPlayground = false
            do {
                let data = try Data(contentsOf: url)
                let prompt = description
                processing = true; errorMessage = nil
                Task {
                    do {
                        let character = try await Task.detached(priority: .userInitiated) {
                            try CharacterProcessor.create(from: data, name: prompt)
                        }.value
                        draft = character; name = character.name; accent = Color(character.color)
                        do { try onSave(character); savedToPicker = true }
                        catch { savedToPicker = false; errorMessage = "Your image is ready, but couldn’t be saved. Tap Use character to retry." }
                    } catch { errorMessage = "Couldn’t prepare that image. \(error.localizedDescription)" }
                    processing = false
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save(_ character: CustomCharacter) {
        var saved = character
        saved.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.territoryHex = CharacterProcessor.territoryColor(UIColor(accent))
        do { try onSave(saved); dismiss() }
        catch { errorMessage = "Couldn’t save your character. Please try again." }
    }
}
