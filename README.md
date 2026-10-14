<p align="center">
  <img src="assets/branding/yujianxinglu.png" width="180" alt="玉简行录 Logo" style="border-radius: 36px;" />
</p>

<h1 align="center">玉简行录 (Yujianxinglu)</h1>

<p align="center">
  <strong>落笔随行 · 简明知物 · 离线随身收纳与出门清单助手</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47.6-02569B?logo=flutter" alt="Flutter Version" />
  <img src="https://img.shields.io/badge/Dart-3.13.5-0175C2?logo=dart" alt="Dart Version" />
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android" alt="Android Platform" />
  <img src="https://img.shields.io/badge/Database-SQLite%20%2B%20Drift-003B57?logo=sqlite" alt="SQLite & Drift" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT" />
</p>

---

## 项目简介

《玉简行录》（原开发代号：个人物品与出门助手 / Personal Items & Outing Assistant）是一款 **Android 优先、单用户、100% 离线、基于本地 SQLite (Drift)** 的个人随身物品收纳管理与出行核验工具。

旨在帮助用户清晰记录物品位置，并在每一次出行前通过结构化清单进行快速核验，告别丢三落四，保持从容自律。

---

## 核心功能特性

### 1. 多层级收纳位置树
- **任意深度层级**：支持任意深度的收纳树形层级（如：`家 → 主卧 → 书桌 → 左侧第二抽屉`）。
- **安全拓扑移动**：支持跨层级移动或移动至根节点，内置严格的**祖先环路与自移动检测**防循环机制。
- **重名防重校验**：同父级节点下（包括根节点）严格禁止重名。
- **安全删除保护**：仅无子位置、无直接登记物品的空位置允许物理删除。

### 2. 物品登记与全局检索
- **单向归属约束**：每件已登记物品必须属于且仅属于一个有效的收纳位置。
- **正整数存量跟踪**：记录数量、分类与备忘，支持多关键字快速搜索与全路径溯源。
- **原子引用转换**：删除已登记物品时，已关联该物品的模板条目与进行中任务条目将**原子级转换为普通文本备忘**，完整保留名称、数量、排序和勾选状态，不破坏用户既有清单。

### 3. 可复用出门模板
- **场景化预设**：支持为高频出行场景建立模板（如“日常通勤”、“短途差旅”、“雨天随行”）。
- **混合条目支持**：条目支持自由关联物品库登记物品或保存普通文本事项。
- **库存不足预警**：携带数量超过当前库存储备时即时高亮预警，但不阻断保存。
- **智能排序与最近使用**：支持上下排序与最近使用时间追踪。

### 4. 本次出门任务生命周期
- **灵活创建**：支持从既有模板一键复制衍生，也支持随时即兴直接新建任务。
- **任务隔离**：各进行中任务状态完全独立，勾选状态即刻本地持久化。
- **不可逆历史快照**：完成出行任务时，系统冻结包含物品名称、数量、完整位置路径在内的全量快照。已完成历史记录**不可修改、不可删除**。
- **整组编辑与确认删除**：进行中任务支持安全重排与编辑；经二次确认后可永久删除进行中记录，不留冗余脏数据。

### 5. 首页综合仪表盘
- **全局搜索直达**：首页顶部提供全局物品与收纳位置快速搜索栏。
- **进行中任务看板**：卡片式展示当前未完成任务、准备进度条及待办计数。
- **常用模板磁贴**：按最近使用时间智能展示模板列表，支持一键发起出行。

---

## 应用架构与技术选型

- **UI 框架**：Flutter 3.47.6 (Material 3 设计语言，采用古典深青绿与沉稳雅金视觉规范)
- **状态管理**：Riverpod 3.x (无缝解耦 UI 表现层与领域逻辑)
- **路由导航**：go_router (声明式路由，支持三栏底部导航与状态恢复)
- **本地存储**：SQLite 3 + Drift 2.35
  - 严格启用 SQLite 外键级联约束与唯一索引；
  - 核心业务流全部由 Repository ACID 事务保障；
  - 隔离测试数据库与生产单例 `AppDatabase`。
- **三大一级导航模块**：
  1. **首页 (`/home`)**：全局搜索、进行中任务跟踪、最近模板磁贴；
  2. **物品 (`/items`)**：收纳位置层级树逐级导航、物品登记、编辑与跨位置移动；
  3. **出门 (`/outings`)**：进行中出行核验清单、出门模板管理与详情。

---

## 离线安全与系统备份策略

《玉简行录》恪守极简与隐私第一原则：

1. **零网络权限**：Android Manifest 中不声明任何互联网网络访问权限（无 `INTERNET` 权限），物理级杜绝任何远程遥测或私密数据上传。
2. **禁用云端自动备份**：
   - `AndroidManifest.xml` 配置 `android:allowBackup="false"`；
   - 依据 Android 12+ 规范配置 `data_extraction_rules.xml`，全面禁用 `cloud-backup` 与 `device-transfer`；
   - 依据 Android 11 及以下规范配置 `backup_rules.xml`，全面排除所有存储域（databases, sharedpref, files, root 等）。
   保证用户的物理空间物品隐私绝对驻留在个人设备。

---

## 开源许可证 (License) & 知识产权声明

### 1. 源代码许可证
本项目源代码遵循 **[MIT License](LICENSE)**，版权所有 (c) 2026 **huaishiW**。

### 2. 品牌与图标视觉素材保留权利 (All Rights Reserved)
项目名称 **“玉简行录” (Yujianxinglu)**、应用桌面图标、启动屏视觉设计以及位于 `assets/branding/` 目录下的所有图像素材的版权由作者 **huaishiW** 独家保留（All Rights Reserved）。

上述品牌资产不包含在 MIT License 授权范围内。未经作者事先书面许可，任何个人或组织不得将这些视觉素材或“玉简行录”品牌标识用于商业软件发行、二次打包分发或衍生产品的商业宣传。
