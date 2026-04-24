//
//  ScheduledTask.swift
//  mercantis core
//
//  P1.4 / §4.13 — Internal representation of one scheduler registration.
//

import Foundation

/// One scheduled task registered with `SchedulerService`. (§4.13, P1.4)
///
/// A `ScheduledTask` is created when `ExtensionPointResolver` forwards a
/// `SchedulerEventDeclaration` to the scheduler at install time. The task
/// carries the cadence and the dispatch closure that runs the declaration's
/// actions. The closure stays opaque to the scheduler — it is built by the
/// resolver and binds the action list to the `ExtensionActionDispatcher`.
public struct ScheduledTask: Sendable {

    /// Stable identity for this task, used as the `scheduler_state` key. The
    /// scheduler composes this from `appId::declarationId` so reinstalling
    /// the same app preserves the last-run timestamp and the next firing time
    /// is calculated from when the task last ran, not from when it was last
    /// registered.
    public let key: String

    /// App that owns this task. Used by `unregister(appId:)` to drop every
    /// task belonging to an uninstalled app in one call.
    public let appId: String

    /// Cadence at which the task should fire.
    public let interval: ScheduleInterval

    /// Closure invoked when the task is due. Synchronous and `Sendable` —
    /// long work should `Task.detached` from inside the closure rather than
    /// block the scheduler's tick.
    public let dispatch: @Sendable () -> Void

    /// Retry policy applied if `dispatch` throws. The scheduler does not
    /// catch errors from `dispatch` directly — its closures are produced by
    /// `ExtensionPointResolver`, which already routes failures through its
    /// own `errorReporter`. The policy here governs scheduler-internal
    /// retries (e.g. transient persistence failures); kept as a typed value
    /// so future internal retries don't need a signature change.
    public let retryPolicy: RetryPolicy

    public init(
        key: String,
        appId: String,
        interval: ScheduleInterval,
        retryPolicy: RetryPolicy = .none,
        dispatch: @escaping @Sendable () -> Void
    ) {
        self.key = key
        self.appId = appId
        self.interval = interval
        self.retryPolicy = retryPolicy
        self.dispatch = dispatch
    }

    public enum RetryPolicy: Sendable, Equatable {
        case none
        case fixed(attempts: Int, delay: TimeInterval)
        case exponentialBackoff(attempts: Int, base: TimeInterval)
    }
}
