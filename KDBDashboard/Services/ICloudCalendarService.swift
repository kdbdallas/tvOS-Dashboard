import Foundation

/// Service for fetching iCloud Calendar events via the CalDAV protocol
///
/// ## Setup Instructions:
///
/// 1. Go to https://appleid.apple.com/account/manage
/// 2. Sign in with your Apple ID
/// 3. Go to "Sign-In and Security" > "App-Specific Passwords"
/// 4. Click "Generate an App-Specific Password"
/// 5. Name it something like "KDB Dashboard"
/// 6. Copy the 16-character password (format: xxxx-xxxx-xxxx-xxxx)
/// 7. Enter your Apple ID email and this password in the app
///
@MainActor
class ICloudCalendarService: ObservableObject {
    // MARK: - Configuration

    private let caldavBaseURL = "https://caldav.icloud.com/"

    // MARK: - Published Properties

    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var availableCalendars: [CalDAVCalendar] = []
    @Published var selectedCalendarHrefs: Set<String> = []

    // MARK: - Private Properties

    private var appleIdEmail: String?
    private var appSpecificPassword: String?
    private var calendarHomeURL: String?
    private var principalURL: String?
    private var periodicUpdateTask: Task<Void, Never>?

    private let userDefaults = UserDefaults.standard
    private let emailKey = "ICloudCalDAVEmail"
    private let passwordKey = "ICloudCalDAVPassword"
    private let calendarHomeKey = "ICloudCalDAVCalendarHome"
    private let principalKey = "ICloudCalDAVPrincipal"
    private let selectedCalendarsKey = "ICloudCalDAVSelectedCalendars"
    private let calendarsKey = "ICloudCalDAVCalendars"

    /// URLSession with delegate that re-attaches auth on redirects
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        let delegate = AuthRedirectDelegate()
        delegate.authHeader = authorizationHeader
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    // MARK: - Initialization

    init() {
        loadStoredCredentials()
    }

    // MARK: - Auth Header

    private var authorizationHeader: String? {
        guard let email = appleIdEmail, let password = appSpecificPassword else { return nil }
        let credentials = "\(email):\(password)"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    // MARK: - Credential Management

    private func loadStoredCredentials() {
        KeychainStore.migrateFromUserDefaults(key: emailKey)
        KeychainStore.migrateFromUserDefaults(key: passwordKey)

        appleIdEmail = KeychainStore.string(forKey: emailKey)
        appSpecificPassword = KeychainStore.string(forKey: passwordKey)
        calendarHomeURL = userDefaults.string(forKey: calendarHomeKey)
        principalURL = userDefaults.string(forKey: principalKey)

        if let selectedArray = userDefaults.stringArray(forKey: selectedCalendarsKey) {
            selectedCalendarHrefs = Set(selectedArray)
        }

        if let calendarsData = userDefaults.data(forKey: calendarsKey),
           let calendars = try? JSONDecoder().decode([CalDAVCalendar].self, from: calendarsData) {
            availableCalendars = calendars
        }

        if appleIdEmail != nil && appSpecificPassword != nil {
            isAuthenticated = true
            // Update the session delegate's auth header
            (session.delegate as? AuthRedirectDelegate)?.authHeader = authorizationHeader
        }
    }

    private func storeCredentials() {
        KeychainStore.set(appleIdEmail, forKey: emailKey)
        KeychainStore.set(appSpecificPassword, forKey: passwordKey)
        userDefaults.set(calendarHomeURL, forKey: calendarHomeKey)
        userDefaults.set(principalURL, forKey: principalKey)
        userDefaults.set(Array(selectedCalendarHrefs), forKey: selectedCalendarsKey)

        if let data = try? JSONEncoder().encode(availableCalendars) {
            userDefaults.set(data, forKey: calendarsKey)
        }
    }

    /// Authenticates with Apple ID email and app-specific password
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        // Strip dashes from app-specific password (user may paste with dashes)
        let cleanPassword = password.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces)

        appleIdEmail = email.trimmingCharacters(in: .whitespaces)
        appSpecificPassword = cleanPassword
        (session.delegate as? AuthRedirectDelegate)?.authHeader = authorizationHeader

        do {
            try await discoverCalendars()
            isAuthenticated = true
            storeCredentials()
            isLoading = false
            await fetchEvents()
        } catch {
            isLoading = false
            isAuthenticated = false
            appleIdEmail = nil
            appSpecificPassword = nil

            if let calDavError = error as? CalDAVError {
                errorMessage = calDavError.localizedDescription
            } else {
                errorMessage = "Failed to connect: \(error.localizedDescription)"
            }
        }
    }

    func signOut() {
        appleIdEmail = nil
        appSpecificPassword = nil
        calendarHomeURL = nil
        principalURL = nil
        isAuthenticated = false
        events = []
        availableCalendars = []
        selectedCalendarHrefs = []

        KeychainStore.remove(forKey: emailKey)
        KeychainStore.remove(forKey: passwordKey)
        userDefaults.removeObject(forKey: calendarHomeKey)
        userDefaults.removeObject(forKey: principalKey)
        userDefaults.removeObject(forKey: selectedCalendarsKey)
        userDefaults.removeObject(forKey: calendarsKey)
    }

    // MARK: - CalDAV Discovery

    /// Discovers the user's calendars via CalDAV PROPFIND requests
    private func discoverCalendars() async throws {
        // Step 1: Find current-user-principal
        let principalPath = try await findPrincipal()
        principalURL = principalPath

        // Step 2: Find calendar-home-set from principal
        let calHomePath = try await findCalendarHome(principalPath: principalPath)
        calendarHomeURL = calHomePath

        // Step 3: List calendars
        let calendars = try await listCalendars(calendarHomePath: calHomePath)
        availableCalendars = calendars

        // Auto-select all calendars if none were previously selected
        if selectedCalendarHrefs.isEmpty {
            selectedCalendarHrefs = Set(calendars.map { $0.href })
        }
    }

    /// Step 1: PROPFIND to caldav.icloud.com to find current-user-principal
    private func findPrincipal() async throws -> String {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:current-user-principal/>
          </d:prop>
        </d:propfind>
        """

        let data = try await sendPropfind(
            url: URL(string: caldavBaseURL)!,
            body: body,
            depth: "0"
        )

        let parser = CalendarHomePropfindParser(target: "current-user-principal")
        guard let href = parser.parse(data: data) else {
            throw CalDAVError.discoveryFailed("Could not find user principal")
        }

        return href
    }

    /// Step 2: PROPFIND to principal URL to find calendar-home-set
    private func findCalendarHome(principalPath: String) async throws -> String {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <c:calendar-home-set/>
          </d:prop>
        </d:propfind>
        """

        let url = resolveURL(path: principalPath)
        let data = try await sendPropfind(url: url, body: body, depth: "0")

        let parser = CalendarHomePropfindParser(target: "calendar-home-set")
        guard let href = parser.parse(data: data) else {
            throw CalDAVError.discoveryFailed("Could not find calendar home")
        }

        return href
    }

    /// Step 3: PROPFIND to calendar-home-set to list all calendars
    private func listCalendars(calendarHomePath: String) async throws -> [CalDAVCalendar] {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:ic="http://apple.com/ns/ical/">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
            <ic:calendar-color/>
          </d:prop>
        </d:propfind>
        """

        let url = resolveURL(path: calendarHomePath)
        let data = try await sendPropfind(url: url, body: body, depth: "1")

        let parser = CalendarListParser()
        let calendars = parser.parse(data: data)

        if calendars.isEmpty {
            throw CalDAVError.discoveryFailed("No calendars found")
        }

        return calendars
    }

    // MARK: - Event Fetching

    /// Fetches events from all selected calendars
    func fetchEvents() async {
        guard isAuthenticated else { return }

        isLoading = true
        errorMessage = nil

        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let timeMinDate = calendar.date(byAdding: .day, value: -7, to: startOfMonth)!
        let timeMaxDate = calendar.date(byAdding: .day, value: 45, to: startOfMonth)!

        var allEvents: [CalendarEvent] = []

        for calendarHref in selectedCalendarHrefs {
            do {
                let calEvents = try await fetchEventsFromCalendar(
                    href: calendarHref,
                    startDate: timeMinDate,
                    endDate: timeMaxDate
                )
                allEvents.append(contentsOf: calEvents)
            } catch {
                // Log but continue with other calendars
                print("Failed to fetch events from \(calendarHref): \(error)")
            }
        }

        events = allEvents.sorted { $0.startTime < $1.startTime }
        isLoading = false
    }

    /// Fetches events from a single calendar using REPORT calendar-query
    private func fetchEventsFromCalendar(href: String, startDate: Date, endDate: Date) async throws -> [CalendarEvent] {
        let startStr = formatCalDAVDate(startDate)
        let endStr = formatCalDAVDate(endDate)

        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <c:calendar-data/>
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="VEVENT">
                <c:time-range start="\(startStr)" end="\(endStr)"/>
              </c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """

        let url = resolveURL(path: href)
        let data = try await sendReport(url: url, body: body)

        let dataParser = CalendarDataParser()
        let icsBlocks = dataParser.parse(data: data)

        var events: [CalendarEvent] = []
        for icsBlock in icsBlocks {
            let parsed = ICalendarParser.parseEvents(from: icsBlock, rangeStart: startDate, rangeEnd: endDate)
            events.append(contentsOf: parsed)
        }
        return events
    }

    /// Formats a Date as CalDAV time-range format: "20260215T000000Z"
    private func formatCalDAVDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: - HTTP Helpers

    /// Sends a PROPFIND request with Basic Auth
    private func sendPropfind(url: URL, body: String, depth: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.httpBody = body.data(using: .utf8)

        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalDAVError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw CalDAVError.authenticationFailed
        }

        guard httpResponse.statusCode == 207 else {
            throw CalDAVError.httpError(httpResponse.statusCode)
        }

        return data
    }

    /// Sends a REPORT request with Basic Auth
    private func sendReport(url: URL, body: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "REPORT"
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.httpBody = body.data(using: .utf8)

        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalDAVError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw CalDAVError.authenticationFailed
        }

        guard httpResponse.statusCode == 207 else {
            throw CalDAVError.httpError(httpResponse.statusCode)
        }

        return data
    }

    /// Resolves a relative path against the CalDAV base URL
    private func resolveURL(path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)!
        }
        // Resolve against the base URL (which may have been redirected to pXX-caldav.icloud.com)
        return URL(string: path, relativeTo: URL(string: caldavBaseURL))?.absoluteURL
            ?? URL(string: caldavBaseURL + path)!
    }

    // MARK: - Periodic Updates

    /// Starts periodic event updates every 5 minutes
    func startPeriodicUpdates() {
        // Cancel existing task if any
        periodicUpdateTask?.cancel()

        periodicUpdateTask = Task {
            if isAuthenticated {
                await fetchEvents()
            }

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
    }
}

// MARK: - CalDAV Errors

enum CalDAVError: LocalizedError {
    case authenticationFailed
    case discoveryFailed(String)
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Authentication failed. Check your Apple ID and app-specific password."
        case .discoveryFailed(let detail):
            return "Calendar discovery failed: \(detail)"
        case .httpError(let code):
            return "Server error (HTTP \(code))"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

// MARK: - Auth Redirect Delegate

/// URLSession delegate that re-attaches the Authorization header on redirects.
/// Apple's CalDAV server redirects from caldav.icloud.com to pXX-caldav.icloud.com,
/// and URLSession strips the Authorization header on cross-origin redirects.
class AuthRedirectDelegate: NSObject, URLSessionTaskDelegate {
    var authHeader: String?

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectRequest = request
        if let auth = authHeader {
            redirectRequest.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        // Preserve the original HTTP method and body
        if let originalRequest = task.originalRequest {
            redirectRequest.httpMethod = originalRequest.httpMethod
            redirectRequest.httpBody = originalRequest.httpBody
            // Preserve content-type and depth headers
            if let contentType = originalRequest.value(forHTTPHeaderField: "Content-Type") {
                redirectRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            if let depth = originalRequest.value(forHTTPHeaderField: "Depth") {
                redirectRequest.setValue(depth, forHTTPHeaderField: "Depth")
            }
        }
        completionHandler(redirectRequest)
    }
}
