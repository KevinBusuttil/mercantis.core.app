//
//  SchedulerService.swift
//  mercantis core
//
//  P1.4 / §4.13 — Periodic task scheduler.
//
//  Registers `ScheduledTask`s declared by app manifests via
//  `ExtensionPointResolver`, persists the last-run timestamp per task in
//  `scheduler_state`, and fires each task when its cadence has elapsed.
//
//  ### Lifecycle
//
//  - `register(declaration:appId:dispatch:)` — called by
//    `ExtensionPointResolver` at install / restore time. Returns an
//    `ExtensionSchedulerHandle` that the resolver retains; cancelling the
//    handle removes the task.
//  - `start()` — kicks off the periodic tick. The first tick runs
//    immediately so launch-time backlog catches up; subsequent ticks happen
//    on `tickInterval` (default 60s).
//  - `stop()` — cancels the tick task. Outstanding handles still
//    deregister cleanly when cancelled.
//
//  ### Concurrency model
//
//  The service holds a single `NSLock` around the `tasks` and `lastRun`
//  state. Each tick snapshots due tasks under the lock, releases it, and
//  invokes dispatch closures outside the lock so a slow handler can't block
//  a `register` call from another thread. Persistence writes happen after
//  dispatch returns — handlers that do their own async work need not hold
//  any scheduler state.
//

import Foundation

/// Periodic task scheduler. (P1.4, §4.13)
public final class SchedulerService: ExtensionSchedulerRegistrar, @unchecked Sendable {

    private let persistence: SchedulerPersistence
    private let tickInterval: TimeInterval
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private let errorReporter: (@Sendable (SchedulerError) -> Void)?

    private let lock = NSLock()
    private var tasks: [String: ScheduledTask] = [:]
    private var lastRun: [String: Date] = [:]
    private var cronCache: [String: CronExpression] = [:]
    private var tickTask: Task<Void, Never>?
    private var isStarted = false

    public init(
        persistence: SchedulerPersistence,
        tickInterval: TimeInterval = 60,
        calendar: Calendar = Calendar(identifier: .gregorian),
        clock: @escaping @Sendable () -> Date = { Date() },
        errorReporter: (@Sendable (SchedulerError) -> Void)? = nil
    ) {
        self.persistence = persistence
        self.tickInterval = tickInterval
        self.calendar = calendar
        self.clock = clock
        self.errorReporter = errorReporter
        self.lastRun = persistence.loadAll()
    }

    deinit {
        tickTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Begin the periodic tick loop. Idempotent — calling `start()` twice
    /// has no effect. The first tick runs immediately, before sleeping for
    /// `tickInterval`, so a task that came due while the app was closed
    /// fires on the first launch tick rather than waiting a full interval.
    public func start() {
        lock.lock()
        if isStarted {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()

        let interval = tickInterval
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                let nanos = UInt64(max(interval, 0.001) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    /// Cancel the tick loop. Tasks remain registered — call this on app
    /// background or shutdown rather than on every uninstall.
    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        lock.lock()
        isStarted = false
        lock.unlock()
    }

    // MARK: - Direct registration

    /// Register a `ScheduledTask` directly. Used by tests and by host apps
    /// that want to schedule first-party tasks without going through a
    /// manifest. Returns a handle whose `cancel()` deregisters the task.
    @discardableResult
    public func register(_ task: ScheduledTask) -> ExtensionSchedulerHandle {
        lock.lock()
        tasks[task.key] = task
        if case .cron(let expression) = task.interval {
            cronCache[task.key] = try? CronExpression.parse(expression)
            if cronCache[task.key] == nil {
                lock.unlock()
                errorReporter?(.invalidCron(taskKey: task.key, expression: expression))
                return ExtensionSchedulerHandle { [weak self] in
                    self?.deregister(key: task.key)
                }
            }
        }
        lock.unlock()

        return ExtensionSchedulerHandle { [weak self] in
            self?.deregister(key: task.key)
        }
    }

    /// Manually fire a tick. Surfaced so the host can synchronously catch
    /// up at launch (e.g. inside a `@main App`'s `init`) or test harnesses
    /// can drive the scheduler without sleeping.
    @discardableResult
    public func tick() -> [String] {
        let now = clock()
        let due: [ScheduledTask] = {
            lock.lock(); defer { lock.unlock() }
            return tasks.values.filter { task in
                isDue(task: task, at: now)
            }
        }()

        for task in due {
            task.dispatch()
            recordRun(key: task.key, at: now)
        }
        return due.map { $0.key }
    }

    // MARK: - ExtensionSchedulerRegistrar conformance

    public func register(
        declaration: SchedulerEventDeclaration,
        appId: String,
        dispatch: @escaping @Sendable () -> Void
    ) -> ExtensionSchedulerHandle {
        let task = ScheduledTask(
            key: Self.taskKey(appId: appId, declarationId: declaration.id),
            appId: appId,
            interval: declaration.interval,
            dispatch: dispatch
        )
        return register(task)
    }

    /// Drop every persisted last-run row for `appId` and any in-memory
    /// state that hasn't already been released via a handle. Called by
    /// `AppInstaller.uninstall` *in addition to* the resolver's
    /// per-handle teardown — the resolver path forgets the in-memory
    /// binding (so it stops firing immediately) but deliberately leaves
    /// `lastRun` and the persisted row in place so reinstall preserves
    /// cadence. Full uninstall is the only point that wipes the row.
    public func unregister(appId: String) {
        let prefix = appId + "::"
        lock.lock()
        let lastRunKeys = lastRun.keys.filter { $0.hasPrefix(prefix) }
        for key in lastRunKeys { lastRun.removeValue(forKey: key) }
        let taskKeys = tasks.values.filter { $0.appId == appId }.map(\.key)
        for key in taskKeys {
            tasks.removeValue(forKey: key)
            cronCache.removeValue(forKey: key)
        }
        lock.unlock()
        persistence.clear(appPrefix: appId)
    }

    // MARK: - Inspection (test / diagnostics)

    public func registeredTaskKeys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(tasks.keys)
    }

    public func taskCount(forAppId appId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return tasks.values.reduce(0) { $0 + ($1.appId == appId ? 1 : 0) }
    }

    public func lastRunTimestamp(forKey key: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return lastRun[key]
    }

    // MARK: - Internals

    private func deregister(key: String) {
        // Forget the in-memory binding so the next tick stops firing the
        // task. Deliberately leave `lastRun` and the persisted row alone
        // — see `unregister(appId:)` for the rationale (reinstall must
        // preserve cadence).
        lock.lock()
        tasks.removeValue(forKey: key)
        cronCache.removeValue(forKey: key)
        lock.unlock()
    }

    private func recordRun(key: String, at date: Date) {
        lock.lock()
        lastRun[key] = date
        lock.unlock()
        persistence.recordRun(key: key, at: date)
    }

    /// True when `task` should fire at `now`. A task with no `lastRun`
    /// fires immediately — the launch tick uses this to catch up tasks
    /// whose cadence elapsed while the app was closed. Subsequent firings
    /// are throttled by the interval's minimum gap (or the cron matcher
    /// for `.cron`).
    private func isDue(task: ScheduledTask, at now: Date) -> Bool {
        let last = lastRun[task.key]

        switch task.interval {
        case .all:
            // Fire on every tick. Used for the highest-frequency tasks.
            // First tick always fires; subsequent ticks fire if the tick
            // interval has fully elapsed.
            guard let last else { return true }
            return now.timeIntervalSince(last) >= max(tickInterval - 1, 0)

        case .hourly, .daily, .weekly, .monthly:
            guard let last else { return true }
            return now >= nextFixedFire(after: last, interval: task.interval)

        case .cron:
            guard let cron = cronCache[task.key] else { return false }
            // Two cases:
            //   - Never run before: fire if `now` matches a tick window. We
            //     treat the previous minute as the boundary so a freshly
            //     installed task doesn't fire on a minute that already
            //     passed before it registered.
            //   - Has run before: fire if any cron tick fell between
            //     `lastRun` and `now`.
            let scanFrom = last ?? calendar.date(
                byAdding: .minute, value: -1, to: now
            ) ?? now
            guard let next = cron.nextFireDate(after: scanFrom, in: calendar) else {
                return false
            }
            return next <= now
        }
    }

    /// Next time `interval` is allowed to fire after `last`. Used by the
    /// fixed cadences (`.hourly`, `.daily`, `.weekly`, `.monthly`) — each
    /// just adds the corresponding calendar component to `last`. We use the
    /// calendar (not raw seconds) so daylight-saving transitions don't
    /// shift a daily task's wall-clock time.
    private func nextFixedFire(after last: Date, interval: ScheduleInterval) -> Date {
        switch interval {
        case .hourly:  return calendar.date(byAdding: .hour,  value: 1,  to: last) ?? last
        case .daily:   return calendar.date(byAdding: .day,   value: 1,  to: last) ?? last
        case .weekly:  return calendar.date(byAdding: .day,   value: 7,  to: last) ?? last
        case .monthly: return calendar.date(byAdding: .month, value: 1,  to: last) ?? last
        case .all, .cron: return last
        }
    }

    static func taskKey(appId: String, declarationId: String) -> String {
        "\(appId)::\(declarationId)"
    }

    // MARK: - Errors

    public enum SchedulerError: Error, Sendable {
        /// The cron expression on a registered task could not be parsed.
        /// The task is registered (so `unregister(appId:)` still cleans it
        /// up) but will never fire until re-registered with a valid
        /// expression.
        case invalidCron(taskKey: String, expression: String)
    }
}
