import Foundation
import UIKit

extension URL {
    nonisolated var repositoryLocalImage: UIImage? {
        guard isFileURL else {
            return nil
        }

        return UIImage(contentsOfFile: path)
    }
}
