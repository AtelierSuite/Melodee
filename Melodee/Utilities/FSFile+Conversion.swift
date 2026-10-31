import Foundation

extension FSFile {

    /// Returns true if this audio file can be converted to other formats
    func isConvertibleAudio() -> Bool {
        let convertibleFormats = ["mp3", "m4a", "wav", "alac"]
        return convertibleFormats.contains(self.extension)
    }

    /// Returns available conversion formats for this audio file
    func availableConversionFormats() -> [String] {
        return AudioConverter.availableFormats(for: self.extension)
    }
}
