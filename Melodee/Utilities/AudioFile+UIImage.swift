import SFBAudioEngine
import UIKit

extension AudioFile {

    /// Cover art as a UIImage, if any attached picture is present.
    var coverImage: UIImage? {
        guard let data = coverArtData else { return nil }
        return UIImage(data: data)
    }
}
