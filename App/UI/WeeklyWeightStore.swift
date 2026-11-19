import Foundation
import Observation

/// Server-owned goals and summaries. Cache is scoped to the same account/device as Health.
@MainActor @Observable final class WeeklyWeightStore {
    typealias Loader = @Sendable (String) async throws -> ZoopAPI.WeeklyWeightResponse
    typealias Saver = @Sendable (String, ZoopAPI.WeightGoalInput) async throws -> ZoopAPI.WeightGoal
    private(set) var goal: ZoopAPI.WeightGoal?
    private(set) var summary: ZoopAPI.WeeklyWeightSummary?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var error: String?
    private(set) var saving = false
    var onGoalChange: (() -> Void)?
    let reminder: WeeklyWeightReminder
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let saver: Saver
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var device = ""
    @ObservationIgnored private var connection = ""
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, reminder: WeeklyWeightReminder = WeeklyWeightReminder(), loader: @escaping Loader = { try await ZoopAPI.weeklyWeight($0) }, saver: @escaping Saver = { try await ZoopAPI.saveWeightGoal($0, input: $1) }) {
        self.defaults = defaults; self.reminder = reminder; self.loader = loader; self.saver = saver
    }
    func activate(device: String, scope: String?) {
        if self.scope != scope || self.device != device || connection != Settings.connectionID {
            scheduled?.cancel(); scheduled = nil; request = UUID()
            self.scope = scope; self.device = device; connection = Settings.connectionID
            goal = nil; summary = nil; error = nil; loaded = false; loading = false; saving = false
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
        let connection = connection
        saving = true; scheduled?.cancel(); scheduled = nil; request = UUID()
        defer { if self.scope == scope { saving = false } }
        let saved = try await saver(device, input)
        guard self.scope == scope, connection == Settings.connectionID else { throw CancellationError() }
        goal = saved; summary = nil; loaded = true; error = nil
        persist(); reminder.update(goal: saved, scope: scope); onGoalChange?()
        saving = false
        await reload()
    }
    private func persist() {
        guard let scope, let data = try? JSONEncoder().encode(ZoopAPI.WeeklyWeightResponse(goal: goal, summary: summary)) else { return }
        defaults.set(data, forKey: "weeklyWeight." + scope)
    }
}
