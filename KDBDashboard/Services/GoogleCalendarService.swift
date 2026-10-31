import Foundation

/// Service for fetching Google Calendar events using OAuth 2.0 Device Code Flow
///
/// ## Google Cloud Console Setup Instructions:
///
/// 1. Go to https://console.cloud.google.com/
/// 2. Create a new project or select an existing one
/// 3. Navigate to "APIs & Services" > "Library"
/// 4. Search for "Google Calendar API" and enable it
/// 5. Go to "APIs & Services" > "Credentials"
/// 6. Click "Create Credentials" > "OAuth client ID"
/// 7. Select "TVs and Limited Input devices" as application type
/// 8. Enter a name (e.g., "TVWidget")
/// 9. Click "Create"
/// 10. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and
///     paste the Client ID and Client Secret into it (that file is gitignored)
///
/// ## OAuth Consent Screen Setup:
/// 1. Go to "APIs & Services" > "OAuth consent screen"
/// 2. Select "External" user type (unless you have a Google Workspace)
/// 3. Fill in the required fields (App name, support email, developer email)
/// 4. Add scopes: `.../auth/calendar.readonly`
/// 5. Add your Google account as a test user
///
@MainActor
class GoogleCalendarService: ObservableObject {
    // MARK: - Configuration

    /// OAuth client credentials, injected at build time from `Config/Secrets.xcconfig`
    /// via the `GoogleClientID` / `GoogleClientSecret` keys in Info.plist.
    private let clientId = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? ""
    private let clientSecret = Bundle.main.object(forInfoDictionaryKey: "GoogleClientSecret") as? String ?? ""

    private let deviceCodeEndpoint = "https://oauth2.googleapis.com/device/code"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let calendarEndpoint = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
    private let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    // MARK: - Published Properties

    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?

    /// Device code flow state - display this to the user
    @Published var deviceCode: DeviceCodeResponse?
    @Published var isWaitingForAuthorization = false

    // MARK: - Private Properties

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpirationDate: Date?
    private var pollingTimer: Task<Void, Never>?
    private var periodicUpdateTask: Task<Void, Never>?

    private let userDefaults = UserDefaults.standard
    private let accessTokenKey = "GoogleCalendarAccessToken"
    private let refreshTokenKey = "GoogleCalendarRefreshToken"
    private let expirationKey = "GoogleCalendarTokenExpiration"

    // MARK: - Initialization

    init() {
        loadStoredTokens()
    }

    // MARK: - Token Persistence

    private func loadStoredTokens() {
        KeychainStore.migrateFromUserDefaults(key: accessTokenKey)
        KeychainStore.migrateFromUserDefaults(key: refreshTokenKey)

        accessToken = KeychainStore.string(forKey: accessTokenKey)
        refreshToken = KeychainStore.string(forKey: refreshTokenKey)
        if let expiration = userDefaults.object(forKey: expirationKey) as? Date {
            tokenExpirationDate = expiration
        }

        if accessToken != nil && refreshToken != nil {
            isAuthenticated = true

            // Check if token needs refresh
            if let expiration = tokenExpirationDate, Date() >= expiration {
                Task {
                    await refreshAccessToken()
                }
            }
        }
    }

    private func storeTokens(accessToken: String, refreshToken: String?, expiresIn: Int) {
        self.accessToken = accessToken
        if let refresh = refreshToken {
            self.refreshToken = refresh
            KeychainStore.set(refresh, forKey: refreshTokenKey)
        }

        let expiration = Date().addingTimeInterval(TimeInterval(expiresIn - 60)) // 60s buffer
        tokenExpirationDate = expiration

        KeychainStore.set(accessToken, forKey: accessTokenKey)
        userDefaults.set(expiration, forKey: expirationKey)

        isAuthenticated = true
    }

    /// Clears stored tokens and signs out
    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        isAuthenticated = false
        events = []
        deviceCode = nil
        isWaitingForAuthorization = false

        KeychainStore.remove(forKey: accessTokenKey)
        KeychainStore.remove(forKey: refreshTokenKey)
        userDefaults.removeObject(forKey: expirationKey)

        pollingTimer?.cancel()
    }

    // MARK: - Device Code Flow

    /// Initiates the device code authorization flow
    /// Shows a code that the user enters at google.com/device
    func startDeviceAuthorization() async {
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            errorMessage = "Google sign-in isn't configured. Add your OAuth client to Config/Secrets.xcconfig and rebuild."
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: URL(string: deviceCodeEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientId)&scope=\(calendarScope)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isLoading = false
                errorMessage = "Failed to start authorization"
                return
            }

            let deviceResponse = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
            deviceCode = deviceResponse
            isWaitingForAuthorization = true
            isLoading = false

            // Start polling for authorization
            startPollingForToken(deviceCode: deviceResponse)

        } catch {
            isLoading = false
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    /// Polls Google's token endpoint waiting for user to authorize
    private func startPollingForToken(deviceCode: DeviceCodeResponse) {
        pollingTimer?.cancel()

        pollingTimer = Task {
            let interval = TimeInterval(deviceCode.interval)
            let expiresAt = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))

            while Date() < expiresAt && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                if Task.isCancelled { break }

                let result = await pollForToken(deviceCode: deviceCode.deviceCode)

                switch result {
                case .success(let token):
                    storeTokens(
                        accessToken: token.accessToken,
                        refreshToken: token.refreshToken,
                        expiresIn: token.expiresIn
                    )
                    self.deviceCode = nil
                    isWaitingForAuthorization = false
                    await fetchEvents()
                    return

                case .pending:
                    // Continue polling
                    continue

                case .error(let message):
                    errorMessage = message
                    isWaitingForAuthorization = false
                    self.deviceCode = nil
                    return
                }
            }

            if !Task.isCancelled {
                errorMessage = "Authorization timed out"
                isWaitingForAuthorization = false
                self.deviceCode = nil
            }
        }
    }

    private enum PollResult {
        case success(TokenResponse)
        case pending
        case error(String)
    }

    private func pollForToken(deviceCode: String) async -> PollResult {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientId)&client_secret=\(clientSecret)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // Try to decode as success
            if let token = try? JSONDecoder().decode(TokenResponse.self, from: data) {
                return .success(token)
            }

            // Try to decode as error
            if let error = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) {
                switch error.error {
                case "authorization_pending":
                    return .pending
                case "slow_down":
                    return .pending
                case "access_denied":
                    return .error("Access denied by user")
                case "expired_token":
                    return .error("Authorization expired")
                default:
                    return .error(error.errorDescription ?? error.error)
                }
            }

            return .error("Unknown response")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Token Refresh

    private func refreshAccessToken() async {
        guard let refresh = refreshToken else {
            isAuthenticated = false
            return
        }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(refresh)&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // Refresh failed, need to re-authenticate
                isAuthenticated = false
                return
            }

            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            storeTokens(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? refresh,
                expiresIn: token.expiresIn
            )

        } catch {
            isAuthenticated = false
        }
    }

    // MARK: - Calendar API

    /// Fetches upcoming calendar events
    func fetchEvents() async {
        // Ensure we have a valid token
        if let expiration = tokenExpirationDate, Date() >= expiration {
            await refreshAccessToken()
        }

        guard let token = accessToken else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        errorMessage = nil

        // Fetch events for the current month plus buffer for adjacent months in grid view
        let calendar = Calendar.current
        let now = Date()

        // Start from the beginning of the current month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        // Go back 7 days to include previous month days shown in grid
        let timeMinDate = calendar.date(byAdding: .day, value: -7, to: startOfMonth)!
        // Go forward 45 days to cover current month plus next month days in grid
        let timeMaxDate = calendar.date(byAdding: .day, value: 45, to: startOfMonth)!

        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: timeMinDate)
        let timeMax = formatter.string(from: timeMaxDate)

        var urlComponents = URLComponents(string: calendarEndpoint)!
        urlComponents.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "100")
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                isLoading = false
                errorMessage = "Invalid response"
                return
            }

            if httpResponse.statusCode == 401 {
                // Token expired, try refresh
                await refreshAccessToken()
                isLoading = false
                await fetchEvents()
                return
            }

            guard httpResponse.statusCode == 200 else {
                isLoading = false
                errorMessage = "Failed to fetch events (HTTP \(httpResponse.statusCode))"
                return
            }

            let calendarResponse = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)

            let allItems = calendarResponse.items ?? []

            // Filter out working locations, out of office, and focus time events
            let displayableItems = allItems.filter { $0.isDisplayableEvent }
            events = displayableItems.map { $0.toCalendarEvent() }
            isLoading = false

        } catch {
            isLoading = false
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    /// Starts periodic event updates every 5 minutes
    func startPeriodicUpdates() {
        // Cancel existing task if any
        periodicUpdateTask?.cancel()

        periodicUpdateTask = Task {
            if isAuthenticated {
                await fetchEvents()
            }

            // Update every 5 minutes
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)

                if !Task.isCancelled && isAuthenticated {
                    await fetchEvents()
                }
            }
        }
    }

    deinit {
        periodicUpdateTask?.cancel()
        pollingTimer?.cancel()
    }
}
