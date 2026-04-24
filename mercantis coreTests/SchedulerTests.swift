//
//  SchedulerTests.swift
//  mercantis coreTests
//
//  P1.4 — Coverage for the Scheduling subsystem: cron parser, persistence,
//  due-check semantics, and `ExtensionSchedulerRegistrar` conformance.
//

import XCTest
import GRDB
@testable import mercantis_core

final class SchedulerTests: XCTestCase {

    // MARK: - Helpers

    private var url: URL!
    private var database: MercantisDatabase!

    override func setUpWithError() throws {
        url = TestSupport.tempDatabaseURL("scheduler")
        database = try TestSupport.makeDatabase(at: url)
    }

    override func tearDown() {
        TestSupport.cleanUp(databaseURL: url)
        url = nil
        database = nil
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func makeService(
        tickInterval: TimeInterval = 60,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) -> SchedulerService {
        SchedulerService(
            persistence: SchedulerPersistence(database: database),
            tickInterval: tickInterval,
            calendar: Self.utcCalendar,
            clock: clock
        )
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - CronExpression: parsing

    func testCronParsesWildcardEveryMinute() throws {
        let cron = try CronExpression.parse("* * * * *")
        XCTAssertEqual(cron.minutes.count, 60)
        XCTAssertEqual(cron.hours.count, 24)
        XCTAssertEqual(cron.daysOfMonth.count, 31)
        XCTAssertEqual(cron.months.count, 12)
        XCTAssertEqual(cron.daysOfWeek.count, 7)
        XCTAssertFalse(cron.dayFieldsAreUnion)
    }

    func testCronParsesExactValue() throws {
        let cron = try CronExpression.parse("0 9 * * *")
        XCTAssertEqual(cron.minutes, [0])
        XCTAssertEqual(cron.hours, [9])
    }

    func testCronParsesCommaSeparatedList() throws {
        let cron = try CronExpression.parse("0,15,30,45 * * * *")
        XCTAssertEqual(cron.minutes, [0, 15, 30, 45])
    }

    func testCronParsesInclusiveRange() throws {
        let cron = try CronExpression.parse("* 9-17 * * *")
        XCTAssertEqual(cron.hours, Set(9...17))
    }

    func testCronParsesStepWithWildcard() throws {
        let cron = try CronExpression.parse("*/15 * * * *")
        XCTAssertEqual(cron.minutes, [0, 15, 30, 45])
    }

    func testCronParsesStepWithRange() throws {
        let cron = try CronExpression.parse("0-30/10 * * * *")
        XCTAssertEqual(cron.minutes, [0, 10, 20, 30])
    }

    func testCronAcceptsSundayAsZeroOrSeven() throws {
        let zero = try CronExpression.parse("* * * * 0")
        let seven = try CronExpression.parse("* * * * 7")
        XCTAssertEqual(zero.daysOfWeek, [0])
        XCTAssertEqual(seven.daysOfWeek, [0])
    }

    func testCronRejectsWrongFieldCount() {
        XCTAssertThrowsError(try CronExpression.parse("* * * *"))
        XCTAssertThrowsError(try CronExpression.parse("* * * * * *"))
    }

    func testCronRejectsOutOfRangeValue() {
        XCTAssertThrowsError(try CronExpression.parse("60 * * * *"))
        XCTAssertThrowsError(try CronExpression.parse("* 24 * * *"))
        XCTAssertThrowsError(try CronExpression.parse("* * 32 * *"))
        XCTAssertThrowsError(try CronExpression.parse("* * * 13 *"))
    }

    func testCronRejectsInvertedRange() {
        XCTAssertThrowsError(try CronExpression.parse("30-10 * * * *"))
    }

    func testCronRejectsZeroStep() {
        XCTAssertThrowsError(try CronExpression.parse("*/0 * * * *"))
    }

    func testCronRejectsNonIntegerValue() {
        XCTAssertThrowsError(try CronExpression.parse("abc * * * *"))
    }

    // MARK: - CronExpression: matching

    func testCronMatchesExactTime() throws {
        let cron = try CronExpression.parse("30 14 * * *")
        let utc = Calendar(identifier: .gregorian).withTimeZone(TimeZone(identifier: "UTC")!)
        XCTAssertTrue(cron.matches(Self.date(year: 2026, month: 4, day: 24, hour: 14, minute: 30), in: utc))
        XCTAssertFalse(cron.matches(Self.date(year: 2026, month: 4, day: 24, hour: 14, minute: 31), in: utc))
        XCTAssertFalse(cron.matches(Self.date(year: 2026, month: 4, day: 24, hour: 15, minute: 30), in: utc))
    }

    func testCronDayFieldsUseUnionWhenBothExplicit() throws {
        // "fire on the 1st of the month OR every Friday"
        let cron = try CronExpression.parse("0 12 1 * 5")
        XCTAssertTrue(cron.dayFieldsAreUnion)
        let utc = Calendar(identifier: .gregorian).withTimeZone(TimeZone(identifier: "UTC")!)

        // 2026-05-01 is a Friday — both match.
        XCTAssertTrue(cron.matches(Self.date(year: 2026, month: 5, day: 1, hour: 12, minute: 0), in: utc))
        // 2026-05-08 is a Friday but not the 1st — DOW match alone is enough under union semantics.
        XCTAssertTrue(cron.matches(Self.date(year: 2026, month: 5, day: 8, hour: 12, minute: 0), in: utc))
        // 2026-06-01 is a Monday — DOM match alone is enough under union semantics.
        XCTAssertTrue(cron.matches(Self.date(year: 2026, month: 6, day: 1, hour: 12, minute: 0), in: utc))
        // 2026-05-02 is a Saturday and not the 1st — neither matches.
        XCTAssertFalse(cron.matches(Self.date(year: 2026, month: 5, day: 2, hour: 12, minute: 0), in: utc))
    }

    func testCronNextFireDateAdvancesPastNonMatchingMinutes() throws {
        let cron = try CronExpression.parse("0 9 * * *")   // 09:00 daily
        let utc = Calendar(identifier: .gregorian).withTimeZone(TimeZone(identifier: "UTC")!)
        let from = Self.date(year: 2026, month: 4, day: 24, hour: 8, minute: 30)
        let next = cron.nextFireDate(after: from, in: utc)
        XCTAssertEqual(next, Self.date(year: 2026, month: 4, day: 24, hour: 9, minute: 0))
    }

    func testCronNextFireDateRollsToNextDay() throws {
        let cron = try CronExpression.parse("0 9 * * *")
        let utc = Calendar(identifier: .gregorian).withTimeZone(TimeZone(identifier: "UTC")!)
        let from = Self.date(year: 2026, month: 4, day: 24, hour: 9, minute: 0)
        let next = cron.nextFireDate(after: from, in: utc)
        XCTAssertEqual(next, Self.date(year: 2026, month: 4, day: 25, hour: 9, minute: 0))
    }

    // MARK: - SchedulerPersistence

    func testPersistenceRoundTripsLastRun() throws {
        let p = SchedulerPersistence(database: database)
        let stamp = Self.date(year: 2026, month: 4, day: 24, hour: 12, minute: 0)
        p.recordRun(key: "app.x::daily", at: stamp)

        XCTAssertEqual(p.lastRun(forKey: "app.x::daily")?.timeIntervalSince1970, stamp.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(p.loadAll().count, 1)
    }

    func testPersistenceUpsertsExistingKey() {
        let p = SchedulerPersistence(database: database)
        let early = Self.date(year: 2026, month: 4, day: 1)
        let later = Self.date(year: 2026, month: 4, day: 10)
        p.recordRun(key: "app.x::daily", at: early)
        p.recordRun(key: "app.x::daily", at: later)

        XCTAssertEqual(p.lastRun(forKey: "app.x::daily")?.timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(p.loadAll().count, 1)
    }

    func testPersistenceClearByPrefixDropsAppRows() {
        let p = SchedulerPersistence(database: database)
        let now = Self.date(year: 2026, month: 4, day: 24)
        p.recordRun(key: "app.a::daily",  at: now)
        p.recordRun(key: "app.a::weekly", at: now)
        p.recordRun(key: "app.b::daily",  at: now)

        p.clear(appPrefix: "app.a")

        XCTAssertNil(p.lastRun(forKey: "app.a::daily"))
        XCTAssertNil(p.lastRun(forKey: "app.a::weekly"))
        XCTAssertNotNil(p.lastRun(forKey: "app.b::daily"))
    }

    // MARK: - SchedulerService: cadence

    func testTickFiresTaskWithNoLastRun() {
        let service = makeService()
        var fired = 0
        let task = ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: { fired += 1 }
        )
        service.register(task)

        let firedKeys = service.tick()
        XCTAssertEqual(firedKeys, ["app.x::daily"])
        XCTAssertEqual(fired, 1)
    }

    func testTickHonoursDailyCadenceAndDoesNotRefire() {
        var clockNow = Self.date(year: 2026, month: 4, day: 24, hour: 12)
        let service = makeService(clock: { clockNow })
        var fired = 0
        service.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: { fired += 1 }
        ))

        // First tick — fires (no lastRun).
        XCTAssertEqual(service.tick(), ["app.x::daily"])

        // 12 hours later — daily not yet due.
        clockNow = clockNow.addingTimeInterval(12 * 3600)
        XCTAssertEqual(service.tick(), [])

        // 24 hours after the first run — fires again.
        clockNow = Self.date(year: 2026, month: 4, day: 25, hour: 12)
        XCTAssertEqual(service.tick(), ["app.x::daily"])

        XCTAssertEqual(fired, 2)
    }

    func testHourlyCadenceFiresEveryHour() {
        var clockNow = Self.date(year: 2026, month: 4, day: 24, hour: 9, minute: 0)
        let service = makeService(clock: { clockNow })
        var fired = 0
        service.register(ScheduledTask(
            key: "app.x::hourly",
            appId: "app.x",
            interval: .hourly,
            dispatch: { fired += 1 }
        ))

        XCTAssertEqual(service.tick(), ["app.x::hourly"])    // first run
        clockNow = clockNow.addingTimeInterval(30 * 60)       // +30 min
        XCTAssertEqual(service.tick(), [])
        clockNow = clockNow.addingTimeInterval(30 * 60)       // +60 min total
        XCTAssertEqual(service.tick(), ["app.x::hourly"])
        XCTAssertEqual(fired, 2)
    }

    func testCronCadenceFiresAtMatchingMinute() {
        var clockNow = Self.date(year: 2026, month: 4, day: 24, hour: 8, minute: 59)
        let service = makeService(clock: { clockNow })
        var fired = 0
        // 09:00 daily.
        service.register(ScheduledTask(
            key: "app.x::cron",
            appId: "app.x",
            interval: .cron("0 9 * * *"),
            dispatch: { fired += 1 }
        ))

        // 08:59 — not due.
        XCTAssertEqual(service.tick(), [])
        XCTAssertEqual(fired, 0)

        // 09:00 — due.
        clockNow = Self.date(year: 2026, month: 4, day: 24, hour: 9, minute: 0)
        XCTAssertEqual(service.tick(), ["app.x::cron"])
        XCTAssertEqual(fired, 1)

        // 09:01 same day — already fired today, not due again.
        clockNow = Self.date(year: 2026, month: 4, day: 24, hour: 9, minute: 1)
        XCTAssertEqual(service.tick(), [])

        // 09:00 next day — due.
        clockNow = Self.date(year: 2026, month: 4, day: 25, hour: 9, minute: 0)
        XCTAssertEqual(service.tick(), ["app.x::cron"])
        XCTAssertEqual(fired, 2)
    }

    func testCronInvalidExpressionReportsErrorAndDoesNotFire() {
        let reportedExpectation = expectation(description: "errorReporter")
        let service = SchedulerService(
            persistence: SchedulerPersistence(database: database),
            tickInterval: 60,
            calendar: Self.utcCalendar,
            errorReporter: { error in
                if case .invalidCron = error { reportedExpectation.fulfill() }
            }
        )

        var fired = 0
        service.register(ScheduledTask(
            key: "app.x::bad-cron",
            appId: "app.x",
            interval: .cron("nonsense"),
            dispatch: { fired += 1 }
        ))

        wait(for: [reportedExpectation], timeout: 0.1)
        XCTAssertEqual(service.tick(), [])
        XCTAssertEqual(fired, 0)
    }

    // MARK: - SchedulerService: persistence + restart

    func testLastRunSurvivesServiceRestart() {
        let originalNow = Self.date(year: 2026, month: 4, day: 24, hour: 12)
        var clockNow = originalNow

        let first = makeService(clock: { clockNow })
        first.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: {}
        ))
        XCTAssertEqual(first.tick(), ["app.x::daily"])
        XCTAssertNotNil(first.lastRunTimestamp(forKey: "app.x::daily"))

        // Simulate process restart: build a new service against the same DB.
        let second = makeService(clock: { clockNow })
        XCTAssertEqual(
            second.lastRunTimestamp(forKey: "app.x::daily")?.timeIntervalSince1970,
            originalNow.timeIntervalSince1970,
            accuracy: 0.01
        )

        // Re-register and tick on the same calendar day — should not re-fire.
        var fired = 0
        second.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: { fired += 1 }
        ))
        XCTAssertEqual(second.tick(), [])
        XCTAssertEqual(fired, 0)

        // Advance past 24h — should fire.
        clockNow = clockNow.addingTimeInterval(25 * 3600)
        XCTAssertEqual(second.tick(), ["app.x::daily"])
        XCTAssertEqual(fired, 1)
    }

    func testRestartFiresImmediatelyForBackloggedTask() {
        let originalNow = Self.date(year: 2026, month: 4, day: 24, hour: 12)

        let first = makeService(clock: { originalNow })
        first.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: {}
        ))
        XCTAssertEqual(first.tick(), ["app.x::daily"])

        // App stays closed for three days; on next launch the task is
        // overdue and should fire on the first tick.
        let later = originalNow.addingTimeInterval(3 * 24 * 3600)
        let second = makeService(clock: { later })
        var fired = 0
        second.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: { fired += 1 }
        ))
        XCTAssertEqual(second.tick(), ["app.x::daily"])
        XCTAssertEqual(fired, 1)
    }

    // MARK: - SchedulerService: lifecycle / handles

    func testHandleCancelStopsFurtherDispatch() {
        var clockNow = Self.date(year: 2026, month: 4, day: 24)
        let service = makeService(clock: { clockNow })
        var fired = 0
        let handle = service.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: { fired += 1 }
        ))

        XCTAssertEqual(service.tick(), ["app.x::daily"])
        XCTAssertEqual(fired, 1)

        handle.cancel()

        clockNow = clockNow.addingTimeInterval(48 * 3600)
        XCTAssertEqual(service.tick(), [])
        XCTAssertEqual(fired, 1)
    }

    func testHandleCancelPreservesPersistedLastRunForReinstall() {
        let originalNow = Self.date(year: 2026, month: 4, day: 24, hour: 12)
        var clockNow = originalNow
        let service = makeService(clock: { clockNow })

        let handle = service.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: {}
        ))
        XCTAssertEqual(service.tick(), ["app.x::daily"])

        handle.cancel()

        // Re-register the same task — handle.cancel() is the reinstall
        // path. Last-run must be preserved so we don't fire again until
        // 24 h have passed.
        var fired = 0
        service.register(ScheduledTask(
            key: "app.x::daily",
            appId: "app.x",
            interval: .daily,
            dispatch: { fired += 1 }
        ))

        // 12 hours later — daily not due.
        clockNow = clockNow.addingTimeInterval(12 * 3600)
        XCTAssertEqual(service.tick(), [])
        XCTAssertEqual(fired, 0)

        // 25 hours later — daily due.
        clockNow = originalNow.addingTimeInterval(25 * 3600)
        XCTAssertEqual(service.tick(), ["app.x::daily"])
        XCTAssertEqual(fired, 1)
    }

    func testUnregisterByAppIdWipesPersistedRows() {
        let now = Self.date(year: 2026, month: 4, day: 24)
        let service = makeService(clock: { now })

        service.register(ScheduledTask(key: "app.a::daily", appId: "app.a", interval: .daily, dispatch: {}))
        service.register(ScheduledTask(key: "app.a::weekly", appId: "app.a", interval: .weekly, dispatch: {}))
        service.register(ScheduledTask(key: "app.b::daily", appId: "app.b", interval: .daily, dispatch: {}))
        _ = service.tick()

        service.unregister(appId: "app.a")

        XCTAssertEqual(service.taskCount(forAppId: "app.a"), 0)
        XCTAssertEqual(service.taskCount(forAppId: "app.b"), 1)

        // Persistence is gone for app.a too — verify by spinning a fresh service.
        let restarted = makeService()
        XCTAssertNil(restarted.lastRunTimestamp(forKey: "app.a::daily"))
        XCTAssertNil(restarted.lastRunTimestamp(forKey: "app.a::weekly"))
        XCTAssertNotNil(restarted.lastRunTimestamp(forKey: "app.b::daily"))
    }

    // MARK: - ExtensionSchedulerRegistrar conformance

    func testServiceConformsToExtensionSchedulerRegistrar() {
        let now = Self.date(year: 2026, month: 4, day: 24)
        let service = makeService(clock: { now })
        let registrar: ExtensionSchedulerRegistrar = service

        var fired = 0
        let handle = registrar.register(
            declaration: SchedulerEventDeclaration(
                id: "daily-cleanup",
                interval: .daily,
                actions: []
            ),
            appId: "app.test.registrar",
            dispatch: { fired += 1 }
        )
        XCTAssertEqual(service.taskCount(forAppId: "app.test.registrar"), 1)

        XCTAssertEqual(service.tick(), ["app.test.registrar::daily-cleanup"])
        XCTAssertEqual(fired, 1)

        handle.cancel()
        XCTAssertEqual(service.taskCount(forAppId: "app.test.registrar"), 0)
    }

    // MARK: - End-to-end: AppInstaller + ExtensionPointResolver + SchedulerService

    func testSchedulerWiredThroughExtensionPointResolverAndAppInstaller() throws {
        let originalNow = Self.date(year: 2026, month: 4, day: 24, hour: 12)
        var clockNow = originalNow

        let scheduler = makeService(clock: { clockNow })
        let dispatcher = LoggingExtensionActionDispatcher()
        let registry = MetadataRegistry(database: database)
        let emitter = EventEmitter()
        let resolver = ExtensionPointResolver(
            emitter: emitter,
            dispatcher: dispatcher,
            schedulerRegistrar: scheduler
        )
        let installer = AppInstaller(
            database: database,
            schemaValidator: SchemaValidator(),
            registry: registry,
            extensionResolver: resolver,
            schedulerService: scheduler
        )

        let manifest = AppManifest(
            id: "app.test.sched.e2e",
            name: "Scheduler E2E",
            version: "0.1.0",
            minimumCoreVersion: "1.0.0",
            description: "",
            doctypes: [],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: [],
            extensionPoints: ExtensionPoints(
                schedulerEvents: [
                    SchedulerEventDeclaration(
                        id: "daily-cleanup",
                        interval: .daily,
                        actions: [ExtensionActionDeclaration(actionType: "send_notification")]
                    )
                ]
            )
        )

        try installer.install(manifest)
        XCTAssertEqual(scheduler.taskCount(forAppId: manifest.id), 1)

        // First tick fires the action through the dispatcher.
        XCTAssertEqual(scheduler.tick().count, 1)
        XCTAssertEqual(dispatcher.entries.count, 1)
        XCTAssertEqual(dispatcher.entries.first?.actionType, "send_notification")
        XCTAssertEqual(dispatcher.entries.first?.appId, manifest.id)

        // Same day — not due.
        clockNow = clockNow.addingTimeInterval(2 * 3600)
        XCTAssertEqual(scheduler.tick(), [])

        // Uninstall releases the binding and wipes scheduler persistence.
        try installer.uninstall(appId: manifest.id)
        XCTAssertEqual(scheduler.taskCount(forAppId: manifest.id), 0)

        let restarted = makeService(clock: { clockNow })
        XCTAssertNil(restarted.lastRunTimestamp(forKey: "\(manifest.id)::daily-cleanup"))
    }
}

// MARK: - Calendar timezone helper

private extension Calendar {
    func withTimeZone(_ tz: TimeZone) -> Calendar {
        var c = self
        c.timeZone = tz
        return c
    }
}
