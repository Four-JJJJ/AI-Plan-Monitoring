import Foundation
import OhMyUsageDomain

extension ProviderDescriptor {
    func normalized() -> ProviderDescriptor {
        ProviderDescriptorNormalizer.normalized(self)
    }
}
