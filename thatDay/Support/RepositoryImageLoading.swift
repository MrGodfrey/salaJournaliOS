import Foundation
import UIKit

extension URL {
    var repositoryLocalImage: UIImage? {
        guard isFileURL else {
            return nil
        }

        return UIImage(contentsOfFile: path)
    }
}
