import Foundation
import Combine

/// Coordinates Google Calendar and iCloud Calendar services,
/// merging events into a single unified list for the view layer
@MainActor
class CalendarManager: ObservableObject {
    // MARK: - Child Services

    let googleService: GoogleCalendarService
    let icloudService: ICloudCalendarService

    // MARK: - Published Properties (merged state)

    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// True if at least one calendar source is authenticated
    var hasAnyAuthentication: Bool {
        googleService.isAuthenticated || icloudService.isAuthenticated
    }

    /// True if neither source is authenticated
    var needsSetup: Bool {
        !googleService.isAuthenticated && !icloudService.isAuthenticated
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        self.googleService = GoogleCalendarService()
        self.icloudService = ICloudCalendarService()

        setupEventMerging()
    }

    // MARK: - Event Merging

    /// Observes both services' event arrays and merges them whenever either changes
    private func setupEventMerging() {
        googleService.$events
            .combineLatest(icloudService.$events)
            .map { googleEvents, icloudEvents in
                (googleEvents + icloudEvents).sorted { $0.startTime < $1.startTime }
            }
            .assign(to: &$events)

        googleService.$isLoading
            .combineLatest(icloudService.$isLoading)
            .map { $0 || $1 }
            .assign(to: &$isLoading)

        googleService.$errorMessage
            .combineLatest(icloudService.$errorMessage)
            .map { googleError, icloudError in
                googleError ?? icloudError
            }
            .assign(to: &$errorMessage)

        // Forward child changes so views reading nested state (auth status, device code) refresh
        googleService.objectWillChange
            .merge(with: icloudService.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Fetches events from all authenticated sources in parallel
    func fetchAllEvents() async {
        async let googleFetch: () = fetchGoogleIfNeeded()
        async let icloudFetch: () = fetchICloudIfNeeded()
        _ = await (googleFetch, icloudFetch)
    }

    private func fetchGoogleIfNeeded() async {
        if googleService.isAuthenticated {
            await googleService.fetchEvents()
        }
    }

    private func fetchICloudIfNeeded() async {
        if icloudService.isAuthenticated {
            await icloudService.fetchEvents()
        }
    }

    /// Starts periodic updates for all authenticated services
    func startPeriodicUpdates() {
        googleService.startPeriodicUpdates()
        icloudService.startPeriodicUpdates()
    }
}
