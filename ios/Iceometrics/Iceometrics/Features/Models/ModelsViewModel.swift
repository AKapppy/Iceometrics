
import Foundation
import Combine

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published private(set) var snapshot: ModelsSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: ModelsDataService
    private var hasLoaded = false

    init(
        service: ModelsDataService = ModelsDataService()
    ) {
        self.service = service
    }

    var updatedText: String {
        guard let generatedAt = snapshot?.generatedAt else {
            return "Not updated yet"
        }

        return "Updated \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = await service.cachedSnapshot() {
            snapshot = cached
            
        }

        await load(forceRefresh: false)
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await service.fetchSnapshot(
                forceRefresh: forceRefresh
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
