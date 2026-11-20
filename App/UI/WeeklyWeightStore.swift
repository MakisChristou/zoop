import Foundation
import Observation

/// Server-owned goals and summaries. Cache is scoped to the same account/device as Health.
@MainActor @Observable final class WeeklyWeightStore {
    typealias Loader = @Sendable (String) async throws -> ZoopAPI.WeeklyWeightResponse
    typealias HistoryLoader = @Sendable (String, Int64?) async throws -> ZoopAPI.GoalHistory
    typealias PeriodLoader = @Sendable (String, Int64) async throws -> ZoopAPI.GoalPeriod
    typealias Saver = @Sendable (String, ZoopAPI.WeightGoalInput) async throws -> ZoopAPI.WeightGoal
    private(set) var goal: ZoopAPI.WeightGoal?
    private(set) var summary: ZoopAPI.WeeklyWeightSummary?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var error: String?
    private(set) var saving = false
    private(set) var history: [ZoopAPI.GoalPeriod] = []
    private(set) var historyLoading = false
    private(set) var historyLoaded = false
    private(set) var historyError: String?
    private(set) var nextCursor: Int64?
    @ObservationIgnored private var historyRequest = UUID()
    var onGoalChange: (() -> Void)?
    let reminder: WeeklyWeightReminder
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let saver: Saver
    @ObservationIgnored private let historyLoader: HistoryLoader
    @ObservationIgnored private let periodLoader: PeriodLoader
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var device = ""
    @ObservationIgnored private var connection = ""
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, reminder: WeeklyWeightReminder = WeeklyWeightReminder(), loader: @escaping Loader = { try await ZoopAPI.weeklyWeight($0) }, saver: @escaping Saver = { try await ZoopAPI.saveWeightGoal($0, input: $1) }, historyLoader: @escaping HistoryLoader = { try await ZoopAPI.goalHistory($0,before:$1) }, periodLoader: @escaping PeriodLoader = { try await ZoopAPI.goalPeriod($0,id:$1) }) {
        self.defaults = defaults; self.reminder = reminder; self.loader = loader; self.saver = saver; self.historyLoader = historyLoader; self.periodLoader = periodLoader
    }
    func activate(device: String, scope: String?) {
        if self.scope != scope || self.device != device || connection != Settings.connectionID {
            scheduled?.cancel(); scheduled = nil; request = UUID()
            self.scope = scope; self.device = device; connection = Settings.connectionID
            goal = nil; summary = nil; error = nil; loaded = false; loading = false; saving = false
            history = []; historyLoaded = false; historyLoading = false; historyError = nil; nextCursor = nil; historyRequest = UUID()
            if let scope, let data = defaults.data(forKey: "weeklyWeight." + scope), let saved = try? JSONDecoder().decode(ZoopAPI.WeeklyWeightResponse.self, from: data) {
                goal = saved.goal; summary = saved.summary
            }
        }
        reminder.update(goal: goal, scope: scope); onGoalChange?()
        guard scope != nil, !device.isEmpty, !saving else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await self?.reload()
        }
    }
    func reload() async {
        guard let scope, !device.isEmpty, !saving else { return }
        let id = UUID(), connection = connection, device = device
        request = id; loading = true
        defer { if request == id { loading = false } }
        do {
            let result = try await loader(device)
            guard request == id, self.scope == scope, connection == Settings.connectionID, !Task.isCancelled else { return }
            goal = result.goal; summary = result.summary; loaded = true; error = nil
            persist(); reminder.update(goal: goal, scope: scope); onGoalChange?()
        } catch is CancellationError { }
        catch {
            guard request == id, self.scope == scope, connection == Settings.connectionID, !Task.isCancelled else { return }
            self.error = "Couldn’t update your weekly outlook. Try again."
        }
    }
    func save(_ input: ZoopAPI.WeightGoalInput) async throws {
        guard let scope, !device.isEmpty, !saving else { throw CancellationError() }
        let connection = connection, device = device
        saving = true; scheduled?.cancel(); scheduled = nil; request = UUID()
        defer { if self.scope == scope, self.device == device, self.connection == connection { saving = false } }
        let saved = try await saver(device, input)
        guard self.scope == scope, self.device == device, connection == Settings.connectionID else { throw CancellationError() }
        historyRequest = UUID(); historyLoading = false; historyLoaded = false
        goal = saved; summary = nil; loaded = true; error = nil
        persist(); reminder.update(goal: saved, scope: scope); onGoalChange?()
        saving = false
        await reload()
    }
    func reloadHistory(more: Bool = false) async {
        guard let scope, !device.isEmpty, !historyLoading, !more || nextCursor != nil else { return }
        let id = UUID(), device = device, connection = connection
        let cursor = more ? nextCursor : nil
        historyRequest = id; historyLoading = true; historyError = nil
        defer { if historyRequest == id { historyLoading = false } }
        do {
            let page = try await historyLoader(device,cursor)
            guard historyRequest == id, self.scope == scope, self.device == device, connection == Settings.connectionID, !Task.isCancelled else { return }
            history = more ? history + page.items.filter { item in !history.contains { $0.id == item.id } } : page.items
            nextCursor = page.nextCursor; historyLoaded = true
        } catch is CancellationError { }
        catch {
            guard historyRequest == id, self.scope == scope, connection == Settings.connectionID else { return }
            historyError = "Couldn’t load past goals."
        }
    }
    func period(_ id: Int64) async throws -> ZoopAPI.GoalPeriod {
        let scope = scope, device = device, connection = connection
        let result = try await periodLoader(device,id)
        guard self.scope == scope, self.device == device, connection == Settings.connectionID, !Task.isCancelled else { throw CancellationError() }
        return result
    }
    func endCurrent() async throws {
        guard let goal, goal.active else { return }
        try await save(.init(revision: goal.revision, active: false, timezone: goal.timezone,
            weeklyLossKg: goal.weeklyLossKg, reminderEnabled: goal.reminderEnabled,
            reminderWeekday: goal.reminderWeekday, reminderMinute: goal.reminderMinute,
            dailyStepsGoal: goal.dailyStepsGoal, finishDate: goal.finishDate))
        await reloadHistory()
    }
    private func persist() {
        guard let scope, let data = try? JSONEncoder().encode(ZoopAPI.WeeklyWeightResponse(goal: goal, summary: summary)) else { return }
        defaults.set(data, forKey: "weeklyWeight." + scope)
    }
}
