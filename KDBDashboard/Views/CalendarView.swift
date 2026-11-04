import MapKit
import SwiftUI

/// Displays merged calendar events from Google and iCloud with authorization flows
struct CalendarView: View {
    @ObservedObject var calendarManager: CalendarManager
    @Binding var showingSettings: Bool
    var isOnboarding: Bool = false
    var onOnboardingComplete: (() -> Void)? = nil

    // MARK: - Focus Management

    enum CalendarFocus: Hashable {
        case calendar
        case eventPanel
        case eventHUD
        case eventHUDFirstButton
    }

    @FocusState private var focusedSection: CalendarFocus?

    // MARK: - State Properties for Monthly View

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var showingEventDetail: Bool = false
    @State private var showingGoogleAuth: Bool = false
    @State private var showingICloudAuth: Bool = false
    @State private var selectedEvent: CalendarEvent? = nil

    // MARK: - Upcoming Event Banner State

    /// The event currently shown in the upcoming banner (nil = no banner)
    @State private var upcomingBannerEvent: CalendarEvent? = nil
    /// Minutes remaining until the upcoming event starts (0 or negative = "Now")
    @State private var upcomingMinutesRemaining: Int = 0
    /// Whether the event has reached "Now" status (start time passed)
    @State private var upcomingIsNow: Bool = false
    /// Timestamp when the event transitioned to "Now", used to dismiss after 3 min
    @State private var upcomingNowSince: Date? = nil

    /// Whether any full-screen overlay is showing (auth)
    private var isOverlayShowing: Bool {
        showingICloudAuth
        || calendarManager.googleService.isWaitingForAuthorization
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.15, green: 0.15, blue: 0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            Group {
                if calendarManager.isLoading && calendarManager.events.isEmpty && (calendarManager.needsSetup || isOnboarding) {
                    loadingView
                } else if calendarManager.needsSetup || isOnboarding {
                    calendarSetupView
                } else {
                    monthlyCalendarView
                }
            }
            .disabled(isOverlayShowing)

            // Google device-code auth overlay
            if calendarManager.googleService.isWaitingForAuthorization,
               let deviceCode = calendarManager.googleService.deviceCode {
                Color(.sRGB, red: 0.08, green: 0.08, blue: 0.12, opacity: 1.0)
                    .ignoresSafeArea()
                GoogleSignInView(googleService: calendarManager.googleService, deviceCode: deviceCode)
            }

            // iCloud sign-in overlay
            if showingICloudAuth {
                Color(.sRGB, red: 0.08, green: 0.08, blue: 0.12, opacity: 1.0)
                    .ignoresSafeArea()
                ICloudSignInView(
                    icloudService: calendarManager.icloudService,
                    onDismiss: { showingICloudAuth = false }
                )
            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Computed Properties for Calendar Grid

    /// First day of the currently displayed month
    private var firstDayOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return calendar.date(from: components)!
    }

    /// Number of rows needed for the current month
    private var numberOfRows: Int {
        let calendar = Calendar.current
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1
        let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth)!
        let daysInMonth = range.count
        let totalCells = firstWeekday + daysInMonth
        return (totalCells + 6) / 7 // Ceiling division
    }

    /// All days to display in the calendar grid (only current month with minimal padding)
    private var calendarDays: [CalendarDay] {
        let calendar = Calendar.current

        // Find the weekday of the first day (1 = Sunday in Gregorian)
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1

        // Get the number of days in the month
        let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth)!
        let daysInMonth = range.count

        var days: [CalendarDay] = []

        // Empty placeholder cells for days before the 1st (no previous month days shown)
        for _ in 0..<firstWeekday {
            // Add empty placeholder - we'll handle this in the view
            days.append(CalendarDay(date: Date.distantPast, dayNumber: 0, isCurrentMonth: false))
        }

        // Current month days
        for day in 1...daysInMonth {
            let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth)!
            days.append(CalendarDay(date: date, dayNumber: day, isCurrentMonth: true))
        }

        // Fill remaining cells in the last row with empty placeholders
        let totalCells = numberOfRows * 7
        let remainingCells = totalCells - days.count
        for _ in 0..<remainingCells {
            days.append(CalendarDay(date: Date.distantPast, dayNumber: 0, isCurrentMonth: false))
        }

        return days
    }

    /// Events grouped by date for quick lookup.
    /// Multi-day events appear on every day they span.
    private var eventsByDate: [Date: [CalendarEvent]] {
        let calendar = Calendar.current
        var grouped: [Date: [CalendarEvent]] = [:]

        for event in calendarManager.events {
            let eventStartDay = calendar.startOfDay(for: event.startTime)
            let eventEndDay = calendar.startOfDay(for: event.endTime)

            // If event spans multiple days, add it to each day
            if eventStartDay < eventEndDay {
                var currentDay = eventStartDay
                while currentDay <= eventEndDay {
                    if grouped[currentDay] == nil {
                        grouped[currentDay] = []
                    }
                    grouped[currentDay]?.append(event)

                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
                    currentDay = nextDay
                }
            } else {
                // Single-day event
                if grouped[eventStartDay] == nil {
                    grouped[eventStartDay] = []
                }
                grouped[eventStartDay]?.append(event)
            }
        }

        return grouped
    }

    /// Events for the currently selected date
    private var selectedDateEvents: [CalendarEvent] {
        guard let selected = selectedDate else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selected)
        return (eventsByDate[dayStart] ?? []).sorted { $0.startTime < $1.startTime }
    }

    /// Month/year display string
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    // MARK: - Upcoming Event Logic

    /// Finds the nearest timed event today that starts within 30 minutes from now
    private func findUpcomingEvent() -> CalendarEvent? {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let todayEvents = eventsByDate[todayStart] ?? []

        // Find timed events starting within the next 30 minutes (or just started)
        let thirtyMinutesFromNow = now.addingTimeInterval(30 * 60)

        let candidates = todayEvents.filter { event in
            guard !event.isAllDay else { return false }
            // Event starts between now and 30 min from now
            return event.startTime > now && event.startTime <= thirtyMinutesFromNow
        }

        // Return the soonest one
        return candidates.min(by: { $0.startTime < $1.startTime })
    }

    /// Updates the upcoming banner state: finds events, calculates minutes, handles "Now" and dismissal
    private func refreshUpcomingBanner(eventsChanged: Bool = false) {
        let now = Date()

        // If we're currently showing "Now", check if 3 minutes have passed
        if upcomingIsNow, let nowSince = upcomingNowSince {
            if now.timeIntervalSince(nowSince) >= 3 * 60 {
                // Dismiss the banner
                withAnimation(.easeInOut(duration: 0.3)) {
                    upcomingBannerEvent = nil
                    upcomingIsNow = false
                    upcomingNowSince = nil
                }
                return
            }
            // Still in "Now" state — but if events changed, verify the event still exists unchanged
            if eventsChanged, let bannerEvent = upcomingBannerEvent {
                let stillValid = calendarManager.events.contains {
                    $0.id == bannerEvent.id && $0.startTime == bannerEvent.startTime
                }
                if !stillValid {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        upcomingBannerEvent = nil
                        upcomingIsNow = false
                        upcomingNowSince = nil
                    }
                }
            }
            return
        }

        // If we have a banner event, verify it still exists with the same start time after a refresh
        if let bannerEvent = upcomingBannerEvent, eventsChanged {
            let stillValid = calendarManager.events.contains {
                $0.id == bannerEvent.id && $0.startTime == bannerEvent.startTime
            }
            if !stillValid {
                withAnimation(.easeInOut(duration: 0.3)) {
                    upcomingBannerEvent = nil
                    upcomingIsNow = false
                    upcomingNowSince = nil
                }
                // After clearing, check if there's a new upcoming event to show
                if let event = findUpcomingEvent() {
                    let remaining = Int(ceil(event.startTime.timeIntervalSince(now) / 60))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        upcomingBannerEvent = event
                        upcomingMinutesRemaining = max(remaining, 1)
                        upcomingIsNow = false
                        upcomingNowSince = nil
                    }
                }
                return
            }
        }

        // If we have a banner event, update its countdown
        if let event = upcomingBannerEvent {
            let remaining = Int(ceil(event.startTime.timeIntervalSince(now) / 60))
            if remaining <= 0 {
                // Transition to "Now"
                withAnimation(.easeInOut(duration: 0.3)) {
                    upcomingMinutesRemaining = 0
                    upcomingIsNow = true
                    upcomingNowSince = now
                }
            } else {
                upcomingMinutesRemaining = remaining
            }
            return
        }

        // No current banner event — look for one
        if let event = findUpcomingEvent() {
            let remaining = Int(ceil(event.startTime.timeIntervalSince(now) / 60))
            withAnimation(.easeInOut(duration: 0.3)) {
                upcomingBannerEvent = event
                upcomingMinutesRemaining = max(remaining, 1)
                upcomingIsNow = false
                upcomingNowSince = nil
            }
        }
    }

    /// The text to display in the upcoming event banner
    private var upcomingBannerText: String? {
        guard let event = upcomingBannerEvent else { return nil }
        if upcomingIsNow {
            return "Upcoming: \(event.summary) — Now"
        } else {
            let min = upcomingMinutesRemaining
            return "Upcoming: \(event.summary) in \(min) minute\(min == 1 ? "" : "s")"
        }
    }

    // MARK: - Upcoming Event Banner View

    private var upcomingBannerView: some View {
        Group {
            if let text = upcomingBannerText {
                Text(text)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .focusable(false)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Calendar Setup View (no sources connected)

    private var calendarSetupView: some View {
        VStack(spacing: 30) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 70))
                .foregroundColor(.white.opacity(0.7))

            Text(isOnboarding ? "Connect Your Calendar(s)" : "Connect a Calendar")
                .font(.title)
                .foregroundColor(.white)

            Text(isOnboarding ? "Connect at least one calendar source" : "Sign in to view your upcoming events")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))

            if let error = calendarManager.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 25) {
                // Google Calendar
                Button {
                    Task {
                        await calendarManager.googleService.startDeviceAuthorization()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image("GoogleG40")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                        Text(calendarManager.googleService.isAuthenticated ? "Google Calendar Connected" : "Sign In with Google")
                            .foregroundColor(.white)
                        if calendarManager.googleService.isAuthenticated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.headline)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.card)
                .disabled(calendarManager.googleService.isAuthenticated)

                // iCloud Calendar
                Button {
                    showingICloudAuth = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                        Text(calendarManager.icloudService.isAuthenticated ? "iCloud Calendar Connected" : "Sign In with iCloud")
                            .foregroundColor(.white)
                        if calendarManager.icloudService.isAuthenticated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.headline)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.card)
                .disabled(calendarManager.icloudService.isAuthenticated)
            }

            // Next button during onboarding
            if isOnboarding && !calendarManager.needsSetup {
                Button("Next") {
                    onOnboardingComplete?()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 20)
            }
        }
        .padding(40)
    }

    // MARK: - Monthly Calendar View

    private var monthlyCalendarView: some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = 80
            let bannerHeight: CGFloat = upcomingBannerEvent != nil ? 46 : 0
            let weekdayHeight: CGFloat = 40
            let maxDetailPanelHeight: CGFloat = geometry.size.height * 0.75
            let gridPadding: CGFloat = 40 // top and bottom padding for grid
            let availableGridHeight = geometry.size.height - headerHeight - bannerHeight - weekdayHeight - gridPadding
            let rowHeight = availableGridHeight / CGFloat(numberOfRows)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Header with month/year and navigation
                    calendarHeaderView
                        .frame(height: headerHeight)

                    Divider()
                        .background(Color.white.opacity(0.2))

                    // Upcoming event banner (above weekday labels)
                    upcomingBannerView
                        .frame(height: bannerHeight)
                        .clipped()

                    // Weekday labels
                    weekdayHeaderRow
                        .frame(height: weekdayHeight)

                    // Calendar grid - fills remaining space
                    calendarGridView(rowHeight: rowHeight)
                        .padding(.bottom, 15)
                        .focused($focusedSection, equals: .calendar)
                }
                .disabled(showingEventDetail)
                .opacity(showingEventDetail ? 0.5 : 1.0)

                // Event detail panel (overlay from bottom when a day is selected)
                if showingEventDetail && selectedDate != nil {
                    eventDetailPanel(maxHeight: maxDetailPanelHeight)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 15)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .focused($focusedSection, equals: .eventPanel)
                }

                // Event detail HUD overlay
                if let event = selectedEvent {
                    eventDetailHUD(event: event, geometry: geometry)
                }
            }
            .onChange(of: showingEventDetail) { _, newValue in
                if newValue {
                    // Move focus into the event panel when it opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedSection = .eventPanel
                    }
                } else {
                    focusedSection = .calendar
                }
            }
            .onChange(of: selectedEvent) { _, newValue in
                if newValue != nil {
                    // Move focus to the first button in the HUD when it opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedSection = .eventHUDFirstButton
                    }
                } else {
                    // Return focus to the event panel when HUD closes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedSection = .eventPanel
                    }
                }
            }
            .onAppear {
                refreshUpcomingBanner()
                // Set initial focus to calendar view
                focusedSection = .calendar
            }
            .onChange(of: calendarManager.events) { _, _ in
                refreshUpcomingBanner(eventsChanged: true)
            }
            .task {
                // Refresh the upcoming banner every 1 minutes
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1 * 60 * 1_000_000_000)
                    refreshUpcomingBanner()
                }
            }
        }
    }

    // MARK: - Calendar Header

    private var calendarHeaderView: some View {
        HStack(spacing: 40) {
            // Previous month button
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // Next month button
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // Month and Year
            Text(monthYearString)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            // Today button
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    displayedMonth = Date()
                    selectedDate = Date()
                    showingEventDetail = true
                }
            } label: {
                Text("Today")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            // Settings button
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // Refresh button
            Button {
                Task {
                    await calendarManager.fetchAllEvents()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .opacity(calendarManager.isLoading ? 0.5 : 1.0)
        }
        .padding(.leading, 40)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
    }

    // MARK: - Weekday Header Row

    private var weekdayHeaderRow: some View {
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        return HStack(spacing: 4) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Calendar Grid

    /// Groups calendar days into weeks (rows of 7)
    private var calendarWeeks: [[CalendarDay]] {
        var weeks: [[CalendarDay]] = []
        var currentWeek: [CalendarDay] = []

        for day in calendarDays {
            currentWeek.append(day)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }

        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }

        return weeks
    }

    private func calendarGridView(rowHeight: CGFloat) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(calendarWeeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(week) { day in
                        DayCellView(
                            day: day,
                            events: eventsByDate[Calendar.current.startOfDay(for: day.date)] ?? [],
                            isSelected: selectedDate != nil && Calendar.current.isDate(day.date, inSameDayAs: selectedDate!)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedDate != nil && Calendar.current.isDate(day.date, inSameDayAs: selectedDate!) {
                                    // Toggle detail view if already selected
                                    showingEventDetail.toggle()
                                    if !showingEventDetail {
                                        selectedDate = nil
                                    }
                                } else {
                                    selectedDate = day.date
                                    showingEventDetail = true
                                }
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Event Detail Panel

    private func eventDetailPanel(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with selected date
            HStack {
                if let selected = selectedDate {
                    Text(selectedDateString(selected))
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()
                .background(Color.white.opacity(0.2))

            if selectedDateEvents.isEmpty {
                // No events message
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.5))
                    Text("No events")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Events list - each event is a focusable button
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedDateEvents) { event in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedEvent = event
                                }
                            } label: {
                                EventRow(event: event)
                            }
                            .buttonStyle(.card)
                            .padding(.horizontal, 15)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Close button — easily reachable at bottom of panel
            Button {
                withAnimation {
                    showingEventDetail = false
                    selectedDate = nil
                }
            } label: {
                Text("Close")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.card)
        }
        .focusSection()
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .background(
            Color(.sRGB, red: 0.08, green: 0.08, blue: 0.12, opacity: 0.95)
        )
        .cornerRadius(15)
        .onExitCommand {
            withAnimation {
                showingEventDetail = false
                selectedDate = nil
            }
        }
    }

    private func selectedDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    // MARK: - Event Detail HUD

    private func attendeeStatusColor(_ status: AttendeeStatus) -> Color {
        switch status {
        case .accepted: return .green
        case .declined: return .red
        case .tentative: return .yellow
        case .needsAction: return .gray
        case .unknown: return .gray
        }
    }

    private func eventDetailHUD(event: CalendarEvent, geometry: GeometryProxy) -> some View {
        let sourceLabel = event.source == .google ? "Google Calendar" : "iCloud Calendar"
        let sourceColor: Color = event.source == .google ? .orange : .blue
        let maxHUDHeight = geometry.size.height * 0.8

        return ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header: title + source badge (fixed at top)
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.summary)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(sourceColor)
                            .frame(width: 8, height: 8)
                        Text(sourceLabel)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 30)
                .padding(.bottom, 16)

                Divider().background(Color.white.opacity(0.3)).padding(.horizontal, 30)

                // Scrollable content area — all focusable items including Done
                // are inside ScrollView so tvOS focus flows naturally through them
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Time
                        Button { } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 24)

                                if event.isAllDay {
                                    Text("All Day")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.9))
                                } else {
                                    Text(event.formattedDateRange)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.9))
                                }

                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, 12)
                        }
                        .buttonStyle(.card)
                        .focused($focusedSection, equals: .eventHUDFirstButton)

                        // Location + Map
                        if let location = event.location, !location.isEmpty {
                            Button { } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "location.fill")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 24)

                                    Text(location)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.9))
                                        .multilineTextAlignment(.leading)

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            .padding(.leading, 12)
                            }
                            .buttonStyle(.card)

                            // Map view with pin at the address
                            EventLocationMapView(address: location)
                                .frame(height: 200)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        }

                        // My RSVP status
                        if let myStatus = event.myStatus {
                            Button { } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 24)

                                    Text("My Status:")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.7))

                                    HStack(spacing: 4) {
                                        Image(systemName: myStatus.iconName)
                                            .font(.caption)
                                            .foregroundColor(attendeeStatusColor(myStatus))
                                        Text(myStatus.displayLabel)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(attendeeStatusColor(myStatus))
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            .padding(.leading, 12)
                            }
                            .buttonStyle(.card)
                        }

                        // Conference / Meeting link
                        if let confURL = event.conferenceURL, !confURL.isEmpty {
                            Button { } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "video.fill")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Meeting Link")
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.9))
                                        Text(confURL)
                                            .font(.caption)
                                            .foregroundColor(.blue.opacity(0.8))
                                            .lineLimit(2)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            .padding(.leading, 12)
                            }
                            .buttonStyle(.card)
                        }

                        // Organizer
                        if let organizer = event.organizer, !organizer.isEmpty {
                            Button { } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "person.fill")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 24)

                                    Text("Organizer: \(organizer)")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.9))

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            .padding(.leading, 12)
                            }
                            .buttonStyle(.card)
                        }

                        // Attendees
                        if !event.attendees.isEmpty {
                            Button { } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "person.2.fill")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Attendees (\(event.attendees.count))")
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.9))

                                        ForEach(Array(event.attendees.enumerated()), id: \.offset) { _, attendee in
                                            HStack(spacing: 6) {
                                                Image(systemName: attendee.status.iconName)
                                                    .font(.caption)
                                                    .foregroundColor(attendeeStatusColor(attendee.status))

                                                Text(attendee.name ?? attendee.email)
                                                    .font(.callout)
                                                    .foregroundColor(.white.opacity(0.8))

                                                if attendee.isOrganizer {
                                                    Text("(organizer)")
                                                        .font(.caption2)
                                                        .foregroundColor(.white.opacity(0.4))
                                                }
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            .padding(.leading, 12)
                            }
                            .buttonStyle(.card)
                        }

                        // Description/notes
                        if let description = event.description, !description.isEmpty {
                            Button { } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 24)

                                    Text(description)
                                        .font(.callout)
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            .padding(.leading, 12)
                            }
                            .buttonStyle(.card)
                        }

                        // Divider before Done
                        Divider().background(Color.white.opacity(0.3))

                        // Dismiss button inside scroll so focus flows here naturally
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedEvent = nil
                            }
                        } label: {
                            Text("Done")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.card)
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: min(geometry.size.width * 0.6, 700), maxHeight: maxHUDHeight)
            .background(
                Color(.sRGB, red: 0.1, green: 0.1, blue: 0.15, opacity: 0.98)
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(sourceColor.opacity(0.3), lineWidth: 1)
            )
            .focusSection()
            .focused($focusedSection, equals: .eventHUD)
            .onExitCommand {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedEvent = nil
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading events...")
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Day Cell View

struct DayCellView: View {
    let day: CalendarDay
    let events: [CalendarEvent]
    let isSelected: Bool
    let onSelect: () -> Void
    
    @Environment(\.isFocused) var isFocused

    /// Whether an event shows without a time on this day cell
    /// (all-day events, or multi-day timed events on middle days)
    private func showsAsAllDay(_ event: CalendarEvent) -> Bool {
        if event.isAllDay { return true }
        let calendar = Calendar.current
        let cellDay = calendar.startOfDay(for: day.date)
        let startDay = calendar.startOfDay(for: event.startTime)
        let endDay = calendar.startOfDay(for: event.endTime)
        // Multi-day timed event on a middle day (no time shown)
        if startDay != endDay && cellDay != startDay && cellDay != endDay {
            return true
        }
        return false
    }

    /// Deduplicated events by ID, sorted: timeless events first (alphabetically),
    /// then timed events by start time
    private var uniqueEvents: [CalendarEvent] {
        var seen = Set<String>()
        let deduped = events.filter { event in
            if seen.contains(event.id) {
                return false
            }
            seen.insert(event.id)
            return true
        }
        return deduped.sorted { a, b in
            let aAllDay = showsAsAllDay(a)
            let bAllDay = showsAsAllDay(b)
            if aAllDay != bAllDay {
                return aAllDay
            }
            if aAllDay && bAllDay {
                return a.summary.localizedCaseInsensitiveCompare(b.summary) == .orderedAscending
            }
            return a.startTime < b.startTime
        }
    }

    var body: some View {
        // Empty placeholder cells (dayNumber == 0)
        if day.dayNumber == 0 {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    // Day number - compact, left-aligned
                    HStack(spacing: 4) {
                        Text("\(day.dayNumber)")
                            .font(.caption)
                            .fontWeight(day.isToday ? .bold : .medium)
                            .foregroundColor(dayNumberColor)

                        // Today indicator
                        if day.isToday {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                        }
                    }

                    // Event indicators - directly below date
                    if !uniqueEvents.isEmpty {
                        eventIndicators
                    }

                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(cellBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
            }
            .buttonStyle(.card)
        }
    }

    private var dayNumberColor: Color {
        if !day.isCurrentMonth {
            return .white.opacity(0.3)
        } else if day.isToday {
            return .blue
        } else {
            return .white
        }
    }

    private var cellBackground: Color {
        if isSelected {
            return Color.red.opacity(0.05)
        } else if day.isToday {
            return Color.blue.opacity(0.2)
        } else {
            return Color.white.opacity(0.05)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .blue
        } else {
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 0
    }

    /// Returns the dot color for an event based on its source
    private func eventDotColor(for event: CalendarEvent) -> Color {
        switch event.source {
        case .google:
            return .orange
        case .icloud:
            return .blue
        }
    }

    @ViewBuilder
    private var eventIndicators: some View {
        let maxEventsToShow = 4
        let displayEvents = Array(uniqueEvents.prefix(maxEventsToShow))
        let hasMore = uniqueEvents.count > maxEventsToShow

        VStack(alignment: .leading, spacing: 2) {
            ForEach(displayEvents) { event in
                let isPast = isEventPast(event)
                VStack(alignment: .leading, spacing: 0) {
                    if shouldShowTime(for: event) {
                        Text(timeLabel(for: event))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(isPast ? 0.2 : 0.4))
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(eventDotColor(for: event).opacity(isPast ? 0.3 : 1.0))
                            .frame(width: 6, height: 6)

                        Text(event.summary)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(isPast ? 0.3 : 0.9))
                            .lineLimit(1)
                    }
                }
            }

            if hasMore {
                Text("+\(uniqueEvents.count - maxEventsToShow) more")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    /// Whether to show a time label for this event on the current day cell.
    /// Never for all-day events. For multi-day timed events, only on first and last day.
    private func shouldShowTime(for event: CalendarEvent) -> Bool {
        if event.isAllDay { return false }

        let calendar = Calendar.current
        let cellDay = calendar.startOfDay(for: day.date)
        let startDay = calendar.startOfDay(for: event.startTime)
        let endDay = calendar.startOfDay(for: event.endTime)

        // Single-day event — always show time
        if startDay == endDay { return true }

        // Multi-day event — only on first or last day
        return cellDay == startDay || cellDay == endDay
    }

    /// Returns the appropriate time label for a multi-day event on the current day.
    /// Shows start time on first day, end time on last day.
    private func timeLabel(for event: CalendarEvent) -> String {
        let calendar = Calendar.current
        let cellDay = calendar.startOfDay(for: day.date)
        let startDay = calendar.startOfDay(for: event.startTime)
        let endDay = calendar.startOfDay(for: event.endTime)

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let start = formatter.string(from: event.startTime)
        let end = formatter.string(from: event.endTime)
        let isMultiDay = startDay != endDay

        // Single-day: show full range. Multi-day: start time on first day, end time on last day.
        if cellDay == startDay {
            return isMultiDay ? start : "\(start) - \(end)"
        }
        if cellDay == endDay {
            return "Ends \(end)"
        }
        return start
    }

    /// Returns true if this is a timed event on today's cell whose end time has passed.
    private func isEventPast(_ event: CalendarEvent) -> Bool {
        guard !event.isAllDay, day.isToday else { return false }
        return event.endTime < Date()
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: CalendarEvent

    /// Returns the indicator color based on event source
    private var sourceColor: Color {
        switch event.source {
        case .google:
            return .orange
        case .icloud:
            return .blue
        }
    }

    var body: some View {
        HStack(spacing: 15) {
            // Source indicator
            VStack {
                Circle()
                    .fill(sourceColor)
                    .frame(width: 12, height: 12)
            }
            .padding(.leading, 8)

            // Event details
            VStack(alignment: .leading, spacing: 4) {
                Text(event.summary)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(event.formattedTime)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.7))

                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption)
                            Text(location)
                                .lineLimit(1)
                        }
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .padding(.vertical, 2)
    }
}

// MARK: - Event Group (kept for potential future use)

struct EventGroup {
    let date: Date
    let events: [CalendarEvent]

    var dateString: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Event Location Map View

/// Geocodes an address string and displays a Map with an annotation pin
struct EventLocationMapView: View {
    let address: String

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var pin: IdentifiableCoordinate?
    @State private var geocodeFailed = false

    var body: some View {
        Group {
            if geocodeFailed {
                // Fallback if geocoding fails (e.g. "Zoom Meeting" isn't an address)
                EmptyView()
            } else if let pin = pin {
                Map(position: $cameraPosition) {
                    Annotation("", coordinate: pin.coordinate) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                    }
                }
                .allowsHitTesting(false)
            } else {
                // Loading state while geocoding
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .onAppear {
            geocodeAddress()
        }
    }

    private func geocodeAddress() {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let coordinate = placemarks?.first?.location?.coordinate {
                region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                pin = IdentifiableCoordinate(coordinate: coordinate)
                cameraPosition = .region(region)
            } else {
                geocodeFailed = true
            }
        }
    }
}

/// Wrapper to make CLLocationCoordinate2D identifiable for Map annotations
struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    CalendarView(
        calendarManager: CalendarManager(),
        showingSettings: .constant(false)
    )
    .frame(width: 600)
    .padding()
}

