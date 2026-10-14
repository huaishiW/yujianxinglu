# 个人物品与出门助手 (Personal Items & Outing Assistant)

《个人物品与出门助手》是一款 Android 优先、单用户、完全离线、基于本地 SQLite (Drift) 的个人物品收纳与出行清单管理工具。

---

## 核心业务功能

1. **多层级收纳位置管理**
   - 任意深度的收纳位置树形层级（如：家 → 主卧 → 书桌 → 左侧抽屉）。
   - 支持跨层级移动位置、移动到根节点，内置严格的祖先环路与自身移动检测防循环机制。
   - 同级节点重名防重约束。
   - 仅无子位置、无直接物品的空位置允许安全物理删除。

2. **物品库登记与管理**
   - 登记物品必须归属于一个有效的收纳位置。
   - 记录正整数数量，支持名称模糊搜索与完整路径追踪。
   - 物品删除时与模板及进行中任务执行原子级引用转换（转为文本条目保留历史状态）。

3. **出门模板管理**
   - 支持将常用的随身携带物品预设为出门模板（如：“通勤日常”、“短途差旅”、“雨天出行”）。
   - 支持混合条目类型（关联登记物品 / 普通文本备忘）。
   - 物品库存不足即时预警与最近使用时间追踪。

4. **本次出门清单生命周期**
   - 支持基于模板一键复用生成，亦支持直接新建本次清单。
   - 独立的任务状态隔离：各进行中任务互不干扰，勾选即刻持久化。
   - 任务完成时冻结历史快照（名称、数量、收纳位置全路径快照），已完成记录不可修改、不可删除。
   - 进行中任务支持整组安全编辑与删除二次确认。

5. **首页综合面板**
   - 物品全局快速搜索直达。
   - 进行中的出门任务卡片与进度条跟踪（如：“3 / 5 已准备”、“还剩 2 项未勾选”）。
   - 最近使用的出门模板快捷查看与一键导航。

---

## 技术架构

- **UI 框架**：Flutter 3.47.6 (Material 3)
- **状态管理**：Riverpod 3.x
- **路由管理**：go_router
- **本地数据库**：SQLite 3 + Drift 2.35 (启用外键约束与 ACID 事务保障)
- **架构分层**：
  - `lib/data/local/tables/`：Drift 六张核心业务表映射
  - `lib/data/repositories/`：LocationRepository、ItemRepository、TemplateRepository、SessionRepository
  - `lib/features/`：按领域划分（items, outings, home）的 Presentation / Application 分层
  - `lib/app/theme/`：统一的 Material 3 规范与配色系统

---

## 开发与验证指令

```powershell
# 运行全部自动化回归测试
flutter test

# 静态代码分析
flutter analyze

# 代码风格统一格式化
dart format lib test

# 编译 Android Debug 安装包
flutter build apk --debug
```

---

## Android 发布与签名配置说明

> **重要合规说明**：
> - 调试与本地测试期间默认沿用 Android Debug 证书。
> - 正式发布（Release 构建）前，建议在本地环境生成专属的发布私钥，通过 `android/key.properties` 独立加载，**切勿将密钥文件或密码凭据提交至 Git 仓库**。
