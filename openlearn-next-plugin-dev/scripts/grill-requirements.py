#!/usr/bin/env python3
"""grill-requirements.py —— OpenLearnV2 插件需求梳理 Grilling 决策向导.

通过单问推进、选项驱动、动态分支与即时护栏摩擦，引导开发者逐步明确：
受众场景、数据持久化、UI 通道可行性、白板挂件通信、平台权限与 AI Action。
最后自动汇总生成符合 L0/L2 护栏规范的 `plugin.contract.json`，并推荐脚手架生成命令。

用法：
    python3 grill-requirements.py                   # 交互式逐题问答
    python3 grill-requirements.py --dump-questions   # 导出全部题目与选项 JSON
    python3 grill-requirements.py --output /path/to/plugin.contract.json
    python3 grill-requirements.py --answers '{"q1":"A","q2":"A","q3":"A","q5":["1"]}'
"""

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional

try:
    from pydantic import BaseModel, Field

    HAS_PYDANTIC = True
except ImportError:
    from dataclasses import dataclass, field

    HAS_PYDANTIC = False


if HAS_PYDANTIC:

    class QuestionOption(BaseModel):
        """题目选项模型."""

        key: str = Field(..., description="选项键名 (A/B/C/D 或数字)")
        label: str = Field(..., description="选项显示名称与推荐标签")
        description: str = Field(default="", description="选项详细说明与架构影响")
        is_recommended: bool = Field(default=False, description="是否为推荐项")
        guardrail_warning: Optional[str] = Field(
            default=None, description="命中违规或受限方案时的即时摩擦警告"
        )

    class QuestionItem(BaseModel):
        """问答题干模型."""

        id: str = Field(..., description="题目标识符 (如 q1, q2)")
        title: str = Field(..., description="题目简要标题")
        prompt: str = Field(..., description="详细提问引导语")
        is_multi_select: bool = Field(default=False, description="是否为多选题")
        options: List[QuestionOption] = Field(
            default_factory=list, description="可选选项列表"
        )

    class PluginDesignContract(BaseModel):
        """生成的设计契约模型 (对齐 plugin.contract.json)."""

        executionMode: str = Field("process", description="执行模式: process / inline")
        uiChannel: str = Field(
            "sandbox-view",
            description="UI通道: sandbox-view / declarative / inline-react / none",
        )
        studentVisible: bool = Field(False, description="学生端是否可见")
        whiteboardWidget: bool = Field(False, description="是否为白板挂件卡片")
        slots: List[str] = Field(default_factory=list, description="贡献点槽位清单")
        viewFiles: Optional[List[str]] = Field(
            default=None, description="沙箱 HTML 页面路径 (storage/*.html)"
        )
        capabilitiesProposed: List[str] = Field(
            default_factory=list, description="申请的权限全集"
        )
        hasAiAction: bool = Field(True, description="是否注册 ActionDescriptor 供 AI 调用")
        recommendedTemplate: str = Field(
            "sandbox-view", description="推荐使用的 assets 模板名称"
        )

else:

    @dataclass
    class QuestionOption:
        """题目选项数据类."""

        key: str
        label: str
        description: str = ""
        is_recommended: bool = False
        guardrail_warning: Optional[str] = None

        def model_dump(self) -> Dict[str, Any]:
            """转换为字典格式."""
            return {
                "key": self.key,
                "label": self.label,
                "description": self.description,
                "is_recommended": self.is_recommended,
                "guardrail_warning": self.guardrail_warning,
            }

    @dataclass
    class QuestionItem:
        """问答题干数据类."""

        id: str
        title: str
        prompt: str
        is_multi_select: bool = False
        options: List[QuestionOption] = field(default_factory=list)

        def model_dump(self) -> Dict[str, Any]:
            """转换为字典格式."""
            return {
                "id": self.id,
                "title": self.title,
                "prompt": self.prompt,
                "is_multi_select": self.is_multi_select,
                "options": [opt.model_dump() for opt in self.options],
            }

    @dataclass
    class PluginDesignContract:
        """生成的设计契约数据类."""

        executionMode: str = "process"
        uiChannel: str = "sandbox-view"
        studentVisible: bool = False
        whiteboardWidget: bool = False
        slots: List[str] = field(default_factory=list)
        viewFiles: Optional[List[str]] = None
        capabilitiesProposed: List[str] = field(default_factory=list)
        hasAiAction: bool = True
        recommendedTemplate: str = "sandbox-view"

        def model_dump(self, exclude_none: bool = True) -> Dict[str, Any]:
            """转换为字典格式."""
            d: Dict[str, Any] = {
                "executionMode": self.executionMode,
                "uiChannel": self.uiChannel,
                "studentVisible": self.studentVisible,
                "whiteboardWidget": self.whiteboardWidget,
                "slots": self.slots,
                "capabilitiesProposed": self.capabilitiesProposed,
                "hasAiAction": self.hasAiAction,
                "recommendedTemplate": self.recommendedTemplate,
            }
            if self.viewFiles is not None:
                d["viewFiles"] = self.viewFiles
            return d


def load_live_contract(filename: str) -> Optional[Dict[str, Any]]:
    """加载平台契约数据 (优先平台一手源，降级本地快照).

    Args:
        filename: 契约文件名 (如 capabilities.json, slots.json).

    Returns:
        解析后的 JSON 字典，若未找到则返回 None.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(
            os.environ.get(
                "PLATFORM_REPO",
                os.path.expanduser("~/Develop/openlearnv2"),
            ),
            "docs",
            "agent",
            "contracts",
            filename,
        ),
        os.path.join(
            script_dir, "..", "assets", "test-harness", "contracts", filename
        ),
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
    return None


def get_all_questions() -> List[QuestionItem]:
    """获取 Grilling 题库全集与选项定义.

    Returns:
        定义完整的问答题干与结构化选项列表.
    """
    return [
        QuestionItem(
            id="q1",
            title="核心受众与业务场景",
            prompt="插件主要面向谁使用？解决什么课堂业务场景？",
            is_multi_select=False,
            options=[
                QuestionOption(
                    key="A",
                    label="(推荐) 师生互动型",
                    description="教师发起/控制，学生端实时接收、互动或作答（如课堂答题、白板挂件、抢答投票）",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="B",
                    label="教师专属工具",
                    description="仅教师可见与操作（如备课辅助、学情监控看板、课堂计时器控制台）",
                ),
                QuestionOption(
                    key="C",
                    label="学生专属工具",
                    description="仅学生可见与使用（如实验随堂笔记、自测练习器、个人错题小助手）",
                ),
                QuestionOption(
                    key="D",
                    label="纯后台 / 系统能力",
                    description="无师生直接交互的前端界面，用于后台数据分析、定时同步或 AI Agent 调度",
                ),
            ],
        ),
        QuestionItem(
            id="q2",
            title="后端状态与数据持久化",
            prompt="该插件是否需要后端命令、事件总线或本地数据库存储？",
            is_multi_select=False,
            options=[
                QuestionOption(
                    key="A",
                    label="(推荐) 需要独立数据库持久化",
                    description="需要独立的 SQLite 数据表（如题库表、答题流水表、统计记录），走向 full-stack",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="B",
                    label="仅需内存状态 / 事件总线",
                    description="需要后端服务处理业务逻辑与消息广播，但不需要新建持久化数据表，走向 full-stack",
                ),
                QuestionOption(
                    key="C",
                    label="纯轻量前端小工具",
                    description="不需要后端命令与后台数据库，仅在前端本地保持轻量状态或调用宿主公开 API，走向 frontend-only",
                ),
                QuestionOption(
                    key="D",
                    label="纯后端计算 / AI 工具",
                    description="无需前端界面，纯后端注册命令或 Action 工具，走向 server-only",
                ),
            ],
        ),
        QuestionItem(
            id="q3",
            title="前端 UI 展现通道 (P0 架构门禁)",
            prompt="插件打算采用哪种方式在 OpenLearnV2 宿主中呈现界面？",
            is_multi_select=False,
            options=[
                QuestionOption(
                    key="A",
                    label="(推荐) 双轨制沙箱页面 (storage/*.html，sandbox-view)",
                    description="宿主以受限 iframe 渲染页面，通过 OpenLearnPluginBridge 桥接通信；安全且无需白名单，可使用任意 HTML/CSS/JS 构建产物",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="B",
                    label="宿主原生声明式控件",
                    description="仅需要标准导航 Tab、工具栏按钮或命令面板条目，由宿主直接渲染，插件无需开发前端复杂页面",
                ),
                QuestionOption(
                    key="C",
                    label="白板互动卡片 (画布内挂件 type:'plugin')",
                    description="投射在电子白板画布上的卡片挂件（推荐通过 ext.view 映射到 storage/*.html，在 process 模式下安全运行）",
                ),
                QuestionOption(
                    key="D",
                    label="宿主内联原生 React 组件 (inline-react)",
                    description="直接注入宿主 React 树渲染（仅限加入 OPENLEARN_TRUSTED_INLINE_PLUGINS 白名单的插件）",
                    guardrail_warning="【高危/产品边界】第三方 process 插件注册 component 函数跨 postMessage 会触发 DataCloneError 导致激活失败！若未加入宿主白名单，请务必选择 A 或 C 的沙箱 view 方案！",
                ),
            ],
        ),
        QuestionItem(
            id="q4",
            title="白板/课堂数据投射机制",
            prompt="教师触发互动后，如何将挂件或数据准确推送到学生端？",
            is_multi_select=False,
            options=[
                QuestionOption(
                    key="A",
                    label="(推荐) 声明式代发 (classroomTools.commandType: 'whiteboard.draw')",
                    description="直接在 manifest 中将 commandType 声明为 whiteboard.draw，由宿主代发，零权限风险且符合规范",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="B",
                    label="后端命令派发 (commandBus.execute('whiteboard.draw', ...))",
                    description="在后端 Handler 收到动作后，通过命令总线统一派发 whiteboard.draw 到白板服务",
                ),
                QuestionOption(
                    key="C",
                    label="直接用 SQL 写入核心表 whiteboard_elements",
                    description="在子进程直接拼接 SQL 写入白板表",
                    guardrail_warning="【绝对禁区】子进程受 sql-guard 零信任安全防护，直接操作核心表会被拒绝！必须通过 A 或 B 机制由平台内核代发！",
                ),
            ],
        ),
        QuestionItem(
            id="q5",
            title="所需平台特权与能力申请 (Capabilities)",
            prompt="插件需要向宿主申请哪些特权能力？(多选，输入序号如 1,2)",
            is_multi_select=True,
            options=[
                QuestionOption(
                    key="1",
                    label="database",
                    description="本地数据库访问权限（受 sql-guard 插件独立前缀隔离保护）",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="2",
                    label="event:emit & event:subscribe",
                    description="课堂 EventBus 事件总线广播与订阅能力",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="3",
                    label="whiteboard:write",
                    description="白板元素创建与修改权限",
                ),
                QuestionOption(
                    key="4",
                    label="student-data:read & student-data:write",
                    description="学生课堂作答记录与学情分析数据读写",
                ),
                QuestionOption(
                    key="5",
                    label="llm:chat",
                    description="调用平台内置的大语言模型服务",
                ),
                QuestionOption(
                    key="6",
                    label="零特权 (仅基础沙箱)",
                    description="不需要任何受控系统特权",
                ),
            ],
        ),
        QuestionItem(
            id="q6",
            title="AI Agent 动作暴露 (ActionDescriptor)",
            prompt="是否需要将插件能力封装为 Action 暴露给课堂 AI Agent / 教学助手调用？",
            is_multi_select=False,
            options=[
                QuestionOption(
                    key="A",
                    label="(推荐) 需要注册 ActionDescriptor",
                    description="提供清晰语义化描述与入参 Schema，使课堂 AI Agent 能够通过工具调用触发本插件",
                    is_recommended=True,
                ),
                QuestionOption(
                    key="B",
                    label="不需要暴露给 AI",
                    description="仅供师生在 UI 界面或白板上人工点击交互",
                ),
            ],
        ),
    ]


def synthesize_contract(answers: Dict[str, Any]) -> PluginDesignContract:
    """根据问答结果动态推导并生成设计契约.

    Args:
        answers: 各题回答字典，形如 {'q1': 'A', 'q2': 'A', ...}.

    Returns:
        综合推导出的 PluginDesignContract 实例.
    """
    q1 = answers.get("q1", "A")
    q2 = answers.get("q2", "A")
    q3 = answers.get("q3", "A")
    q5_raw = answers.get("q5", ["1"])

    is_student_visible = q1 in ("A", "C")
    is_pure_backend = q1 == "D" or q2 == "D"

    # 执行模式与 UI 通道判定
    execution_mode = "process"
    ui_channel = "sandbox-view"
    whiteboard_widget = False
    slots: List[str] = []
    view_files: Optional[List[str]] = None
    recommended_template = "full-stack"

    if is_pure_backend:
        ui_channel = "none"
        recommended_template = "server-only"
    elif q2 == "C":
        # 纯前端
        ui_channel = "sandbox-view" if q3 == "A" else "declarative"
        recommended_template = "frontend-only"
        slots = ["teacher.tab"] if q1 == "B" else ["student.lesson.tool"]
    else:
        if q3 == "A":
            ui_channel = "sandbox-view"
            recommended_template = "sandbox-view"
            if q1 == "A":
                slots = ["teacher.tab", "student.view"]
                view_files = ["storage/teacher.html", "storage/student.html"]
            elif q1 == "B":
                slots = ["teacher.tab"]
                view_files = ["storage/teacher.html"]
            else:
                slots = ["student.lesson.tool"]
                view_files = ["storage/student.html"]
        elif q3 == "B":
            ui_channel = "declarative"
            recommended_template = "full-stack"
            slots = ["teacher.tab"]
        elif q3 == "C":
            ui_channel = "sandbox-view"
            whiteboard_widget = True
            recommended_template = "sandbox-view"
            slots = ["teacher.dashboard.widget", "student.view"]
            view_files = ["storage/teacher.html", "storage/student.html"]
        elif q3 == "D":
            ui_channel = "inline-react"
            execution_mode = "inline"
            recommended_template = "inline-react"
            slots = ["teacher.dashboard.widget", "student.view"]

    # 权限能力解析
    cap_map = {
        "1": "database",
        "2": "event:emit,event:subscribe",
        "3": "whiteboard:write",
        "4": "student-data:read,student-data:write",
        "5": "llm:chat",
    }
    caps: List[str] = []
    if isinstance(q5_raw, list):
        for item in q5_raw:
            val = cap_map.get(str(item).strip())
            if val:
                for sub in val.split(","):
                    if sub not in caps:
                        caps.append(sub)
    elif isinstance(q5_raw, str):
        for ch in q5_raw.replace("，", ",").split(","):
            val = cap_map.get(ch.strip())
            if val:
                for sub in val.split(","):
                    if sub not in caps:
                        caps.append(sub)

    has_ai = answers.get("q6", "A") == "A"

    return PluginDesignContract(
        executionMode=execution_mode,
        uiChannel=ui_channel,
        studentVisible=is_student_visible,
        whiteboardWidget=whiteboard_widget,
        slots=slots,
        viewFiles=view_files,
        capabilitiesProposed=caps,
        hasAiAction=has_ai,
        recommendedTemplate=recommended_template,
    )


def interactive_grill() -> Dict[str, Any]:
    """终端交互式逐题问答流程 (Grilling Wizard).

    Returns:
        用户选择的回答字典.
    """
    questions = get_all_questions()
    answers: Dict[str, Any] = {}

    print("\n" + "=" * 65)
    print("  OpenLearnV2 插件需求梳理 Grilling 决策向导")
    print("  遵循『单问推进、选项驱动、动态分支、即时摩擦』原则")
    print("=" * 65 + "\n")

    for q in questions:
        # 动态分支判断：如果已确定纯后台无 UI，则跳过 Q3 与 Q4
        if q.id in ("q3", "q4") and (
            answers.get("q1") == "D" or answers.get("q2") == "D"
        ):
            continue
        # 如果 Q3 没选白板挂件，则跳过 Q4 白板投射
        if q.id == "q4" and answers.get("q3") not in ("C", "A"):
            continue

        print(f"\n【{q.id.upper()}】{q.title}")
        print(f"  {q.prompt}\n")

        for opt in q.options:
            rec_tag = " ★" if opt.is_recommended else ""
            print(f"    [{opt.key}] {opt.label}{rec_tag}")
            if opt.description:
                print(f"        └─ {opt.description}")

        while True:
            try:
                choice = input(
                    f"\n  请输入选项键名 ({'/'.join(o.key for o in q.options)}): "
                ).strip()
            except (KeyboardInterrupt, EOFError):
                print("\n已取消问答向导。")
                sys.exit(1)

            if not choice:
                # 默认选用推荐项
                rec = next((o.key for o in q.options if o.is_recommended), None)
                if rec:
                    choice = rec
                    print(f"  (默认选择推荐项: [{rec}])")

            # 校验输入
            valid_keys = [o.key.upper() for o in q.options]
            if q.is_multi_select:
                selected_keys = [
                    k.strip() for k in choice.replace("，", ",").split(",") if k.strip()
                ]
                if all(k.upper() in valid_keys for k in selected_keys):
                    answers[q.id] = selected_keys
                    break
                print(f"  ✘ 输入有误，请输入有效的序号列表，如: 1,2")
            else:
                choice_upper = choice.upper()
                matched = next(
                    (o for o in q.options if o.key.upper() == choice_upper), None
                )
                if matched:
                    # 检查即时摩擦警告
                    if matched.guardrail_warning:
                        print(f"\n  \033[33m⚠ {matched.guardrail_warning}\033[0m")
                        confirm = (
                            input("  仍要坚持该选项吗？(y/N，推荐选 N 重新选择): ")
                            .strip()
                            .lower()
                        )
                        if confirm != "y":
                            continue
                    answers[q.id] = choice_upper
                    break
                print(f"  ✘ 输入无效，请输入其中一项：{valid_keys}")

    return answers


def main() -> None:
    """命令行主执行入口."""
    parser = argparse.ArgumentParser(
        description="OpenLearnV2 插件需求梳理 Grilling 决策向导"
    )
    parser.add_argument(
        "--dump-questions",
        action="store_true",
        help="导出题目定义 JSON 供 Agent 或自动化调用",
    )
    parser.add_argument(
        "--answers",
        type=str,
        help="非交互模式：直接传入 JSON 格式回答字典",
    )
    parser.add_argument(
        "--output",
        type=str,
        help="输出生成的 plugin.contract.json 目标文件路径",
    )
    args = parser.parse_args()

    if args.dump_questions:
        questions = get_all_questions()
        out = [
            q.model_dump() if hasattr(q, "model_dump") else q.__dict__
            for q in questions
        ]
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return

    if args.answers:
        try:
            answers = json.loads(args.answers)
        except Exception as e:
            print(f"解析 --answers 失败：{e}", file=sys.stderr)
            sys.exit(2)
    else:
        answers = interactive_grill()

    contract = synthesize_contract(answers)
    contract_dict = (
        contract.model_dump()
        if hasattr(contract, "model_dump")
        else contract.__dict__
    )

    live_caps = load_live_contract("capabilities.json")
    print("\n" + "=" * 65)
    print("  Grilling 梳理完成！已自动生成插件设计契约 (plugin.contract.json)")
    if live_caps:
        print("  [契约直连] 已动态对齐平台一手契约 (docs/agent/contracts/)")
    else:
        print("  [快照模式] 依据内置 references/ 快照对齐")
    print("=" * 65)
    print(f"  - 推荐模板:   {contract.recommendedTemplate}")
    print(f"  - 执行模式:   {contract.executionMode}")
    print(f"  - UI 通道:    {contract.uiChannel}")
    print(f"  - 学生端可见: {'是' if contract.studentVisible else '否'}")
    print(f"  - 白板挂件:   {'是' if contract.whiteboardWidget else '否'}")
    print(f"  - 槽位列表:   {contract.slots}")
    if contract.viewFiles:
        print(f"  - View 文件:  {contract.viewFiles}")
    print(f"  - 申请权限:   {contract.capabilitiesProposed}")
    print(f"  - AI Action:  {'是' if contract.hasAiAction else '否'}")
    print("=" * 65 + "\n")

    if args.output:
        out_path = os.path.expanduser(args.output)
        if os.path.isdir(out_path):
            out_path = os.path.join(out_path, "plugin.contract.json")
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(contract_dict, f, ensure_ascii=False, indent=2)
        print(f"✔ 已将设计契约写入：{out_path}")

    tpl = contract.recommendedTemplate
    print("💡 推荐脚手架创建命令：")
    print(f"  bash scripts/new-plugin.sh {tpl} my-{tpl}-plugin --id @ext/my-tool\n")


if __name__ == "__main__":
    main()
