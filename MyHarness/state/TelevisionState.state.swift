import Foundation
import Observation

@MainActor
@Observable
final class TelevisionState {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var channels: [TelevisionChannel] = []
    var selectedChannel: TelevisionChannel?
    var quality: TelevisionStreamQuality = .high
    var loadState: LoadState = .idle

    private let client: KonomiTVAPIClient

    init(client: KonomiTVAPIClient) {
        self.client = client
    }

    func loadChannels() async {
        loadState = .loading
        do {
            let previousSelectionID = selectedChannel?.id
            let groups = try await client.fetchChannels()
            let loadedChannels = groups.displayableTerrestrialChannels
            channels = loadedChannels
            selectedChannel = previousSelectionID.flatMap { selectionID in
                loadedChannels.first { $0.id == selectionID }
            }
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func select(_ channel: TelevisionChannel) {
        selectedChannel = channel
    }
}
