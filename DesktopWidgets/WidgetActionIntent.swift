import AppIntents
import WidgetKit

struct CompleteMintTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "更新 Mint Todo 任务"
    static var description = IntentDescription("在小组件与试用版之间同步任务完成状态。")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "任务 ID") var taskID: String
    @Parameter(title: "目标任务") var isGoal: Bool
    @Parameter(title: "完成") var completed: Bool

    init() {}
    init(taskID: UUID, isGoal: Bool = false, completed: Bool) {
        self.taskID = taskID.uuidString; self.isGoal = isGoal; self.completed = completed
    }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let files = MintWidgetFiles()
        let command = MintWidgetCommand(target: isGoal ? .goal : .daily, taskID: id, completed: completed)
        guard try files.readSnapshot().contains(command) else { return .result() }
        try files.enqueue(command)
        WidgetCenter.shared.reloadTimelines(ofKind: MintWidgetFiles.kind)
        return .result()
    }
}
