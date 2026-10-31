import Foundation

// MARK: - CalDAV Discovery Models

/// Represents a discovered CalDAV calendar
struct CalDAVCalendar: Identifiable, Codable {
    var id: String { href }
    let href: String
    let displayName: String
    let color: String?
}

// MARK: - iCalendar VEVENT Parser

/// Parses iCalendar (.ics) data into CalendarEvent objects
struct ICalendarParser {

    /// Parses raw iCalendar text and extracts all VEVENTs as CalendarEvent objects,
    /// expanding RRULE recurrences within the given date range.
    static func parseEvents(from icsData: String, rangeStart: Date, rangeEnd: Date) -> [CalendarEvent] {
        let lines = unfoldLines(icsData)
        var eventBlocks: [[String]] = []
        var currentEventLines: [String]?

        for line in lines {
            if line == "BEGIN:VEVENT" {
                currentEventLines = []
            } else if line == "END:VEVENT" {
                if let eventLines = currentEventLines {
                    eventBlocks.append(eventLines)
                }
                currentEventLines = nil
            } else if currentEventLines != nil {
                currentEventLines?.append(line)
            }
        }

        // Separate override instances (those with RECURRENCE-ID) from base events
        var baseBlock: [String]?
        var overrideBlocks: [[String]] = []
        for block in eventBlocks {
            let hasRecurrenceId = block.contains { line in
                let (name, _, _) = parseProperty(line)
                return name == "RECURRENCE-ID"
            }
            if hasRecurrenceId {
                overrideBlocks.append(block)
            } else {
                // Use the last base event block (there should only be one)
                baseBlock = block
            }
        }

        guard let base = baseBlock else { return [] }
        guard let parsed = parseVEvent(base) else { return [] }

        let events = expandRecurrence(
            event: parsed.event,
            rrule: parsed.rrule,
            exdates: parsed.exdates,
            overrideBlocks: overrideBlocks,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )

        return events
    }

    /// Result of parsing a VEVENT block — includes recurrence info
    private struct ParsedVEvent {
        let event: CalendarEvent
        let rrule: String?
        let exdates: [Date]
        let duration: TimeInterval
    }

    /// Parses a single VEVENT block into a CalendarEvent plus recurrence metadata
    private static func parseVEvent(_ lines: [String]) -> ParsedVEvent? {
        var uid: String?
        var summary: String?
        var location: String?
        var description: String?
        var dtstart: String?
        var dtend: String?
        var dtstartParams: String?
        var dtendParams: String?
        var rrule: String?
        var exdates: [Date] = []
        var organizer: String?
        var attendees: [EventAttendee] = []
        var eventStatus: EventStatus = .unknown
        var conferenceURL: String?

        for line in lines {
            let (name, params, value) = parseProperty(line)

            switch name {
            case "UID":
                uid = value
            case "SUMMARY":
                summary = unescapeICalText(value)
            case "LOCATION":
                location = unescapeICalText(value)
            case "DESCRIPTION":
                description = unescapeICalText(value)
            case "DTSTART":
                dtstart = value
                dtstartParams = params
            case "DTEND":
                dtend = value
                dtendParams = params
            case "RRULE":
                rrule = value
            case "EXDATE":
                // EXDATE can contain multiple dates separated by commas
                for dateStr in value.split(separator: ",") {
                    if let parsed = parseICalDate(String(dateStr).trimmingCharacters(in: .whitespaces), params: params) {
                        exdates.append(parsed.date)
                    }
                }
            case "ORGANIZER":
                // ORGANIZER;CN=John Smith:mailto:john@example.com
                let cn = extractParam("CN", from: params)
                let email = value.replacingOccurrences(of: "mailto:", with: "")
                organizer = cn ?? email
            case "ATTENDEE":
                // ATTENDEE;CN=Jane;PARTSTAT=ACCEPTED;ROLE=REQ-PARTICIPANT:mailto:jane@example.com
                let cn = extractParam("CN", from: params)
                let email = value.replacingOccurrences(of: "mailto:", with: "")
                let partstat = extractParam("PARTSTAT", from: params) ?? "NEEDS-ACTION"
                let attStatus: AttendeeStatus
                switch partstat.uppercased() {
                case "ACCEPTED": attStatus = .accepted
                case "DECLINED": attStatus = .declined
                case "TENTATIVE": attStatus = .tentative
                case "NEEDS-ACTION": attStatus = .needsAction
                default: attStatus = .unknown
                }
                attendees.append(EventAttendee(
                    name: cn,
                    email: email,
                    status: attStatus,
                    isSelf: false, // iCloud doesn't mark self in VEVENT; we could match by email later
                    isOrganizer: false
                ))
            case "STATUS":
                switch value.uppercased() {
                case "CONFIRMED": eventStatus = .confirmed
                case "TENTATIVE": eventStatus = .tentative
                case "CANCELLED": eventStatus = .cancelled
                default: eventStatus = .unknown
                }
            case "URL":
                conferenceURL = value
            case "CONFERENCE":
                // CONFERENCE property (newer RFC) takes priority over URL
                conferenceURL = value
            default:
                break
            }
        }

        guard let eventUid = uid, let startValue = dtstart else { return nil }

        guard let startResult = parseICalDate(startValue, params: dtstartParams) else { return nil }

        let endResult: (date: Date, isAllDay: Bool)?
        if let endValue = dtend {
            endResult = parseICalDate(endValue, params: dtendParams)
        } else {
            endResult = nil
        }

        var endDate = endResult?.date ?? startResult.date

        // RFC 5545: DTEND for VALUE=DATE is exclusive (the day after the last day).
        // Adjust so the end date falls on the actual last day of the event.
        if startResult.isAllDay, let endRes = endResult, endRes.isAllDay, endDate > startResult.date {
            let cal = Calendar.current
            if let adjusted = cal.date(byAdding: .day, value: -1, to: endDate) {
                endDate = adjusted
            }
        }

        let duration = endDate.timeIntervalSince(startResult.date)

        // Mark organizer in attendees list
        let organizerEmail = organizer?.contains("@") == true ? organizer : nil
        let enrichedAttendees = attendees.map { att -> EventAttendee in
            let isOrg = (organizerEmail != nil && att.email == organizerEmail)
            return EventAttendee(
                name: att.name, email: att.email, status: att.status,
                isSelf: att.isSelf, isOrganizer: isOrg
            )
        }

        let event = CalendarEvent(
            id: "icloud-\(eventUid)",
            summary: summary ?? "Untitled Event",
            startTime: startResult.date,
            endTime: endDate,
            isAllDay: startResult.isAllDay,
            location: location,
            description: description,
            source: .icloud,
            organizer: organizer,
            attendees: enrichedAttendees,
            status: eventStatus,
            conferenceURL: conferenceURL,
            calendarName: nil
        )

        return ParsedVEvent(event: event, rrule: rrule, exdates: exdates, duration: duration)
    }

    /// Extracts a parameter value from an iCalendar params string
    /// e.g. extractParam("CN", from: "CN=John Smith;PARTSTAT=ACCEPTED") -> "John Smith"
    private static func extractParam(_ key: String, from params: String?) -> String? {
        guard let params = params else { return nil }
        for param in params.split(separator: ";") {
            let pair = param.split(separator: "=", maxSplits: 1)
            if pair.count == 2, String(pair[0]).uppercased() == key.uppercased() {
                // Remove surrounding quotes if present
                var val = String(pair[1])
                if val.hasPrefix("\"") && val.hasSuffix("\"") {
                    val = String(val.dropFirst().dropLast())
                }
                return val
            }
        }
        return nil
    }

    // MARK: - RRULE Expansion

    /// Expands a recurring event into individual instances within the given date range
    private static func expandRecurrence(
        event: CalendarEvent,
        rrule: String?,
        exdates: [Date],
        overrideBlocks: [[String]],
        rangeStart: Date,
        rangeEnd: Date
    ) -> [CalendarEvent] {
        guard let rrule = rrule else {
            // Non-recurring event — return as-is if it overlaps the range
            if event.endTime >= rangeStart && event.startTime < rangeEnd {
                return [event]
            }
            return []
        }

        let params = parseRRuleParams(rrule)
        guard let freq = params["FREQ"] else { return [event] }

        let interval = Int(params["INTERVAL"] ?? "1") ?? 1
        let count = params["COUNT"].flatMap { Int($0) }
        let untilDate = params["UNTIL"].flatMap { parseICalDate($0, params: nil)?.date }

        let calendar = Calendar.current
        let duration = event.endTime.timeIntervalSince(event.startTime)
        let originalStart = event.startTime

        // Build set of excluded dates (normalized to start-of-day for comparison)
        let exdateSet = Set(exdates.map { calendar.startOfDay(for: $0) })

        // Build map of override instances keyed by their RECURRENCE-ID (start-of-day)
        var overridesByDate: [Date: CalendarEvent] = [:]
        for block in overrideBlocks {
            if let parsed = parseVEvent(block) {
                // Find the RECURRENCE-ID to know which instance this overrides
                for line in block {
                    let (name, params, value) = parseProperty(line)
                    if name == "RECURRENCE-ID" {
                        if let recDate = parseICalDate(value, params: params) {
                            let key = calendar.startOfDay(for: recDate.date)
                            overridesByDate[key] = parsed.event
                        }
                        break
                    }
                }
            }
        }

        var instances: [CalendarEvent] = []
        var instanceCount = 0
        let maxInstances = 500 // Safety limit
        var currentStart = originalStart

        while currentStart < rangeEnd && instanceCount < maxInstances {
            // Check UNTIL limit
            if let until = untilDate, currentStart > until { break }
            // Check COUNT limit
            if let maxCount = count, instanceCount >= maxCount { break }

            let currentEnd = currentStart.addingTimeInterval(duration)
            let currentDayKey = calendar.startOfDay(for: currentStart)

            // Only include if the instance overlaps our query range
            if currentEnd >= rangeStart && currentStart < rangeEnd {
                // Check if this date is excluded
                if !exdateSet.contains(currentDayKey) {
                    // Check if there's an override for this instance
                    if let override = overridesByDate[currentDayKey] {
                        instances.append(override)
                    } else {
                        let instance = CalendarEvent(
                            id: "\(event.id)-\(instanceCount)",
                            summary: event.summary,
                            startTime: currentStart,
                            endTime: currentEnd,
                            isAllDay: event.isAllDay,
                            location: event.location,
                            description: event.description,
                            source: .icloud,
                            organizer: event.organizer,
                            attendees: event.attendees,
                            status: event.status,
                            conferenceURL: event.conferenceURL,
                            calendarName: event.calendarName
                        )
                        instances.append(instance)
                    }
                }
            }

            instanceCount += 1

            // Advance to next occurrence
            guard let next = advanceDate(currentStart, freq: freq, interval: interval, calendar: calendar) else { break }
            currentStart = next
        }

        return instances
    }

    /// Parses RRULE string like "FREQ=WEEKLY;INTERVAL=2;UNTIL=20260301T000000Z" into a dictionary
    private static func parseRRuleParams(_ rrule: String) -> [String: String] {
        var params: [String: String] = [:]
        for part in rrule.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1])
            }
        }
        return params
    }

    /// Advances a date by the given frequency and interval
    private static func advanceDate(_ date: Date, freq: String, interval: Int, calendar: Calendar) -> Date? {
        switch freq {
        case "DAILY":
            return calendar.date(byAdding: .day, value: interval, to: date)
        case "WEEKLY":
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case "MONTHLY":
            return calendar.date(byAdding: .month, value: interval, to: date)
        case "YEARLY":
            return calendar.date(byAdding: .year, value: interval, to: date)
        default:
            return nil
        }
    }

    /// Parses an iCalendar property line into (name, params, value)
    /// e.g. "DTSTART;TZID=America/Phoenix:20260215T140000" -> ("DTSTART", "TZID=America/Phoenix", "20260215T140000")
    private static func parseProperty(_ line: String) -> (name: String, params: String?, value: String) {
        // Find the first colon that separates the property name/params from the value
        // But property params can contain colons in values like TZID=America/New_York
        // The format is NAME;PARAM=VALUE;PARAM=VALUE:PROPERTY_VALUE
        // We need to find the colon that is NOT inside a parameter value

        guard let colonIndex = findValueColon(in: line) else {
            return (line, nil, "")
        }

        let nameAndParams = String(line[line.startIndex..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])

        if let semicolonIndex = nameAndParams.firstIndex(of: ";") {
            let name = String(nameAndParams[nameAndParams.startIndex..<semicolonIndex])
            let params = String(nameAndParams[nameAndParams.index(after: semicolonIndex)...])
            return (name, params, value)
        } else {
            return (nameAndParams, nil, value)
        }
    }

    /// Finds the colon that separates property name/params from the value.
    /// Handles the case where TZID values contain colons (they don't in IANA tz names,
    /// but we handle it safely by finding the first colon after the last semicolon-separated param).
    private static func findValueColon(in line: String) -> String.Index? {
        // Simple approach: find first colon. For iCalendar, the property value starts
        // after the first colon that follows the property name and any parameters.
        // IANA timezone names use "/" not ":", so first colon is safe.
        return line.firstIndex(of: ":")
    }

    /// Parses iCalendar date/datetime values
    /// Formats: "20260215" (date), "20260215T140000Z" (UTC), "20260215T140000" (local/TZID)
    private static func parseICalDate(_ value: String, params: String?) -> (date: Date, isAllDay: Bool)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Check if this is a DATE (all-day) value
        let isAllDay = params?.contains("VALUE=DATE") == true || (!trimmed.contains("T") && trimmed.count == 8)

        if isAllDay {
            // All-day: "20260215"
            return parseAllDayDate(trimmed)
        }

        // Extract TZID if present
        var tzid: String?
        if let params = params {
            for param in params.split(separator: ";") {
                let paramStr = String(param)
                if paramStr.hasPrefix("TZID=") {
                    tzid = String(paramStr.dropFirst(5))
                }
            }
        }

        // DateTime: "20260215T140000Z" or "20260215T140000"
        return parseDateTimeValue(trimmed, tzid: tzid)
    }

    /// Parses an all-day date "20260215" into a Date at noon local time
    private static func parseAllDayDate(_ value: String) -> (date: Date, isAllDay: Bool)? {
        guard value.count >= 8 else { return nil }

        let yearStr = String(value.prefix(4))
        let monthStr = String(value.dropFirst(4).prefix(2))
        let dayStr = String(value.dropFirst(6).prefix(2))

        guard let year = Int(yearStr), let month = Int(monthStr), let day = Int(dayStr) else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12 // Noon to avoid timezone edge cases
        components.minute = 0

        guard let date = calendar.date(from: components) else { return nil }
        return (date, true)
    }

    /// Parses a datetime value "20260215T140000Z" or "20260215T140000"
    private static func parseDateTimeValue(_ value: String, tzid: String?) -> (date: Date, isAllDay: Bool)? {
        // Remove any trailing Z to detect UTC
        let isUTC = value.hasSuffix("Z")
        let cleaned = isUTC ? String(value.dropLast()) : value

        // Expected format: "20260215T140000"
        guard cleaned.count >= 15, cleaned.contains("T") else { return nil }

        let parts = cleaned.split(separator: "T")
        guard parts.count == 2 else { return nil }

        let dateStr = String(parts[0])
        let timeStr = String(parts[1])

        guard dateStr.count >= 8, timeStr.count >= 6 else { return nil }

        guard let year = Int(dateStr.prefix(4)),
              let month = Int(dateStr.dropFirst(4).prefix(2)),
              let day = Int(dateStr.dropFirst(6).prefix(2)),
              let hour = Int(timeStr.prefix(2)),
              let minute = Int(timeStr.dropFirst(2).prefix(2)),
              let second = Int(timeStr.dropFirst(4).prefix(2)) else { return nil }

        var calendar = Calendar.current
        let timeZone: TimeZone
        if isUTC {
            timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = tzid, let tz = TimeZone(identifier: tzid) {
            timeZone = tz
        } else {
            timeZone = TimeZone.current
        }
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        guard let date = calendar.date(from: components) else { return nil }
        return (date, false)
    }

    /// Unfolds iCalendar long lines (lines starting with space or tab are continuations)
    private static func unfoldLines(_ raw: String) -> [String] {
        var result: [String] = []
        let rawLines = raw.components(separatedBy: .newlines)

        for line in rawLines {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Continuation line - append to previous
                if !result.isEmpty {
                    result[result.count - 1] += String(line.dropFirst())
                }
            } else {
                result.append(line)
            }
        }

        return result
    }

    /// Unescapes iCalendar text values
    private static func unescapeICalText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\N", with: "\n")
        result = result.replacingOccurrences(of: "\\,", with: ",")
        result = result.replacingOccurrences(of: "\\;", with: ";")
        result = result.replacingOccurrences(of: "\\\\", with: "\\")
        return result
    }
}

// MARK: - CalDAV XML Parsers

/// Parses PROPFIND response to extract the current-user-principal or calendar-home-set URL
class CalendarHomePropfindParser: NSObject, XMLParserDelegate {
    private var currentText = ""
    private var foundHref: String?
    private var insideTarget = false
    private var insideHref = false

    private let targetElement: String

    /// Initialize with target element name to find href within
    /// - Parameter target: "current-user-principal" or "calendar-home-set"
    init(target: String) {
        self.targetElement = target
    }

    func parse(data: Data) -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return foundHref
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == targetElement {
            insideTarget = true
        } else if localName == "href" && insideTarget {
            insideHref = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideHref {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == "href" && insideHref {
            insideHref = false
            if insideTarget {
                foundHref = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if localName == targetElement {
            insideTarget = false
        }
    }
}

/// Parses PROPFIND response (Depth:1) to extract calendar collection URLs
class CalendarListParser: NSObject, XMLParserDelegate {
    private var calendars: [CalDAVCalendar] = []

    // Current response tracking
    private var currentHref: String?
    private var currentDisplayName: String?
    private var currentColor: String?
    private var isCalendar = false

    // Element tracking
    private var currentText = ""
    private var insideResponse = false
    private var insideHref = false
    private var insideDisplayName = false
    private var insideCalendarColor = false
    private var insideResourceType = false
    private var responseDepth = 0

    func parse(data: Data) -> [CalDAVCalendar] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return calendars
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "response":
            insideResponse = true
            responseDepth += 1
            currentHref = nil
            currentDisplayName = nil
            currentColor = nil
            isCalendar = false
        case "href":
            if insideResponse && responseDepth == 1 && currentHref == nil {
                insideHref = true
                currentText = ""
            }
        case "displayname":
            insideDisplayName = true
            currentText = ""
        case "calendar-color":
            insideCalendarColor = true
            currentText = ""
        case "resourcetype":
            insideResourceType = true
        case "calendar":
            if insideResourceType {
                isCalendar = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideHref || insideDisplayName || insideCalendarColor {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "response":
            if isCalendar, let href = currentHref {
                let name = currentDisplayName ?? "Untitled Calendar"
                calendars.append(CalDAVCalendar(
                    href: href,
                    displayName: name,
                    color: currentColor?.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            insideResponse = false
            responseDepth -= 1
        case "href":
            if insideHref {
                currentHref = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                insideHref = false
            }
        case "displayname":
            if insideDisplayName {
                currentDisplayName = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                insideDisplayName = false
            }
        case "calendar-color":
            if insideCalendarColor {
                currentColor = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                insideCalendarColor = false
            }
        case "resourcetype":
            insideResourceType = false
        default:
            break
        }
    }
}

/// Parses REPORT (calendar-query) response to extract calendar-data (raw iCalendar text)
class CalendarDataParser: NSObject, XMLParserDelegate {
    private var calendarDataBlocks: [String] = []
    private var currentText = ""
    private var insideCalendarData = false

    func parse(data: Data) -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return calendarDataBlocks
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == "calendar-data" {
            insideCalendarData = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideCalendarData {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == "calendar-data" {
            insideCalendarData = false
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                calendarDataBlocks.append(trimmed)
            }
        }
    }
}
