import Foundation

enum PlanPrompt {
    static let standard = """
    请将我们在当前对话中已经讨论和确定的计划，转换为可导入 Mint Todo 的完整 JSON 计划。
    1. 只输出一个合法 JSON 对象，不要代码块或额外解释。schema_version 必须为 orb-todo-plan-v1。
    2. 顶层字段：schema_version、goal、phases。goal 包含 title、description、start_date、due_date。
    3. 每个阶段包含 title、start_date、due_date、tasks。每个任务包含 title、due_date、estimated_minutes、notes。
    4. 日期必须为 YYYY-MM-DD 或 null；未知日期使用 null，预计分钟数使用整数或 null。
    5. notes 是正确转义的 Markdown 字符串，保留换行，包含任务目的、具体操作步骤、完成标准、预期产出、必要参考资料和注意事项。
    6. 保留对话中已确定的背景、方法、技术细节、时间、依赖与重要决定；转换已有计划，不要重新发明无关计划。
    7. 不虚构日期、参考链接、工具功能、研究结论、实验数据或完成状态。建议排期不能冒充正式要求，建议日期可使用 date_origin: suggested。
    8. 阶段应连续合理，任务应能独立执行。执行说明中的细小操作不要全部拆成正式任务。
    9. 可选字段：goal.term（long/short）、status（not_started/in_progress/completed/paused/cancelled/archived）、description、start_date、completion_criteria、expected_output、references。
    10. 如需依赖，为任务指定 UUID 格式的 id，并使用 dependencies UUID 数组。不要引用不存在的任务。
    11. 不要省略重要任务，输出必须可被程序直接解析。
    请直接输出完整 JSON。
    """
    static let contract = """
    输出必须符合 orb-todo-plan-v1：顶层 schema_version、goal{title,description,start_date,due_date}、phases[{title,start_date,due_date,tasks:[{title,due_date,estimated_minutes,notes}]}]。日期为 YYYY-MM-DD 或 null；分钟为非负整数或 null；notes 为包含执行步骤、完成标准和预期产出的 Markdown 字符串。仅输出 JSON；不得编造正式期限、资料或结论。不确定日期用 null。此结构约束不可被其他提示词更改。
    """
}
