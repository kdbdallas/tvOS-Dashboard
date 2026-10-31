import Foundation

/// Identifies which calendar provider an event came from
enum CalendarSource: String, Codable {
    case google
    case icloud
}

/// Represents an attendee of a calendar event
struct EventAttendee: Codable, Equatable {
    let name: String?
    let email: String
    let status: AttendeeStatus
    let isSelf: Bool
    let isOrganizer: Bool
}

/// RSVP status for an attendee
enum AttendeeStatus: String, Codable {
    case accepted
    case declined
    case tentative
    case needsAction
    case unknown

    var displayLabel: String {
        switch self {
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .tentative: return "Maybe"
        case .needsAction: return "No Response"
        case .unknown: return "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .needsAction: return "minus.circle"
        case .unknown: return "minus.circle"
        }
    }

    var color: String {
        switch self {
        case .accepted: return "green"
        case .declined: return "red"
        case .tentative: return "yellow"
        case .needsAction: return "gray"
        case .unknown: return "gray"
        }
    }
}

/// Status of the overall event
enum EventStatus: String, Codable {
    case confirmed
    case tentative
    case cancelled
    case unknown
}

/// Represents a calendar event from any calendar source
struct CalendarEvent: Identifiable, Codable, Equatable {
    let id: String
    let summary: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let location: String?
    let description: String?
    let source: CalendarSource
    let organizer: String?
    let attendees: [EventAttendee]
    let status: EventStatus
    let conferenceURL: String?
    let calendarName: String?

    /// My RSVP status (from the attendee marked as self)
    var myStatus: AttendeeStatus? {
        attendees.first(where: { $0.isSelf })?.status
    }

    var formattedTime: String {
        if isAllDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = isAllDay ? .none : .short

        let start = formatter.string(from: startTime)
        let end = formatter.string(from: endTime)

        if isAllDay {
            return start
        }
        return "\(start) - \(end)"
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(startTime)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(startTime)
    }

    var relativeDayString: String {
        if isToday {
            return "Today"
        } else if isTomorrow {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: startTime)
        }
    }
}

// MARK: - Google Calendar API Response Models

struct GoogleCalendarListResponse: Codable {
    let items: [GoogleCalendarEvent]?
    let nextPageToken: String?
}

struct GoogleCalendarEvent: Codable {
    let id: String
    let summary: String?
    let start: GoogleDateTime
    let end: GoogleDateTime
    let location: String?
    let description: String?
    let eventType: String? // "default", "workingLocation", "outOfOffice", "focusTime"
    let organizer: GoogleOrganizer?
    let attendees: [GoogleAttendee]?
    let status: String? // "confirmed", "tentative", "cancelled"
    let conferenceData: GoogleConferenceData?
    let hangoutLink: String?

    /// Returns true if this is a working location event (not a real calendar event)
    var isWorkingLocation: Bool {
        eventType == "workingLocation"
    }

    /// Returns true if this should be displayed as a regular calendar event
    var isDisplayableEvent: Bool {
        // Only filter out specific non-event types; everything else is displayable
        guard let type = eventType else { return true }
        let hiddenTypes: Set<String> = ["workingLocation", "outOfOffice", "focusTime"]
        return !hiddenTypes.contains(type)
    }

    func toCalendarEvent() -> CalendarEvent {
        let isAllDay = start.date != nil

        let startDate: Date
        let endDate: Date

        if let dateString = start.date {
            // All-day event - create a date at noon local time to avoid timezone boundary issues
            // This ensures the event stays on the correct day regardless of timezone
            var calendar = Calendar.current
            calendar.timeZone = TimeZone.current

            let components = dateString.split(separator: "-")
            if components.count == 3,
               let year = Int(components[0]),
               let month = Int(components[1]),
               let day = Int(components[2]) {
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = day
                dateComponents.hour = 12 // Noon to avoid timezone edge cases
                dateComponents.minute = 0
                startDate = calendar.date(from: dateComponents) ?? Date()

                // Parse end date similarly
                // Google API uses exclusive end dates for all-day events (same as RFC 5545),
                // so subtract 1 day to get the actual last day of the event.
                if let endDateString = end.date {
                    let endComponents = endDateString.split(separator: "-")
                    if endComponents.count == 3,
                       let endYear = Int(endComponents[0]),
                       let endMonth = Int(endComponents[1]),
                       let endDay = Int(endComponents[2]) {
                        var endDateComps = DateComponents()
                        endDateComps.year = endYear
                        endDateComps.month = endMonth
                        endDateComps.day = endDay
                        endDateComps.hour = 12
                        endDateComps.minute = 0
                        let rawEnd = calendar.date(from: endDateComps) ?? startDate
                        // Subtract 1 day: exclusive end → inclusive last day
                        if rawEnd > startDate, let adjusted = calendar.date(byAdding: .day, value: -1, to: rawEnd) {
                            endDate = adjusted
                        } else {
                            endDate = startDate
                        }
                    } else {
                        endDate = startDate
                    }
                } else {
                    endDate = startDate
                }
            } else {
                startDate = Date()
                endDate = Date()
            }
        } else if let dateTimeString = start.dateTime {
            // Timed event - try multiple ISO8601 formats
            let startParsed = Self.parseISO8601Date(dateTimeString)
            let endParsed = Self.parseISO8601Date(end.dateTime ?? dateTimeString)
            startDate = startParsed ?? Date()
            endDate = endParsed ?? startDate
        } else {
            startDate = Date()
            endDate = Date()
        }

        // Parse attendees
        let parsedAttendees: [EventAttendee] = (attendees ?? []).map { att in
            let attStatus: AttendeeStatus
            switch att.responseStatus {
            case "accepted": attStatus = .accepted
            case "declined": attStatus = .declined
            case "tentative": attStatus = .tentative
            case "needsAction": attStatus = .needsAction
            default: attStatus = .unknown
            }
            return EventAttendee(
                name: att.displayName,
                email: att.email ?? "",
                status: attStatus,
                isSelf: att.isSelf ?? false,
                isOrganizer: att.organizer ?? false
            )
        }

        // Parse event status
        let eventStatus: EventStatus
        switch status {
        case "confirmed": eventStatus = .confirmed
        case "tentative": eventStatus = .tentative
        case "cancelled": eventStatus = .cancelled
        default: eventStatus = .unknown
        }

        // Get conference URL: prefer conferenceData entry points, fall back to hangoutLink
        let confURL: String? = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
            ?? hangoutLink

        // Organizer name
        let organizerName = organizer?.displayName ?? organizer?.email

        return CalendarEvent(
            id: id,
            summary: summary ?? "Untitled Event",
            startTime: startDate,
            endTime: endDate,
            isAllDay: isAllDay,
            location: location,
            description: description,
            source: .google,
            organizer: organizerName,
            attendees: parsedAttendees,
            status: eventStatus,
            conferenceURL: confURL,
            calendarName: nil
        )
    }

    /// Parse ISO8601 date string with multiple format attempts
    private static func parseISO8601Date(_ dateString: String) -> Date? {
        // Try with fractional seconds first
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: dateString) {
            return date
        }

        // Try without fractional seconds
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        if let date = formatterWithoutFractional.date(from: dateString) {
            return date
        }

        // Try basic DateFormatter as fallback
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter.date(from: dateString)
    }
}

struct GoogleDateTime: Codable {
    let date: String?      // For all-day events (yyyy-MM-dd)
    let dateTime: String?  // For timed events (ISO8601)
    let timeZone: String?
}

struct GoogleOrganizer: Codable {
    let email: String?
    let displayName: String?
    let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case isSelf = "self"
    }
}

struct GoogleAttendee: Codable {
    let email: String?
    let displayName: String?
    let responseStatus: String?  // "accepted", "declined", "tentative", "needsAction"
    let isSelf: Bool?
    let organizer: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case responseStatus
        case isSelf = "self"
        case organizer
    }
}

struct GoogleConferenceData: Codable {
    let entryPoints: [GoogleEntryPoint]?
    let conferenceSolution: GoogleConferenceSolution?
}

struct GoogleEntryPoint: Codable {
    let entryPointType: String?  // "video", "phone", "sip", "more"
    let uri: String?
    let label: String?
}

struct GoogleConferenceSolution: Codable {
    let name: String?   // e.g. "Google Meet", "Zoom Meeting"
    let iconUri: String?
}

// MARK: - OAuth Device Flow Models

struct DeviceCodeResponse: Codable {
    let deviceCode: String
    let userCode: String
    let verificationUrl: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUrl = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct TokenErrorResponse: Codable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Calendar Grid Models

/// Represents a single day cell in the monthly calendar grid
struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}
