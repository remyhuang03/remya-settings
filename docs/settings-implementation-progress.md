# 设置功能实现进度清单

目录基线：2026-10-26；清单建立：2026-10-26。

本清单逐项对应 [设置目录](../assets/settings/catalog.json)，用于后续接入 Hyprland / Linux 系统功能时跟踪进度。页面已能打开、控件已能显示，不代表其系统功能已经实现。

清单覆盖现有目录中的全部设置项，包括主要中文控件和保留原名的 Windows 参考细项；相同概念可能存在多个展示位置。下述数量统计的是控件条目，不是去重后的独立后端功能数量。公开资料与内部 schema 的边界见 [调研说明](windows-settings-research.md)。

## 当前概况

- 设置分类：11 个；详情页面：202 个；设置条目：1,321 项。
- 系统功能已实现：0 项；未实现：1,162 项；不适用：159 项。
- 本阶段没有系统设置读写、设备扫描、服务调用或预览值持久化。所有设备名称、选项和值均为界面示例。

### 已完成的界面能力（不计入系统功能进度）

- [x] 首页、分类侧栏、窄屏抽屉与自适应布局。
- [x] 按页面、设置名称和参考 URI 进行本地搜索。
- [x] 面包屑、返回、相关页面跳转及参考细项展开。
- [x] 已实现 / 未实现 / 不适用的文字、图标和控件禁用状态。
- [x] 应用图标、About、版本和仓库信息。
- [x] 项目许可证及第三方许可查看。

## 状态与记录方式

| 状态 | 含义 | 何时更新 |
| --- | --- | --- |
| 未实现 | 仅有界面，尚未接入对应系统能力 | 实现真实读取 / 修改或明确的只读查询，完成错误处理和相关验证后再更新 |
| 已实现 | 已接入可用的真实系统功能，并有验证依据 | 在“跟踪 / 验证”中记录提交、问题单、测试或实机验证记录 |
| 不适用 | Windows 专属、旧版或当前平台没有确定对应能力 | 保留条目；确认 Linux 替代方案后，记录决策并改为未实现 |

实现一个小项时，同步更新本表与目录中的 `availability` / `reason`，并更新页面汇总状态；不能只修改徽标或让示例控件响应。部分完成的页面应保持未实现，逐项记录已接入能力。使用稳定 ID 对齐记录，不因重命名、翻译或排序而修改 ID。新增或删除控件时也同步清单与分类统计；保留已有跟踪和验证记录。

同一后端能力服务多个展示条目时，逐个登记所覆盖的 ID，并链接同一实现与验证依据。`不适用` 不代表承诺实现 Windows 服务；是否纳入 Hyprland 的产品范围需要另作决定。参考区域的选项和范围仍需在接入时核实。

## 分类索引与统计

| 分类 | 页面 | 条目 | 已实现 | 未实现 | 不适用 |
| --- | ---: | ---: | ---: | ---: | ---: |
| [系统](#category-system) | 43 | 274 | 0 | 254 | 20 |
| [蓝牙和设备](#category-devices) | 13 | 105 | 0 | 101 | 4 |
| [网络和 Internet](#category-network) | 15 | 90 | 0 | 88 | 2 |
| [个性化](#category-personalization) | 15 | 129 | 0 | 119 | 10 |
| [应用](#category-apps) | 9 | 45 | 0 | 45 | 0 |
| [账户](#category-accounts) | 19 | 78 | 0 | 59 | 19 |
| [时间和语言](#category-time) | 16 | 103 | 0 | 48 | 55 |
| [游戏](#category-gaming) | 5 | 29 | 0 | 25 | 4 |
| [辅助功能](#category-accessibility) | 15 | 242 | 0 | 242 | 0 |
| [隐私和安全性](#category-privacy) | 42 | 179 | 0 | 151 | 28 |
| [系统更新](#category-update) | 10 | 47 | 0 | 30 | 17 |

<a id="category-system"></a>

## 系统

显示、声音、通知与电源

### 显示 — `display`

亮度、缩放、显示器排列与图形

页面状态：**未实现**；条目：20；已实现 0 / 未实现 20 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:display`、`ms-settings:screenrotation`。

相关页面 ID：`night-light`、`advanced-display`、`graphics`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 亮度 | `display.5d419889` | 滑块 | 未实现 | — |
| 根据内容调整亮度 | `display.4686de0d` | 开关 | 未实现 | — |
| 夜间模式 | `display.e32be03e` | 操作 | 未实现 | — |
| 颜色配置文件 | `display.af8e280d` | 选择 | 未实现 | — |
| HDR | `display.0ce92088` | 开关 | 未实现 | — |

#### 缩放和布局

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 缩放 | `display.12e2ed4d` | 选择 | 未实现 | — |
| 显示分辨率 | `display.44f6b9b0` | 选择 | 未实现 | — |
| 显示方向 | `display.9843ad76` | 选择 | 未实现 | — |
| 多显示器 | `display.7cb5dc06` | 选择 | 未实现 | — |
| 检测其他显示器 | `display.15697afc` | 操作 | 未实现 | — |

#### 相关设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 高级显示 | `display.2d0b8c7d` | 操作 | 未实现 | — |
| 图形 | `display.2f32a8c2` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Display › Multiple displays › Remember window locations based on monitor connection | `display.reference.45daf28f` | 开关 | 未实现 | — |
| Display › Multiple displays › Minimize windows when a monitor is disconnected | `display.reference.b0b25287` | 开关 | 未实现 | — |
| Display › Multiple displays › Ease cursor movement between displays | `display.reference.9c5f075f` | 开关 | 未实现 | — |
| Display › Night Light › Show warmer colors on your display to help you sleep | `display.reference.5106967a` | 选择 | 未实现 | — |
| Display › Night Light › Strength | `display.reference.b55908e7` | 开关 | 未实现 | — |
| Display › Night Light › Schedule Night Light | `display.reference.613ad1ca` | 开关 | 未实现 | — |
| Display › Night Light › Sunset to sunrise/ Set hours (Actual sunrise / sunset time depends on location) › Turn on | `display.reference.a303e647` | 开关 | 未实现 | — |
| Display › Night Light › Sunset to sunrise/ Set hours (Actual sunrise / sunset time depends on location) › Turn off | `display.reference.0d998610` | 开关 | 未实现 | — |

### 高级显示 — `advanced-display`

显示器信息、刷新率与动态刷新率

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:display-advanced`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 桌面模式 | `advanced-display.3b3ebb60` | 信息展示 | 未实现 | — |
| 活动信号模式 | `advanced-display.761b7ac8` | 信息展示 | 未实现 | — |
| 位深度 | `advanced-display.91720250` | 信息展示 | 未实现 | — |
| 色彩空间 | `advanced-display.3278abf9` | 信息展示 | 未实现 | — |
| 选择刷新率 | `advanced-display.34d8396d` | 选择 | 未实现 | — |
| 动态刷新率 | `advanced-display.2d80c2c4` | 开关 | 未实现 | — |

### 夜间模式 — `night-light`

暖色显示与时间安排

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:nightlight`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 夜间模式 | `night-light.e32be03e` | 开关 | 未实现 | — |
| 强度 | `night-light.2fa4c751` | 滑块 | 未实现 | — |
| 安排夜间模式 | `night-light.7e6239c9` | 开关 | 未实现 | — |
| 时间安排 | `night-light.50840111` | 选择 | 未实现 | — |
| 开始时间 | `night-light.e8868af6` | 文本输入 | 未实现 | — |
| 结束时间 | `night-light.a0bb9f49` | 文本输入 | 未实现 | — |

### 图形 — `graphics`

默认图形选项与每应用 GPU 偏好

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:display-advancedgraphics`、`ms-settings:display-advancedgraphics-default`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 窗口化游戏优化 | `graphics.66507566` | 开关 | 未实现 | — |
| 硬件加速 GPU 调度 | `graphics.c76f798a` | 开关 | 未实现 | — |
| 可变刷新率 | `graphics.4ee2d0bc` | 开关 | 未实现 | — |
| 添加桌面应用 | `graphics.f6aaf67c` | 操作 | 未实现 | — |
| 添加应用商店应用 | `graphics.232eb7f3` | 操作 | 未实现 | — |
| 应用 GPU 首选项 | `graphics.49ad9ee9` | 选择 | 未实现 | — |

### 声音 — `sound`

输出、输入与应用音量

页面状态：**未实现**；条目：11；已实现 0 / 未实现 11 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:sound`。

相关页面 ID：`sound-devices`、`volume-mixer`、`audio-output`、`audio-input`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 选择输出设备 | `sound.df22d19a` | 选择 | 未实现 | — |
| 输出音量 | `sound.b6723f8d` | 滑块 | 未实现 | — |
| 单声道音频 | `sound.1a90a9eb` | 开关 | 未实现 | — |
| 所有声音设备 | `sound.83c3c324` | 操作 | 未实现 | — |

#### 输入

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 选择输入设备 | `sound.b456670c` | 选择 | 未实现 | — |
| 输入音量 | `sound.6d541e81` | 滑块 | 未实现 | — |
| 测试麦克风 | `sound.8714d013` | 操作 | 未实现 | — |

#### 高级

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 音量合成器 | `sound.9146f08b` | 操作 | 未实现 | — |
| 更多声音设置 | `sound.494f3460` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Sound › Mono audio | `sound.reference.523e7f5c` | 开关 | 未实现 | — |
| Sound › More sound settings > Sounds [Program Events] (Windows default sounds) | `sound.reference.a9568fa7` | 操作 | 未实现 | — |

### 音量合成器 — `volume-mixer`

系统音量与每应用路由

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:apps-volume`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 系统音量 | `volume-mixer.d17879a4` | 滑块 | 未实现 | — |
| 输出设备 | `volume-mixer.3aa83c30` | 选择 | 未实现 | — |
| 输入设备 | `volume-mixer.c15e3367` | 选择 | 未实现 | — |
| 示例应用音量 | `volume-mixer.ef9d857c` | 滑块 | 未实现 | — |
| 将声音设备和音量重置为推荐值 | `volume-mixer.42141672` | 操作 | 未实现 | — |

### 所有声音设备 — `sound-devices`

输出和输入设备目录

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:sound-devices`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 扬声器属性 | `sound-devices.507f1aa5` | 操作 | 未实现 | — |
| 耳机属性 | `sound-devices.4119daae` | 操作 | 未实现 | — |
| 麦克风属性 | `sound-devices.9b818984` | 操作 | 未实现 | — |
| 添加声音设备 | `sound-devices.91c56260` | 操作 | 未实现 | — |

### 输出设备属性 — `audio-output`

格式、增强与空间音效

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:sound-defaultoutputproperties`、`ms-settings:sound-properties`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 允许此设备用于音频 | `audio-output.2c45320f` | 操作 | 未实现 | — |
| 格式 | `audio-output.9d2601c8` | 选择 | 未实现 | — |
| 左声道音量 | `audio-output.74e9cee2` | 滑块 | 未实现 | — |
| 右声道音量 | `audio-output.19521017` | 滑块 | 未实现 | — |
| 音频增强 | `audio-output.48bde259` | 选择 | 未实现 | — |
| 空间音效 | `audio-output.f6e78b36` | 选择 | 未实现 | — |
| 测试声音 | `audio-output.540eb103` | 操作 | 未实现 | — |

### 输入设备属性 — `audio-input`

麦克风格式、音量与测试

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:sound-defaultinputproperties`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 允许应用使用麦克风 | `audio-input.0b48b921` | 操作 | 未实现 | — |
| 格式 | `audio-input.9d2601c8` | 选择 | 未实现 | — |
| 输入音量 | `audio-input.6d541e81` | 滑块 | 未实现 | — |
| 开始麦克风测试 | `audio-input.1eeef8e1` | 操作 | 未实现 | — |
| 麦克风增强 | `audio-input.519e7157` | 选择 | 未实现 | — |

### 通知 — `notifications`

应用通知、免打扰与优先级

页面状态：**未实现**；条目：24；已实现 0 / 未实现 24 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:notifications`。

相关页面 ID：`quiet-schedule`、`priority-notifications`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 通知 | `notifications.7a66c0d0` | 开关 | 未实现 | — |
| 允许通知播放声音 | `notifications.e0ab8430` | 开关 | 未实现 | — |
| 锁屏通知 | `notifications.4a3428cc` | 开关 | 未实现 | — |
| 锁屏提醒和来电 | `notifications.d6aba528` | 开关 | 未实现 | — |
| 显示通知铃铛图标 | `notifications.d503fb54` | 开关 | 未实现 | — |

#### 免打扰

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 请勿打扰 | `notifications.a04cba4d` | 开关 | 未实现 | — |
| 自动开启请勿打扰 | `notifications.7abaf526` | 操作 | 未实现 | — |
| 设置优先通知 | `notifications.5ca577ba` | 操作 | 未实现 | — |

#### 其他设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 更新后显示欢迎体验 | `notifications.d04ff1cd` | 开关 | 未实现 | — |
| 使用系统时获取提示和建议 | `notifications.bf018b80` | 开关 | 未实现 | — |
| 屏幕指示器位置 | `notifications.af16c789` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Notifications › Notifications › Allow notifications to play sounds | `notifications.reference.da472fb3` | 开关 | 未实现 | — |
| Notifications › Notifications › Show notifications on the lock screen | `notifications.reference.c7fafa9e` | 开关 | 未实现 | — |
| Notifications › Notifications › Show reminders and incoming VoIP calls on the lock screen | `notifications.reference.1517c6c9` | 开关 | 未实现 | — |
| Notifications › Notifications › Show notification bell icon | `notifications.reference.d08d71db` | 开关 | 未实现 | — |
| Notifications › Do not disturb | `notifications.reference.30527137` | 开关 | 未实现 | — |
| Notifications › Turn on do not disturb automatically › During these times | `notifications.reference.40e74cde` | 选择 | 未实现 | — |
| Notifications › Turn on do not disturb automatically › When duplicating your display (priority notification banners are also hidden) | `notifications.reference.1c052cd8` | 开关 | 未实现 | — |
| Notifications › Turn on do not disturb automatically › When playing a game | `notifications.reference.210adac4` | 开关 | 未实现 | — |
| Notifications › Turn on do not disturb automatically › When using an app in full-screen mode (priority notification banners are also hidden) | `notifications.reference.3554d597` | 选择 | 未实现 | — |
| Notifications › Turn on do not disturb automatically › For the first hour after a Windows feature update | `notifications.reference.3d050709` | 开关 | 未实现 | — |
| Notifications › Set Priority Notifications › Calls and reminders › Show incoming calls, including VoIP | `notifications.reference.beb97dd8` | 开关 | 未实现 | — |
| Notifications › Set Priority Notifications › Calls and reminders › Show reminders, regardless of app used | `notifications.reference.8ad51f25` | 开关 | 未实现 | — |
| Notifications › Set Priority Notifications › Apps | `notifications.reference.7e9418df` | 开关 | 未实现 | — |

### 专注 — `focus`

专注时段与减少干扰

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:quiethours`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 时段持续时间 | `focus.9eac723a` | 选择 | 未实现 | — |
| 开始专注时段 | `focus.e9d3186d` | 操作 | 未实现 | — |
| 显示计时器 | `focus.72877c30` | 开关 | 未实现 | — |
| 隐藏任务栏应用徽章 | `focus.4c84c9c8` | 开关 | 未实现 | — |
| 隐藏任务栏闪烁 | `focus.18b69b82` | 开关 | 未实现 | — |
| 开启请勿打扰 | `focus.fadd18ca` | 开关 | 未实现 | — |

### 自动免打扰 — `quiet-schedule`

时间、全屏与演示条件

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:quietmomentsscheduled`、`ms-settings:quietmomentspresentation`、`ms-settings:quietmomentsgame`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 在这些时间段 | `quiet-schedule.a4bf60fc` | 开关 | 未实现 | — |
| 复制显示器时 | `quiet-schedule.00e784e0` | 开关 | 未实现 | — |
| 玩游戏时 | `quiet-schedule.00e302dd` | 开关 | 未实现 | — |
| 应用处于全屏模式时 | `quiet-schedule.98b0a144` | 开关 | 未实现 | — |
| 系统更新后的第一个小时 | `quiet-schedule.52bb4227` | 开关 | 未实现 | — |
| 开始时间 | `quiet-schedule.e8868af6` | 文本输入 | 未实现 | — |
| 结束时间 | `quiet-schedule.a0bb9f49` | 文本输入 | 未实现 | — |
| 重复 | `quiet-schedule.6e708ba7` | 选择 | 未实现 | — |

### 优先通知 — `priority-notifications`

来电、提醒与例外应用

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 显示来电通知 | `priority-notifications.79d29523` | 开关 | 未实现 | — |
| 始终显示提醒 | `priority-notifications.64f96963` | 开关 | 未实现 | — |
| 添加优先应用 | `priority-notifications.c4e0313c` | 操作 | 未实现 | — |

### 电源和电池 — `power`

能耗、屏幕超时与电池

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:powersleep`。

相关页面 ID：`battery-saver`、`battery-usage`、`energy`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 电源模式 | `power.5a4f0131` | 选择 | 未实现 | — |
| 关闭屏幕时间 | `power.5e3af39c` | 选择 | 未实现 | — |
| 睡眠时间 | `power.8b4c8522` | 选择 | 未实现 | — |
| 节能模式 | `power.743773bd` | 操作 | 未实现 | — |
| 电池使用情况 | `power.03bd05ee` | 操作 | 未实现 | — |
| 能源建议 | `power.de734a46` | 操作 | 未实现 | — |
| 视频播放电池优化 | `power.f5cbd1dc` | 开关 | 未实现 | — |

### 节能模式 — `battery-saver`

节能策略与自动启用阈值

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:batterysaver`、`ms-settings:batterysaver-settings`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 节能模式 | `battery-saver.743773bd` | 开关 | 未实现 | — |
| 自动开启条件 | `battery-saver.9b0caf70` | 选择 | 未实现 | — |
| 节能时降低屏幕亮度 | `battery-saver.07945503` | 开关 | 未实现 | — |

### 电池使用情况 — `battery-usage`

电量历史与每应用耗电

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:batterysaver-usagedetails`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 时间范围 | `battery-usage.2be90408` | 选择 | 未实现 | — |
| 屏幕开启时间 | `battery-usage.37bfb377` | 信息展示 | 未实现 | — |
| 屏幕关闭时间 | `battery-usage.1aa63c64` | 信息展示 | 未实现 | — |
| 休眠时间 | `battery-usage.adee81f9` | 信息展示 | 未实现 | — |
| 每应用电池用量 | `battery-usage.68bac7d6` | 信息展示 | 未实现 | — |

### 能源建议 — `energy`

屏幕、睡眠和能耗建议

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:energyrecommendations`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 应用全部建议 | `energy.08ce1ee7` | 操作 | 未实现 | — |
| 调整屏幕亮度 | `energy.0e3095cb` | 操作 | 未实现 | — |
| 调整屏幕关闭时间 | `energy.60d9d90f` | 操作 | 未实现 | — |
| 调整睡眠时间 | `energy.066b21ab` | 操作 | 未实现 | — |
| 优化电源模式 | `energy.bfee6a15` | 操作 | 未实现 | — |

### 存储 — `storage`

空间使用、磁盘与清理

页面状态：**未实现**；条目：10；已实现 0 / 未实现 10 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:storagesense`。

相关页面 ID：`storage-sense`、`cleanup`、`disks`、`save-locations`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 磁盘空间使用 | `storage.bbb5f514` | 信息展示 | 未实现 | — |
| 已安装的应用 | `storage.10396df3` | 操作 | 未实现 | — |
| 临时文件 | `storage.ae5af853` | 操作 | 未实现 | — |
| 文档和其他文件 | `storage.fa08c5fa` | 操作 | 未实现 | — |
| 存储感知 | `storage.008cbe6b` | 操作 | 未实现 | — |
| 清理建议 | `storage.77572238` | 操作 | 未实现 | — |

#### 高级存储设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 磁盘和卷 | `storage.d37bbd44` | 操作 | 未实现 | — |
| 新内容的保存位置 | `storage.e4a69938` | 操作 | 未实现 | — |
| 存储空间 | `storage.89266e3e` | 操作 | 未实现 | — |
| 驱动器优化 | `storage.3236decd` | 操作 | 未实现 | — |

### 存储感知 — `storage-sense`

自动清理与内容保留

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:storagepolicies`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 自动清理临时文件 | `storage-sense.ed72cc7f` | 开关 | 未实现 | — |
| 存储感知 | `storage-sense.008cbe6b` | 开关 | 未实现 | — |
| 运行频率 | `storage-sense.9ea4e59f` | 选择 | 未实现 | — |
| 回收站保留时间 | `storage-sense.c550ab3e` | 选择 | 未实现 | — |
| 下载目录保留时间 | `storage-sense.e91a10f8` | 选择 | 未实现 | — |
| 立即运行 | `storage-sense.275f9972` | 操作 | 未实现 | — |

### 清理建议 — `cleanup`

临时文件、大文件与未使用内容

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:storagerecommendations`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 临时文件 | `cleanup.ae5af853` | 操作 | 未实现 | — |
| 大型或未使用文件 | `cleanup.c17cc68a` | 操作 | 未实现 | — |
| 同步到云的文件 | `cleanup.c05f77b2` | 操作 | 未实现 | — |
| 未使用的应用 | `cleanup.44263144` | 操作 | 未实现 | — |
| 清理选定项目 | `cleanup.679f2d39` | 操作 | 未实现 | — |

### 磁盘和卷 — `disks`

磁盘、分区与卷属性

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:disksandvolumes`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 磁盘目录 | `disks.41d009d9` | 信息展示 | 未实现 | — |
| 卷属性 | `disks.58e6fc20` | 操作 | 未实现 | — |
| 更改卷标 | `disks.5bf6fb0d` | 操作 | 未实现 | — |
| 更改驱动器号 | `disks.d324d258` | 操作 | 未实现 | — |
| 调整卷大小 | `disks.6e9cf764` | 操作 | 未实现 | — |
| 格式化卷 | `disks.c1481df0` | 操作 | 未实现 | — |

### 新内容的保存位置 — `save-locations`

应用与文件的默认目标

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:savelocations`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 新应用 | `save-locations.fa399053` | 选择 | 未实现 | — |
| 新文档 | `save-locations.232eacc2` | 选择 | 未实现 | — |
| 新音乐 | `save-locations.92016bde` | 选择 | 未实现 | — |
| 新照片和视频 | `save-locations.0e457e66` | 选择 | 未实现 | — |
| 新电影和电视节目 | `save-locations.e6a0ecd7` | 选择 | 未实现 | — |
| 离线地图 | `save-locations.cfd0f9eb` | 选择 | 未实现 | — |

### 附近共享 — `nearby`

设备发现、共享范围与接收目录

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:crossdevice`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 附近共享 | `nearby.27459ca2` | 选择 | 未实现 | — |
| 设备名称 | `nearby.4433eb13` | 文本输入 | 未实现 | — |
| 接收文件位置 | `nearby.7436bca6` | 文本输入 | 未实现 | — |
| 更改保存目录 | `nearby.e04563a3` | 操作 | 未实现 | — |

### 多任务处理 — `multitasking`

窗口排列、工作区与切换

页面状态：**未实现**；条目：17；已实现 0 / 未实现 17 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:multitasking`、`ms-settings:multitasking-sgupdate`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 贴靠窗口 | `multitasking.789ebfe1` | 开关 | 未实现 | — |
| 贴靠时显示窗口建议 | `multitasking.49b7cb6a` | 开关 | 未实现 | — |
| 悬停最大化按钮时显示布局 | `multitasking.335ca0a4` | 开关 | 未实现 | — |
| 拖到屏幕顶部时显示布局 | `multitasking.5d8590f9` | 开关 | 未实现 | — |
| Alt + Tab 中的标签页 | `multitasking.11f8a9c1` | 选择 | 未实现 | — |

#### 桌面

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 任务栏窗口范围 | `multitasking.6b3b6f33` | 选择 | 未实现 | — |
| Alt + Tab 窗口范围 | `multitasking.88acef48` | 选择 | 未实现 | — |
| 标题栏窗口摇动 | `multitasking.3930eac4` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Multitasking › Snap Windows › When I snap a window, suggest what I can snap next to it | `multitasking.reference.1f0fd68e` | 开关 | 未实现 | — |
| Multitasking › Snap Windows › Show snap layouts when I hover over a window's maximize button | `multitasking.reference.7eb36360` | 选择 | 未实现 | — |
| Multitasking › Snap Windows › Show snap layouts when I drag a window to the top of my screen | `multitasking.reference.6adfd906` | 选择 | 未实现 | — |
| Multitasking › Snap Windows › Show tabs from apps when snapping or pressing Alt+Tab | `multitasking.reference.b64a018f` | 开关 | 未实现 | — |
| Multitasking › Snap Windows › Show my snapped windows when I hover over taskbar apps, in Task View, and when I press Alt+Tab | `multitasking.reference.22d30ff1` | 开关 | 未实现 | — |
| Multitasking › Snap Windows › When I drag a window, let me snap it without dragging all the way to the screen edge | `multitasking.reference.35f7e68f` | 开关 | 未实现 | — |
| Multitasking › Desktops › On the task, show all the open windows | `multitasking.reference.c8540ba4` | 开关 | 未实现 | — |
| Multitasking › Desktops › Show all open windows when I press Alt+Tab | `multitasking.reference.2d6a63c7` | 开关 | 未实现 | — |
| Multitasking › Title bar window shake | `multitasking.reference.301a71a1` | 开关 | 未实现 | — |

### 激活 — `activation`

Windows 许可证与产品密钥参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:activation`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 激活状态 | `activation.b71fc2ba` | 信息展示 | 不适用 | — |
| 更改产品密钥 | `activation.5426ec32` | 操作 | 不适用 | — |
| 升级系统版本 | `activation.8e3c56ea` | 操作 | 不适用 | — |

### 疑难解答 — `troubleshoot`

推荐的诊断与其他疑难解答

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:troubleshoot`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 诊断运行方式 | `troubleshoot.c521689a` | 选择 | 未实现 | — |
| 其他疑难解答 | `troubleshoot.4b4b161e` | 操作 | 未实现 | — |
| 诊断历史记录 | `troubleshoot.f08a49da` | 操作 | 未实现 | — |

### 恢复 — `recovery`

恢复选项与高级启动

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:recovery`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 修复系统问题 | `recovery.03ea91ae` | 操作 | 未实现 | — |
| 重置此电脑 | `recovery.631b3905` | 操作 | 未实现 | — |
| 返回上一版本 | `recovery.f1b586da` | 操作 | 未实现 | — |
| 高级启动 | `recovery.b85853c3` | 操作 | 未实现 | — |
| 快速计算机恢复 | `recovery.8d2d42f1` | 操作 | 未实现 | — |

### 投影到此电脑 — `projection`

无线显示与投影许可

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:project`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 允许投影 | `projection.ec71f569` | 选择 | 未实现 | — |
| 请求投影确认 | `projection.d8103e93` | 选择 | 未实现 | — |
| 要求 PIN | `projection.7d2dd2be` | 选择 | 未实现 | — |
| 仅接通电源时可发现 | `projection.80db4c9e` | 开关 | 未实现 | — |
| 安装无线显示 | `projection.6e4baff3` | 操作 | 未实现 | — |

### 远程桌面 — `remote-desktop`

远程访问与允许的用户

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:remotedesktop`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 启用远程桌面 | `remote-desktop.308c8bda` | 开关 | 未实现 | — |
| 要求网络级别身份验证 | `remote-desktop.0d46b931` | 开关 | 未实现 | — |
| 电脑名称 | `remote-desktop.2f2f4cf1` | 信息展示 | 未实现 | — |
| 远程桌面用户 | `remote-desktop.ddee4fd6` | 操作 | 未实现 | — |

### 剪贴板 — `clipboard`

历史记录、同步与清除

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:clipboard`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 剪贴板历史记录 | `clipboard.1e42405e` | 开关 | 未实现 | — |
| 跨设备同步 | `clipboard.71367ff3` | 开关 | 未实现 | — |
| 同步方式 | `clipboard.3cc9cef1` | 选择 | 未实现 | — |
| 清除剪贴板数据 | `clipboard.5593d4e3` | 操作 | 未实现 | — |

### 存在感应 — `presence`

离开锁定与接近唤醒

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:presence`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 离开时关闭屏幕 | `presence.bc279609` | 开关 | 未实现 | — |
| 接近时唤醒设备 | `presence.5641252e` | 开关 | 未实现 | — |
| 看向别处时调暗屏幕 | `presence.b9bc699d` | 开关 | 未实现 | — |
| 离开检测距离 | `presence.fb638054` | 选择 | 未实现 | — |
| 锁定延迟 | `presence.043eb133` | 选择 | 未实现 | — |

### 系统信息 — `about`

设备规格、系统版本与相关信息

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:about`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 设备名称 | `about.4433eb13` | 信息展示 | 未实现 | — |
| 处理器 | `about.b4366749` | 信息展示 | 未实现 | — |
| 内存 | `about.d014ab77` | 信息展示 | 未实现 | — |
| 系统类型 | `about.96af9884` | 信息展示 | 未实现 | — |
| 操作系统版本 | `about.d0a7f225` | 信息展示 | 未实现 | — |
| 设备标识符 | `about.5da0260f` | 信息展示 | 未实现 | — |
| 重命名设备 | `about.0f142010` | 操作 | 未实现 | — |
| 高级系统设置 | `about.92d0cfd9` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| About › Rename this PC | `about.reference.9cc38bce` | 操作 | 未实现 | — |

### 高级设置 — `advanced`

开发工具、终端与文件管理器参考

页面状态：**未实现**；条目：14；已实现 0 / 未实现 14 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:developers`。

相关页面 ID：`file-explorer`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 开发者模式 | `advanced.16ab0c5a` | 开关 | 未实现 | — |
| 设备门户 | `advanced.da8193cc` | 开关 | 未实现 | — |
| 设备发现 | `advanced.cb620100` | 开关 | 未实现 | — |
| 默认终端 | `advanced.216f8db4` | 选择 | 未实现 | — |
| 启用 sudo | `advanced.809d3128` | 开关 | 未实现 | — |
| 长路径支持 | `advanced.d2ec4f10` | 开关 | 未实现 | — |
| 任务栏结束任务 | `advanced.d68b8048` | 开关 | 未实现 | — |
| 文件资源管理器选项 | `advanced.001394d6` | 操作 | 未实现 | — |
| 虚拟工作区 | `advanced.daee0454` | 操作 | 未实现 | — |
| Dev Drive | `advanced.80afb07b` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| For Developers › File Explorer › Show file extensions | `advanced.reference.96b6fa8d` | 开关 | 未实现 | — |
| For Developers › File Explorer › Show hidden and system files | `advanced.reference.f09f62a2` | 开关 | 未实现 | — |
| For Developers › File Explorer › Show full path in title bar | `advanced.reference.d6ad9b0f` | 开关 | 未实现 | — |
| For Developers › File Explorer › Show empty drives | `advanced.reference.4c7d62c7` | 开关 | 未实现 | — |

### 文件管理器选项 — `file-explorer`

文件显示与版本控制参考

页面状态：**未实现**；条目：20；已实现 0 / 未实现 20 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 显示文件扩展名 | `file-explorer.aae5a85e` | 开关 | 未实现 | — |
| 显示隐藏和系统文件 | `file-explorer.548c9a49` | 开关 | 未实现 | — |
| 标题栏显示完整路径 | `file-explorer.a484d4f3` | 开关 | 未实现 | — |
| 显示空驱动器 | `file-explorer.e0952b14` | 开关 | 未实现 | — |
| 显示以其他用户身份运行 | `file-explorer.7a72391c` | 开关 | 未实现 | — |
| 显示复选框 | `file-explorer.32a40852` | 开关 | 未实现 | — |
| 紧凑视图 | `file-explorer.e2ebcb73` | 开关 | 未实现 | — |
| 删除确认 | `file-explorer.726b6ec5` | 开关 | 未实现 | — |
| 打开项目方式 | `file-explorer.de1fb32c` | 选择 | 未实现 | — |
| 版本控制集成 | `file-explorer.b3551149` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Single click to open an item (point to select): Underline icon titles/Double click to open an item (single-click to select) | `file-explorer.reference.afe7ff09` | 选择 | 未实现 | — |
| Decrease space between items (compact view) | `file-explorer.reference.7ec40057` | 开关 | 未实现 | — |
| Display the full path in the title bar | `file-explorer.reference.d37f9e0c` | 开关 | 未实现 | — |
| Hidden files and folders: Don't show hidden files, folders, or drives/Show hidden files, folders, and drives | `file-explorer.reference.13fc4541` | 开关 | 未实现 | — |
| Hide empty drives | `file-explorer.reference.b49d9a75` | 开关 | 未实现 | — |
| Hide extensions for known file Types | `file-explorer.reference.67cc9b59` | 开关 | 未实现 | — |
| Use check box to select items | `file-explorer.reference.485b9758` | 开关 | 未实现 | — |
| Recyle bin › Display delete confirmation dialog | `file-explorer.reference.163ce553` | 开关 | 未实现 | — |
| Desktop › View (Icon size, Auto arrange icons, Show desktop icons) | `file-explorer.reference.f24ca65a` | 选择 | 未实现 | — |
| Desktop › Sort by (Name, Size, Item type, Date modified) | `file-explorer.reference.ed11d482` | 选择 | 未实现 | — |

### 控制中心 — `controlcenter`

Windows 快速设置参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:controlcenter`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 编辑快速设置 | `controlcenter.13fd7d4b` | 操作 | 不适用 | — |
| 显示快速操作 | `controlcenter.d8e92750` | 开关 | 不适用 | — |

### 附加设置 — `extras`

Windows OEM 或扩展应用设置参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:extras`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 扩展设置提供者 | `extras.b24f2fc7` | 信息展示 | 不适用 | — |
| 管理扩展设置 | `extras.a049a211` | 操作 | 不适用 | — |

### 混合现实音频和语音 — `holographic-audio`

Windows Mixed Reality 参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:holographic-audio`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 切换到头显音频 | `holographic-audio.53f5cfbb` | 开关 | 不适用 | — |
| 使用头显麦克风 | `holographic-audio.f0145c7a` | 开关 | 不适用 | — |
| 语音识别 | `holographic-audio.df3dd6ab` | 开关 | 不适用 | — |

### 混合现实环境 — `privacy-holographic-environment`

Windows Mixed Reality 参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-holographic-environment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 清除环境数据 | `privacy-holographic-environment.839199fb` | 操作 | 不适用 | — |
| 重置边界 | `privacy-holographic-environment.d7b104e0` | 操作 | 不适用 | — |

### 混合现实头戴显示器 — `holographic-headset`

Windows Mixed Reality 参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:holographic-headset`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 视觉质量 | `holographic-headset.d62dba30` | 选择 | 不适用 | — |
| 刷新率 | `holographic-headset.7bb8bba2` | 选择 | 不适用 | — |
| 校准显示器 | `holographic-headset.c5d62d7f` | 操作 | 不适用 | — |

### 卸载混合现实 — `holographic-management`

Windows Mixed Reality 参考

页面状态：**不适用**；条目：1；已实现 0 / 未实现 0 / 不适用 1。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:holographic-management`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 卸载混合现实 | `holographic-management.63443c74` | 操作 | 不适用 | — |

### 混合现实启动和桌面 — `holographic-startupandesktop`

Windows Mixed Reality 参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:holographic-startupandesktop`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 连接头显时启动 | `holographic-startupandesktop.fb8aa3ee` | 开关 | 不适用 | — |
| 启用虚拟桌面 | `holographic-startupandesktop.701239cf` | 开关 | 不适用 | — |

### 平板模式 — `tabletmode`

旧版页面，仅保留参考

页面状态：**不适用**；条目：1；已实现 0 / 未实现 0 / 不适用 1。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:tabletmode`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 功能状态 | `tabletmode.540cc78d` | 信息展示 | 不适用 | — |

### 电话 — `phone`

旧版页面，仅保留参考

页面状态：**不适用**；条目：1；已实现 0 / 未实现 0 / 不适用 1。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:phone`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 功能状态 | `phone.540cc78d` | 信息展示 | 不适用 | — |


<a id="category-devices"></a>

## 蓝牙和设备

连接设备、输入与外设

### 蓝牙 — `bluetooth`

蓝牙开关、配对与设备目录

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:bluetooth`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 蓝牙 | `bluetooth.c4dc12d3` | 开关 | 未实现 | — |
| 添加蓝牙设备 | `bluetooth.9bf543c2` | 操作 | 未实现 | — |
| 已配对设备 | `bluetooth.222005b0` | 操作 | 未实现 | — |
| 发现设置 | `bluetooth.a54ec9a0` | 操作 | 未实现 | — |

### 设备 — `device-list`

连接设备与设备属性

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:connecteddevices`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加设备 | `device-list.1d30ae60` | 操作 | 未实现 | — |
| 已连接设备 | `device-list.c4c19ef3` | 信息展示 | 未实现 | — |
| 显示器和扩展坞 | `device-list.eabd0e62` | 操作 | 未实现 | — |
| 移除设备 | `device-list.9064c223` | 操作 | 未实现 | — |

### 打印机和扫描仪 — `printers`

添加设备、默认打印机与队列

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:printers`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加打印机或扫描仪 | `printers.9a92f276` | 操作 | 未实现 | — |
| 自动管理默认打印机 | `printers.29e59f94` | 开关 | 未实现 | — |
| 通过按流量计费连接下载驱动程序 | `printers.7d2ec3e1` | 开关 | 未实现 | — |
| 打印队列 | `printers.98323162` | 操作 | 未实现 | — |
| 打印首选项 | `printers.1b618ab5` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Printers & Scanners › Let Windows manage my default printer | `printers.reference.c1c02196` | 开关 | 未实现 | — |

### 摄像头 — `cameras`

摄像头目录、图像与访问

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:camera`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 已连接摄像头 | `cameras.89d99d4d` | 信息展示 | 未实现 | — |
| 添加网络摄像头 | `cameras.2f6bf052` | 操作 | 未实现 | — |
| 亮度 | `cameras.5d419889` | 滑块 | 未实现 | — |
| 对比度 | `cameras.9212a1ec` | 滑块 | 未实现 | — |
| 饱和度 | `cameras.1e9ac879` | 滑块 | 未实现 | — |
| 锐度 | `cameras.6b14430e` | 滑块 | 未实现 | — |
| 允许多个应用使用摄像头 | `cameras.6b86ffc4` | 开关 | 未实现 | — |
| 重置相机设置 | `cameras.39cd691a` | 操作 | 未实现 | — |

### 鼠标 — `mouse`

指针、滚轮与主按钮

页面状态：**未实现**；条目：11；已实现 0 / 未实现 11 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:mousetouchpad`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 主鼠标按钮 | `mouse.ad43aa5f` | 选择 | 未实现 | — |
| 指针速度 | `mouse.2f06ebc7` | 滑块 | 未实现 | — |
| 提高指针精确度 | `mouse.62b5a139` | 开关 | 未实现 | — |
| 滚动方式 | `mouse.33146c4a` | 选择 | 未实现 | — |
| 滚动行数 | `mouse.1b83c1e4` | 选择 | 未实现 | — |
| 悬停时滚动非活动窗口 | `mouse.bb950acc` | 开关 | 未实现 | — |
| 其他鼠标设置 | `mouse.efd4a33a` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mouse › Mouse pointer speed | `mouse.reference.76e18b09` | 滑块 | 未实现 | — |
| Mouse › Roll the mouse wheel to scroll | `mouse.reference.f26b3e91` | 开关 | 未实现 | — |
| Mouse › Lines to scroll at a time | `mouse.reference.3bbac4aa` | 选择 | 未实现 | — |
| Mouse › Scroll inactive windows when hovering over them | `mouse.reference.8907aa76` | 开关 | 未实现 | — |

### 触摸板 — `touchpad`

轻触、滚动与多指手势

页面状态：**未实现**；条目：24；已实现 0 / 未实现 24 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:devices-touchpad`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 触摸板 | `touchpad.5c2f0621` | 开关 | 未实现 | — |
| 连接鼠标时保持触摸板开启 | `touchpad.0b02e5ac` | 开关 | 未实现 | — |
| 光标速度 | `touchpad.5e254c65` | 滑块 | 未实现 | — |
| 触摸板敏感度 | `touchpad.eacee367` | 选择 | 未实现 | — |
| 单指轻触单击 | `touchpad.b59ea1b8` | 开关 | 未实现 | — |
| 双指轻触右键 | `touchpad.6025c7de` | 开关 | 未实现 | — |
| 轻触两次后拖动多选 | `touchpad.7b141aed` | 开关 | 未实现 | — |
| 右下角按压右键 | `touchpad.9ca343b1` | 开关 | 未实现 | — |
| 双指滚动 | `touchpad.8bd607db` | 开关 | 未实现 | — |
| 捏合缩放 | `touchpad.0fd19b47` | 开关 | 未实现 | — |
| 滚动方向 | `touchpad.4fe1093e` | 选择 | 未实现 | — |
| 三指手势 | `touchpad.489e5e53` | 选择 | 未实现 | — |
| 四指手势 | `touchpad.8a817c68` | 选择 | 未实现 | — |
| 触觉反馈 | `touchpad.f7d769a7` | 开关 | 未实现 | — |
| 反馈强度 | `touchpad.2b27039e` | 滑块 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Touchpad › Change the cursor speed | `touchpad.reference.8f2e9734` | 滑块 | 未实现 | — |
| Touchpad › Touchpad sensitivity | `touchpad.reference.79eb339a` | 开关 | 未实现 | — |
| Touchpad › Tap with a single finger to single-click | `touchpad.reference.45d5f5e6` | 开关 | 未实现 | — |
| Touchpad › Tap with two fingers to right-click | `touchpad.reference.380325e1` | 开关 | 未实现 | — |
| Touchpad › Tap twice and drag to multi-select | `touchpad.reference.c6871bd5` | 开关 | 未实现 | — |
| Touchpad › Press the lower right corner of the touchpad to right-click | `touchpad.reference.0c650d0c` | 开关 | 未实现 | — |
| Touchpad › Drag two fingers to scroll | `touchpad.reference.ddf2ff25` | 开关 | 未实现 | — |
| Touchpad › Pinch to Zoom | `touchpad.reference.9fd08601` | 开关 | 未实现 | — |
| Touchpad › Touchpad feedback (supported on some devices only) › Intensity (supported on some devices only) | `touchpad.reference.bbbc35e5` | 滑块 | 未实现 | — |

### 触摸 — `touch`

触摸手势与唤醒

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:devices-touch`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 三指和四指触摸手势 | `touch.5cfa5330` | 开关 | 未实现 | — |
| 触摸屏幕唤醒 | `touch.de9f8969` | 开关 | 未实现 | — |
| 触摸指示器 | `touch.e963918e` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Touch › Three- and four-finger touch gestures | `touch.reference.b3eb626b` | 开关 | 未实现 | — |
| Touch › Touch the screen to wake (supported on some devices only) | `touch.reference.4283e4ac` | 开关 | 未实现 | — |

### 笔和 Windows Ink — `pen`

笔输入、笔菜单与反馈

页面状态：**未实现**；条目：15；已实现 0 / 未实现 15 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:pen`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 惯用手 | `pen.eab621aa` | 选择 | 未实现 | — |
| 使用笔时忽略触摸 | `pen.11c38039` | 开关 | 未实现 | — |
| 将笔用作鼠标 | `pen.73aecd75` | 开关 | 未实现 | — |
| 笔按钮模拟右键 | `pen.7528aa4c` | 开关 | 未实现 | — |
| 书写触觉反馈 | `pen.7a0091bd` | 开关 | 未实现 | — |
| 交互触觉反馈 | `pen.046201e2` | 开关 | 未实现 | — |
| 反馈强度 | `pen.2b27039e` | 滑块 | 未实现 | — |
| 取出笔时显示笔菜单 | `pen.04119d43` | 开关 | 未实现 | — |
| 笔快捷键 | `pen.050f809b` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Pen and Windows Ink › Ignore touch input when I'm using my pen | `pen.reference.f573a64c` | 开关 | 未实现 | — |
| Pen and Windows Ink › Let me use my pen as a mouse when it's available | `pen.reference.e839eb2c` | 开关 | 未实现 | — |
| Pen and Windows Ink › Use the pen button as a right-click equivalent when it's available | `pen.reference.0f60ea0a` | 开关 | 未实现 | — |
| Pen and Windows Ink › Tactile signals (supported on some devices only) › While inking (supported on some devices only) | `pen.reference.3ad69d1e` | 开关 | 未实现 | — |
| Pen and Windows Ink › Tactile signals (supported on some devices only) › While interacting with your device (supported on some devices only) | `pen.reference.7b1c28dd` | 开关 | 未实现 | — |
| Pen and Windows Ink › Tactile signals (supported on some devices only) › Intensity (supported on some devices only) | `pen.reference.8a3c1cf1` | 滑块 | 未实现 | — |

### 笔快捷按钮 — `pen-shortcuts`

单击、双击与按住动作

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:pen-button`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 单击 | `pen-shortcuts.63754892` | 选择 | 未实现 | — |
| 双击 | `pen-shortcuts.f4121511` | 选择 | 未实现 | — |
| 按住 | `pen-shortcuts.c38aef1b` | 选择 | 未实现 | — |
| 允许应用替换按钮行为 | `pen-shortcuts.941cf204` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Choose what your shortcut button does › Single-click | `pen-shortcuts.reference.ceea88ce` | 开关 | 未实现 | — |
| Choose what your shortcut button does › Double-click | `pen-shortcuts.reference.1f59f186` | 开关 | 未实现 | — |
| Choose what your shortcut button does › Press and hold (only supported by some pens) | `pen-shortcuts.reference.853b480c` | 开关 | 未实现 | — |
| Choose what your shortcut button does › Allow apps to override the shortcut button behavior | `pen-shortcuts.reference.339eec05` | 选择 | 未实现 | — |
| Choose what your shortcut button does › When available, show pen menu after I remove my pen from storage | `pen-shortcuts.reference.afd4d4ac` | 开关 | 未实现 | — |

### 自动播放 — `autoplay`

可移动介质与存储卡默认行为

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:autoplay`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 对所有媒体和设备使用自动播放 | `autoplay.aef48ac6` | 开关 | 未实现 | — |
| 可移动驱动器 | `autoplay.cf7a8268` | 选择 | 未实现 | — |
| 存储卡 | `autoplay.16fc14e6` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Autoplay › Use AutoPlay for all media and devices | `autoplay.reference.60b8b8bf` | 开关 | 未实现 | — |
| Autoplay › Removable drive | `autoplay.reference.ea178ab2` | 开关 | 未实现 | — |
| Autoplay › Memory card | `autoplay.reference.9dce54e3` | 开关 | 未实现 | — |

### USB — `usb`

连接问题、充电与节能

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:usb`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 连接出现问题时通知我 | `usb.ef54bf0f` | 开关 | 未实现 | — |
| USB 充电缓慢时通知我 | `usb.4b9d110f` | 开关 | 未实现 | — |
| 屏幕关闭时停止 USB 设备以节能 | `usb.cbd35db8` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| USB › Connection notifications | `usb.reference.efa5ab97` | 开关 | 未实现 | — |
| USB › Show a notification if this PC is charging slowly over USB | `usb.reference.d575fa71` | 开关 | 未实现 | — |

### 移动设备 — `mobile`

手机连接与跨设备体验

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:mobile-devices`、`ms-settings:mobile-devices-addphone`、`ms-settings:mobile-devices-addphone-direct`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 允许访问移动设备 | `mobile.56e3e122` | 开关 | 未实现 | — |
| 管理移动设备 | `mobile.1ec69bd1` | 操作 | 未实现 | — |
| 添加手机 | `mobile.8031425b` | 操作 | 未实现 | — |
| 显示手机建议 | `mobile.1c9889d2` | 开关 | 未实现 | — |

### 滚轮设备 — `wheel`

Surface Dial 等配件参考

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:wheel`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加滚轮设备 | `wheel.1432f6ac` | 操作 | 不适用 | — |
| 灵敏度 | `wheel.a359b3f1` | 滑块 | 不适用 | — |
| 触觉反馈 | `wheel.f7d769a7` | 开关 | 不适用 | — |
| 默认工具 | `wheel.cbe34089` | 选择 | 不适用 | — |


<a id="category-network"></a>

## 网络和 Internet

Wi-Fi、以太网与 VPN

### 网络状态 — `network-status`

连接信息、适配器与数据使用量

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-status`。

相关页面 ID：`network-properties`、`data-usage`、`network-advanced`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 连接状态 | `network-status.b639d60c` | 信息展示 | 未实现 | — |
| 网络名称 | `network-status.e290dbc9` | 信息展示 | 未实现 | — |
| 网络属性 | `network-status.3854422a` | 操作 | 未实现 | — |
| 数据使用量 | `network-status.7d98a49a` | 操作 | 未实现 | — |
| 高级网络设置 | `network-status.b72985a7` | 操作 | 未实现 | — |

### Wi-Fi — `wifi`

无线网络、随机地址与自动连接

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-wifi`。

相关页面 ID：`known-networks`、`network-properties`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Wi-Fi | `wifi.780ff71c` | 开关 | 未实现 | — |
| 显示可用网络 | `wifi.3df9da60` | 操作 | 未实现 | — |
| 管理已知网络 | `wifi.f64d0727` | 操作 | 未实现 | — |
| 随机硬件地址 | `wifi.ad560280` | 开关 | 未实现 | — |
| 当前网络属性 | `wifi.1a8098ed` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Wi-Fi › Random hardware addresses | `wifi.reference.cc052043` | 开关 | 未实现 | — |

### 管理已知网络 — `known-networks`

保存的网络与连接偏好

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-wifisettings`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加网络 | `known-networks.2120e5bc` | 操作 | 未实现 | — |
| 网络名称 | `known-networks.e290dbc9` | 文本输入 | 未实现 | — |
| 安全类型 | `known-networks.2f201b69` | 选择 | 未实现 | — |
| 自动连接 | `known-networks.a034ebdf` | 开关 | 未实现 | — |
| 按流量计费 | `known-networks.2bebdc73` | 开关 | 未实现 | — |
| 忘记网络 | `known-networks.3359a795` | 操作 | 未实现 | — |

### 以太网 — `ethernet`

有线网络与 IP、DNS 设置

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-ethernet`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 连接状态 | `ethernet.b639d60c` | 信息展示 | 未实现 | — |
| 网络配置文件 | `ethernet.403096d1` | 选择 | 未实现 | — |
| 按流量计费 | `ethernet.2bebdc73` | 开关 | 未实现 | — |
| IP 分配 | `ethernet.0e517641` | 选择 | 未实现 | — |
| DNS 分配 | `ethernet.9e3297e9` | 选择 | 未实现 | — |
| IP 地址 | `ethernet.010efa2c` | 文本输入 | 未实现 | — |
| 网关 | `ethernet.86ab111e` | 文本输入 | 未实现 | — |
| 首选 DNS | `ethernet.b10ffae1` | 文本输入 | 未实现 | — |

### VPN — `vpn`

连接配置与流量策略

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-vpn`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加 VPN | `vpn.887aa7eb` | 操作 | 未实现 | — |
| 连接名称 | `vpn.5ef1920d` | 文本输入 | 未实现 | — |
| 服务器地址 | `vpn.2eb291f6` | 文本输入 | 未实现 | — |
| VPN 类型 | `vpn.805e1a09` | 选择 | 未实现 | — |
| 登录信息类型 | `vpn.efb20f32` | 选择 | 未实现 | — |
| 允许按流量计费连接 | `vpn.1c70d283` | 开关 | 未实现 | — |
| 允许漫游时使用 VPN | `vpn.a42231a7` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| VPN › Allow VPN over metered networks | `vpn.reference.f20bc91d` | 开关 | 未实现 | — |
| VPN › Allow VPN while roaming | `vpn.reference.b8f24d72` | 开关 | 未实现 | — |

### 移动热点 — `hotspot`

共享连接、频段与省电

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-mobilehotspot`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 移动热点 | `hotspot.351d8ca9` | 开关 | 未实现 | — |
| 共享 Internet 来源 | `hotspot.8a5fabb4` | 选择 | 未实现 | — |
| 共享方式 | `hotspot.48902a81` | 选择 | 未实现 | — |
| 网络名称 | `hotspot.e290dbc9` | 文本输入 | 未实现 | — |
| 网络密码 | `hotspot.c1412226` | 文本输入 | 未实现 | — |
| 频段 | `hotspot.fea27d68` | 选择 | 未实现 | — |
| 无设备连接时关闭热点 | `hotspot.dc01e4b5` | 开关 | 未实现 | — |

### 飞行模式 — `airplane`

无线设备与独立无线开关

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-airplanemode`、`ms-settings:proximity`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 飞行模式 | `airplane.599fbf62` | 开关 | 未实现 | — |
| Wi-Fi 无线设备 | `airplane.3d2af662` | 开关 | 未实现 | — |
| 蓝牙无线设备 | `airplane.ce637a87` | 开关 | 未实现 | — |

### 手机网络 — `cellular`

SIM、流量、漫游与 APN

页面状态：**未实现**；条目：11；已实现 0 / 未实现 11 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-cellular`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 手机网络 | `cellular.bd841818` | 开关 | 未实现 | — |
| 自动保持连接 | `cellular.86e5dce3` | 开关 | 未实现 | — |
| 按流量计费 | `cellular.2bebdc73` | 开关 | 未实现 | — |
| 数据漫游 | `cellular.68aa3b06` | 选择 | 未实现 | — |
| Wi-Fi 较差时使用手机网络 | `cellular.33c77eb1` | 开关 | 未实现 | — |
| SIM 卡属性 | `cellular.3cb586c5` | 操作 | 未实现 | — |
| APN | `cellular.4a7de9b1` | 文本输入 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Cellular › Let Windows keep me connected | `cellular.reference.0a6416ca` | 开关 | 未实现 | — |
| Cellular › Metered Connection | `cellular.reference.3a1637fd` | 开关 | 未实现 | — |
| Cellular › Data roaming options (dropdown) | `cellular.reference.120ca531` | 选择 | 未实现 | — |
| Cellular › Use cellular whenever Wi-Fi is poor | `cellular.reference.a4a32b75` | 开关 | 未实现 | — |

### 代理 — `proxy`

自动检测、脚本与手动代理

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-proxy`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 自动检测设置 | `proxy.22b15396` | 开关 | 未实现 | — |
| 使用设置脚本 | `proxy.bcc75aea` | 开关 | 未实现 | — |
| 脚本地址 | `proxy.58d46c1e` | 文本输入 | 未实现 | — |
| 使用代理服务器 | `proxy.0727a1b1` | 开关 | 未实现 | — |
| 代理地址 | `proxy.903f8d36` | 文本输入 | 未实现 | — |
| 端口 | `proxy.6cbb7335` | 文本输入 | 未实现 | — |
| 绕过代理的地址 | `proxy.908eea6f` | 文本输入 | 未实现 | — |
| 本地地址不使用代理 | `proxy.f87cf52b` | 开关 | 未实现 | — |

### 拨号 — `dialup`

旧式拨号连接参考

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-dialup`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 设置新连接 | `dialup.17b3e40b` | 操作 | 未实现 | — |
| 拨号号码 | `dialup.07f7d35b` | 文本输入 | 未实现 | — |
| 用户名 | `dialup.a1aaf352` | 文本输入 | 未实现 | — |
| 密码 | `dialup.c839a8ff` | 文本输入 | 未实现 | — |

### DirectAccess — `directaccess`

Windows 企业远程访问参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:network-directaccess`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 连接状态 | `directaccess.b639d60c` | 信息展示 | 不适用 | — |
| 连接属性 | `directaccess.73eb799f` | 操作 | 不适用 | — |

### 高级网络设置 — `network-advanced`

适配器、共享与网络重置

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:network-advancedsettings`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 网络适配器 | `network-advanced.f6baeffd` | 操作 | 未实现 | — |
| 高级共享设置 | `network-advanced.40e1a0e7` | 操作 | 未实现 | — |
| 数据使用量 | `network-advanced.7d98a49a` | 操作 | 未实现 | — |
| 硬件和连接属性 | `network-advanced.95f512ab` | 操作 | 未实现 | — |
| 网络重置 | `network-advanced.bb3c0b53` | 操作 | 未实现 | — |

### 网络连接属性 — `network-properties`

地址分配、名称解析与链路信息

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| IP 分配 | `network-properties.0e517641` | 选择 | 未实现 | — |
| IPv4 地址 | `network-properties.3aaacc78` | 文本输入 | 未实现 | — |
| 子网前缀长度 | `network-properties.73ef4bcd` | 文本输入 | 未实现 | — |
| 网关 | `network-properties.86ab111e` | 文本输入 | 未实现 | — |
| 首选 DNS | `network-properties.b10ffae1` | 文本输入 | 未实现 | — |
| 备用 DNS | `network-properties.ba1b830a` | 文本输入 | 未实现 | — |
| DNS over HTTPS | `network-properties.90d50c67` | 开关 | 未实现 | — |
| 链路速度 | `network-properties.ab79d605` | 信息展示 | 未实现 | — |
| 硬件地址 | `network-properties.aaf3aebe` | 信息展示 | 未实现 | — |

### 数据使用量 — `data-usage`

时间范围、流量限额与应用用量

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 时间范围 | `data-usage.2be90408` | 选择 | 未实现 | — |
| 输入流量限制 | `data-usage.55685047` | 操作 | 未实现 | — |
| 限制类型 | `data-usage.45989fef` | 选择 | 未实现 | — |
| 流量限制 | `data-usage.a4d31b25` | 文本输入 | 未实现 | — |
| 重置统计信息 | `data-usage.800eddaf` | 操作 | 未实现 | — |

### Wi-Fi 配置 — `wifi-provisioning`

配置文件安装参考

页面状态：**未实现**；条目：2；已实现 0 / 未实现 2 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:wifi-provisioning`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 导入无线网络配置 | `wifi-provisioning.6473ace4` | 操作 | 未实现 | — |
| 配置文件路径 | `wifi-provisioning.0b38bb02` | 文本输入 | 未实现 | — |


<a id="category-personalization"></a>

## 个性化

背景、主题与桌面外观

### 背景 — `background`

壁纸、纯色与幻灯片

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-background`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 背景类型 | `background.99b01ada` | 选择 | 未实现 | — |
| 浏览照片 | `background.9e58290b` | 操作 | 未实现 | — |
| 桌面图片适应方式 | `background.56c289eb` | 选择 | 未实现 | — |
| 切换图片间隔 | `background.de8d2f50` | 选择 | 未实现 | — |
| 随机播放 | `background.eca2a518` | 开关 | 未实现 | — |
| 背景颜色 | `background.4a2d8a28` | 颜色 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Background › Personalize your background | `background.reference.fdec0d3a` | 开关 | 未实现 | — |
| Background › Choose a photo | `background.reference.a8aee03d` | 选择 | 未实现 | — |
| Background › Choose a fit for your desktop image | `background.reference.0518a1f3` | 选择 | 未实现 | — |

### 颜色 — `colors`

明暗模式、强调色与透明效果

页面状态：**未实现**；条目：13；已实现 0 / 未实现 13 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-colors`、`ms-settings:colors`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 模式 | `colors.ed0eea8f` | 选择 | 未实现 | — |
| 透明效果 | `colors.3630e7d0` | 开关 | 未实现 | — |
| 强调色来源 | `colors.8983f367` | 选择 | 未实现 | — |
| 强调色 | `colors.6f67371e` | 颜色 | 未实现 | — |
| 在任务栏显示强调色 | `colors.c3a39826` | 开关 | 未实现 | — |
| 在标题栏和窗口边框显示强调色 | `colors.ac16e9e8` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Colors › Choose your mode | `colors.reference.1232ca77` | 选择 | 未实现 | — |
| Colors › Transparency Effects | `colors.reference.ed936eee` | 开关 | 未实现 | — |
| Colors › Accent Color | `colors.reference.8fd43cc0` | 选择 | 未实现 | — |
| Colors › Windows Color | `colors.reference.14bc5762` | 选择 | 未实现 | — |
| Colors › Custom Color | `colors.reference.b4c97f0e` | 选择 | 未实现 | — |
| Colors › Show Accent color on start and Taskbar | `colors.reference.990d69cf` | 选择 | 未实现 | — |
| Colors › Show Accent color on Title bar and window border | `colors.reference.47f631a5` | 选择 | 未实现 | — |

### 主题 — `themes`

主题组合、声音与指针

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:themes`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 选择主题 | `themes.a9039704` | 操作 | 未实现 | — |
| 保存主题 | `themes.d582c922` | 操作 | 未实现 | — |
| 背景 | `themes.b13d33a5` | 操作 | 未实现 | — |
| 颜色 | `themes.8ef48860` | 操作 | 未实现 | — |
| 声音 | `themes.ab9ff81d` | 操作 | 未实现 | — |
| 鼠标光标 | `themes.cb5e32b2` | 操作 | 未实现 | — |
| 桌面图标设置 | `themes.26420e25` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Themes | `themes.reference.94d5186b` | 选择 | 未实现 | — |

### 锁屏界面 — `lockscreen`

锁屏背景、状态与登录画面

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:lockscreen`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 锁屏背景 | `lockscreen.70c5d385` | 选择 | 未实现 | — |
| 选择图片 | `lockscreen.18104edf` | 操作 | 未实现 | — |
| 锁屏状态 | `lockscreen.a0216293` | 选择 | 未实现 | — |
| 显示提示和建议 | `lockscreen.827be04c` | 开关 | 未实现 | — |
| 登录界面显示锁屏背景 | `lockscreen.74460c63` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Lock screen › Personalize your lock screen | `lockscreen.reference.3ada0526` | 开关 | 未实现 | — |
| Lock screen › Get fun facts, tips, tricks, and more on your lock screen | `lockscreen.reference.252498b5` | 开关 | 未实现 | — |
| Lock screen › Show the lock screen background picture on the sign-in screen | `lockscreen.reference.6437619e` | 开关 | 未实现 | — |

### 文本输入 — `text-input`

触摸键盘主题与文字外观

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-textinput`、`ms-settings:personalization-touchkeyboard`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 选择键盘主题 | `text-input.8c7d4c60` | 操作 | 未实现 | — |
| 键盘大小 | `text-input.885e69f4` | 滑块 | 未实现 | — |
| 按键背景 | `text-input.1d7e859f` | 开关 | 未实现 | — |
| 按键文字大小 | `text-input.bb1a22e2` | 选择 | 未实现 | — |
| 编辑自定义主题 | `text-input.99f25205` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Text Input › Theme for touch keyboard | `text-input.reference.e71b3bbe` | 选择 | 未实现 | — |
| Text Input › Touch keyboard › Touch keyboard size | `text-input.reference.3fb1e372` | 选择 | 未实现 | — |
| Text Input › Touch keyboard › Show key background | `text-input.reference.0a8ab202` | 开关 | 未实现 | — |
| Text Input › Touch keyboard › Key text size | `text-input.reference.1fc1438b` | 选择 | 未实现 | — |

### 开始菜单 — `start`

布局、最近内容与文件夹参考

页面状态：**未实现**；条目：22；已实现 0 / 未实现 22 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-start`。

相关页面 ID：`start-folders`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 布局 | `start.b0961e17` | 选择 | 未实现 | — |
| 显示最近添加应用 | `start.d92d56e8` | 开关 | 未实现 | — |
| 显示最常用应用 | `start.c8b5b887` | 开关 | 未实现 | — |
| 显示最近打开的项目 | `start.8c92cfee` | 开关 | 未实现 | — |
| 显示提示和推荐 | `start.468469a6` | 开关 | 未实现 | — |
| 显示账户通知 | `start.13ed1ecd` | 开关 | 未实现 | — |
| 选择开始菜单文件夹 | `start.1e3f5abe` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Start › Start layout › Layout | `start.reference.4e607a8a` | 选择 | 未实现 | — |
| Start › Start layout › Show recently added apps | `start.reference.9e4e7236` | 开关 | 未实现 | — |
| Start › Start layout › Show most used apps | `start.reference.fc387ac7` | 开关 | 未实现 | — |
| Start › Start layout › Show recommended files in Start, recent files in File Explorer, and items in Jump Lists | `start.reference.8ec7c2b7` | 开关 | 未实现 | — |
| Start › Start layout › Show recommendations for tips, shortcuts, new apps and more | `start.reference.bfca4f8f` | 选择 | 未实现 | — |
| Start › Start layout › Show account-related notifications | `start.reference.14d5c068` | 开关 | 未实现 | — |
| Start › Folders › Settings | `start.reference.abde902c` | 开关 | 未实现 | — |
| Start › Folders › File Explorer | `start.reference.f8412609` | 开关 | 未实现 | — |
| Start › Folders › Documents | `start.reference.69e50dbf` | 开关 | 未实现 | — |
| Start › Folders › Downloads | `start.reference.5932c066` | 开关 | 未实现 | — |
| Start › Folders › Music | `start.reference.85550725` | 开关 | 未实现 | — |
| Start › Folders › Pictures | `start.reference.db786e0a` | 开关 | 未实现 | — |
| Start › Folders › Videos | `start.reference.8139f929` | 开关 | 未实现 | — |
| Start › Folders › Network | `start.reference.6ec482d6` | 开关 | 未实现 | — |
| Start › Folders › Personal folder | `start.reference.543cab9d` | 开关 | 未实现 | — |

### 开始菜单文件夹 — `start-folders`

电源按钮旁的快捷入口参考

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-start-places`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 设置 | `start-folders.7debf9cb` | 开关 | 未实现 | — |
| 文件资源管理器 | `start-folders.9796bfb6` | 开关 | 未实现 | — |
| 文档 | `start-folders.10691272` | 开关 | 未实现 | — |
| 下载 | `start-folders.2b9d0131` | 开关 | 未实现 | — |
| 音乐 | `start-folders.afb3c40c` | 开关 | 未实现 | — |
| 图片 | `start-folders.be8da62e` | 开关 | 未实现 | — |
| 视频 | `start-folders.fa4e33b6` | 开关 | 未实现 | — |
| 网络 | `start-folders.0cbda6b5` | 开关 | 未实现 | — |
| 个人文件夹 | `start-folders.08058297` | 开关 | 未实现 | — |

### 任务栏 — `taskbar`

任务栏项目、托盘与多显示器行为

页面状态：**未实现**；条目：26；已实现 0 / 未实现 26 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:taskbar`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索 | `taskbar.f0409080` | 开关 | 未实现 | — |
| 任务视图 | `taskbar.f048711a` | 开关 | 未实现 | — |
| 小组件 | `taskbar.f74efb4f` | 开关 | 未实现 | — |
| 系统托盘图标 | `taskbar.2571c928` | 开关 | 未实现 | — |

#### 任务栏行为

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 对齐方式 | `taskbar.47b8b751` | 选择 | 未实现 | — |
| 自动隐藏 | `taskbar.90482e5d` | 开关 | 未实现 | — |
| 显示徽章 | `taskbar.aee99fe4` | 开关 | 未实现 | — |
| 显示应用闪烁 | `taskbar.45c83101` | 开关 | 未实现 | — |
| 所有显示器显示任务栏 | `taskbar.6d30d353` | 开关 | 未实现 | — |
| 多显示器应用显示范围 | `taskbar.e348754b` | 选择 | 未实现 | — |
| 共享任意窗口 | `taskbar.a4e2e2b6` | 开关 | 未实现 | — |
| 角落显示桌面 | `taskbar.b5f530b6` | 开关 | 未实现 | — |
| 合并按钮和隐藏标签 | `taskbar.b00ce8b3` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Taskbar › Taskbar Pinned layout | `taskbar.reference.47ef6392` | 选择 | 未实现 | — |
| Taskbar › Taskbar Items › Task View | `taskbar.reference.0ca8d47b` | 开关 | 未实现 | — |
| Taskbar › Taskbar Items › Widgets | `taskbar.reference.2f04f30d` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › Taskbar alignment | `taskbar.reference.be160a7d` | 选择 | 未实现 | — |
| Taskbar › Taskbar behaviors › Automatically hide the taskbar | `taskbar.reference.986b8b3a` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › Show badges on taskbar apps | `taskbar.reference.b10a5381` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › Show flashing on taskbar apps | `taskbar.reference.3e990cfd` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › Show my taskbar on all my displays | `taskbar.reference.7eab6479` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › When using multiple displays show my taskbar apps on | `taskbar.reference.d7ca79fe` | 选择 | 未实现 | — |
| Taskbar › Taskbar behaviors › Share any window from my taskbar | `taskbar.reference.e875398a` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › Select the far corner of the taskbar to show the desktop | `taskbar.reference.502aa5d3` | 开关 | 未实现 | — |
| Taskbar › Taskbar behaviors › Combine taskbar buttons and hide labels | `taskbar.reference.67cefb4c` | 选择 | 未实现 | — |
| Taskbar › Taskbar behaviors › Combine taskbar buttons and hide labels on other taskbars | `taskbar.reference.e7e5a003` | 选择 | 未实现 | — |

### 字体 — `fonts`

字体预览、安装与字体目录

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:fonts`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索字体 | `fonts.65a8477b` | 文本输入 | 未实现 | — |
| 安装字体 | `fonts.158ba0bb` | 操作 | 未实现 | — |
| 字体详细信息 | `fonts.fc3969c7` | 操作 | 未实现 | — |
| 卸载字体 | `fonts.f869cae5` | 操作 | 未实现 | — |

### 动态光效 — `lighting`

兼容设备的灯光与效果

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-lighting`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 使用动态光效 | `lighting.c311d486` | 开关 | 未实现 | — |
| 兼容应用控制灯光 | `lighting.53e0654b` | 开关 | 未实现 | — |
| 亮度 | `lighting.5d419889` | 滑块 | 未实现 | — |
| 效果 | `lighting.151ddd4f` | 选择 | 未实现 | — |
| 灯光颜色 | `lighting.bf0bca1e` | 颜色 | 未实现 | — |
| 与强调色匹配 | `lighting.869e06ec` | 开关 | 未实现 | — |

### 设备使用情况 — `device-usage`

Windows 个性化建议参考

页面状态：**不适用**；条目：6；已实现 0 / 未实现 0 / 不适用 6。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:deviceusage`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 开发 | `device-usage.eb3774e3` | 开关 | 不适用 | — |
| 游戏 | `device-usage.2305ee3c` | 开关 | 不适用 | — |
| 家庭 | `device-usage.7cc8d6a5` | 开关 | 不适用 | — |
| 创意 | `device-usage.f3681782` | 开关 | 不适用 | — |
| 学校 | `device-usage.08610a85` | 开关 | 不适用 | — |
| 商业 | `device-usage.60d5c2a0` | 开关 | 不适用 | — |

### Copilot 键 — `copilot-key`

专用键行为参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:personalization-textinput-copilot-hardwarekey`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 专用键动作 | `copilot-key.965faf7e` | 选择 | 不适用 | — |
| 选择应用 | `copilot-key.9ec480c1` | 操作 | 不适用 | — |

### 速览 — `personalization-glance`

旧版页面，仅保留参考

页面状态：**不适用**；条目：1；已实现 0 / 未实现 0 / 不适用 1。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:personalization-glance`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 功能状态 | `personalization-glance.540cc78d` | 信息展示 | 不适用 | — |

### 导航栏 — `personalization-navbar`

旧版页面，仅保留参考

页面状态：**不适用**；条目：1；已实现 0 / 未实现 0 / 不适用 1。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:personalization-navbar`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 功能状态 | `personalization-navbar.540cc78d` | 信息展示 | 不适用 | — |

### 个性化概览 — `personalization`

外观与桌面设置入口

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 背景 | `personalization.b13d33a5` | 操作 | 未实现 | — |
| 颜色 | `personalization.8ef48860` | 操作 | 未实现 | — |
| 主题 | `personalization.e848ddd4` | 操作 | 未实现 | — |
| 锁屏界面 | `personalization.355caa83` | 操作 | 未实现 | — |
| 任务栏 | `personalization.3405fcce` | 操作 | 未实现 | — |


<a id="category-apps"></a>

## 应用

应用管理、默认应用与启动项

### 已安装的应用 — `installed`

应用目录、卸载与高级选项

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:appsfeatures`。

相关页面 ID：`app-properties`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索已安装应用 | `installed.15735a25` | 文本输入 | 未实现 | — |
| 排序方式 | `installed.3bf3689a` | 选择 | 未实现 | — |
| 筛选驱动器 | `installed.765cf6c3` | 选择 | 未实现 | — |
| 应用高级选项 | `installed.32098ab2` | 操作 | 未实现 | — |
| 卸载应用 | `installed.c3c4a29c` | 操作 | 未实现 | — |

### 应用高级选项 — `app-properties`

应用权限、后台运行与修复

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:appsfeatures-app`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 应用版本 | `app-properties.e8427b83` | 信息展示 | 未实现 | — |
| 摄像头权限 | `app-properties.928fd04d` | 开关 | 未实现 | — |
| 麦克风权限 | `app-properties.b9fea940` | 开关 | 未实现 | — |
| 后台运行权限 | `app-properties.dde21b2c` | 选择 | 未实现 | — |
| 终止应用 | `app-properties.6a3d60ab` | 操作 | 未实现 | — |
| 修复应用 | `app-properties.dba04b1b` | 操作 | 未实现 | — |
| 重置应用 | `app-properties.2888e689` | 操作 | 未实现 | — |
| 卸载应用 | `app-properties.c3c4a29c` | 操作 | 未实现 | — |

### 高级应用设置 — `advanced-apps`

应用来源、存档与执行别名

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 应用来源 | `advanced-apps.5aa2062e` | 选择 | 未实现 | — |
| 存档应用 | `advanced-apps.c13be40a` | 开关 | 未实现 | — |
| 应用执行别名 | `advanced-apps.cb756d20` | 操作 | 未实现 | — |
| 跨设备共享 | `advanced-apps.ee408d1b` | 操作 | 未实现 | — |
| 用于网站的应用 | `advanced-apps.bcc84021` | 操作 | 未实现 | — |

### 默认应用 — `defaults`

文件类型、协议与应用默认值

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:defaultapps`、`ms-settings:defaultbrowsersettings`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索文件类型或链接类型 | `defaults.b131ac5a` | 文本输入 | 未实现 | — |
| 搜索应用 | `defaults.897fdfef` | 文本输入 | 未实现 | — |
| 默认浏览器 | `defaults.ccac113f` | 选择 | 未实现 | — |
| 默认邮件应用 | `defaults.3adc9929` | 选择 | 未实现 | — |
| 默认照片应用 | `defaults.c0b97974` | 选择 | 未实现 | — |
| 默认视频应用 | `defaults.e7fe6be6` | 选择 | 未实现 | — |
| 重置所有默认应用 | `defaults.ff4c4bec` | 操作 | 未实现 | — |

### 可选功能 — `optional`

功能安装与历史记录

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:optionalfeatures`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 查看可选功能 | `optional.3316f05b` | 操作 | 未实现 | — |
| 搜索已安装功能 | `optional.4ba5eede` | 文本输入 | 未实现 | — |
| 功能安装历史记录 | `optional.d8aed3a7` | 操作 | 未实现 | — |
| 更多系统功能 | `optional.bd2c3619` | 操作 | 未实现 | — |

### 用于网站的应用 — `websites`

将网站关联到应用

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:appsforwebsites`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索应用 | `websites.897fdfef` | 文本输入 | 未实现 | — |
| 允许应用打开关联网站 | `websites.8cd31008` | 开关 | 未实现 | — |
| 管理网站关联 | `websites.93e2b941` | 操作 | 未实现 | — |

### 离线地图 — `maps`

地图下载、保存位置与更新

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:maps`、`ms-settings:maps-downloadmaps`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 下载地图 | `maps.215e569e` | 操作 | 未实现 | — |
| 存储位置 | `maps.c445d42b` | 选择 | 未实现 | — |
| 通过按流量计费连接下载 | `maps.3f139dcf` | 开关 | 未实现 | — |
| 自动更新地图 | `maps.49291dd0` | 开关 | 未实现 | — |
| 删除所有地图 | `maps.bbecded0` | 操作 | 未实现 | — |

### 视频播放 — `video`

视频增强与电池偏好

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:videoplayback`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 自动处理视频以增强效果 | `video.0cb26c39` | 开关 | 未实现 | — |
| 降低分辨率以节省带宽 | `video.c96f936e` | 开关 | 未实现 | — |
| 电池播放偏好 | `video.7d6e4e4f` | 选择 | 未实现 | — |
| 使用电池时允许 HDR | `video.00912570` | 开关 | 未实现 | — |

### 启动应用 — `startup`

登录时启动的应用与影响

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:startupapps`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索启动应用 | `startup.c445161f` | 文本输入 | 未实现 | — |
| 排序方式 | `startup.3bf3689a` | 选择 | 未实现 | — |
| 示例应用开机启动 | `startup.bf13c9a3` | 开关 | 未实现 | — |
| 启动影响 | `startup.e46804cd` | 信息展示 | 未实现 | — |


<a id="category-accounts"></a>

## 账户

个人信息、登录与其他用户

### 账户信息 — `your-info`

头像、账户类型与身份信息

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:yourinfo`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 用户名 | `your-info.a1aaf352` | 信息展示 | 未实现 | — |
| 账户类型 | `your-info.082c31df` | 信息展示 | 未实现 | — |
| 更改头像 | `your-info.58484bbb` | 操作 | 未实现 | — |
| 管理账户 | `your-info.7e0e3d0b` | 操作 | 未实现 | — |
| 登录选项 | `your-info.398b2d99` | 操作 | 未实现 | — |

### 电子邮件和账户 — `email`

邮件、日历与其他应用账户

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:emailandaccounts`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加账户 | `email.c771c7d8` | 操作 | 未实现 | — |
| 添加工作或学校账户 | `email.83f45bb5` | 操作 | 未实现 | — |
| 其他应用使用的账户 | `email.f03ce431` | 信息展示 | 未实现 | — |

### 登录选项 — `signin`

验证方式、自动锁定与登录要求

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions`。

相关页面 ID：`dynamic-lock`、`hello-face`、`hello-fingerprint`、`security-key`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 面部识别 | `signin.090cb65e` | 操作 | 未实现 | — |
| 指纹识别 | `signin.e3ce550b` | 操作 | 未实现 | — |
| PIN | `signin.3adadd31` | 操作 | 未实现 | — |
| 安全密钥 | `signin.86a2121e` | 操作 | 未实现 | — |
| 密码 | `signin.c839a8ff` | 操作 | 未实现 | — |
| 图片密码 | `signin.82e24adb` | 操作 | 未实现 | — |
| 离开后重新登录要求 | `signin.572a16a1` | 选择 | 未实现 | — |
| 动态锁 | `signin.ad39c1be` | 开关 | 未实现 | — |
| 更新后使用登录信息完成设置 | `signin.3e47dee1` | 开关 | 未实现 | — |

### 动态锁 — `dynamic-lock`

蓝牙离开自动锁定

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions-dynamiclock`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 离开时自动锁定设备 | `dynamic-lock.62b4ddbf` | 开关 | 未实现 | — |
| 配对手机 | `dynamic-lock.fd140857` | 操作 | 未实现 | — |
| 已配对设备 | `dynamic-lock.222005b0` | 信息展示 | 未实现 | — |

### 面部识别 — `hello-face`

Windows Hello 注册流程参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:signinoptions-launchfaceenrollment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 设置面部识别 | `hello-face.f9b4646d` | 操作 | 不适用 | — |
| 改善识别 | `hello-face.83f9098f` | 操作 | 不适用 | — |
| 移除面部识别 | `hello-face.df6cef60` | 操作 | 不适用 | — |

### 指纹识别 — `hello-fingerprint`

生物识别注册参考

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions-launchfingerprintenrollment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加指纹 | `hello-fingerprint.3e0d66e1` | 操作 | 未实现 | — |
| 添加其他手指 | `hello-fingerprint.b640fea8` | 操作 | 未实现 | — |
| 移除指纹 | `hello-fingerprint.e8f4c9a5` | 操作 | 未实现 | — |

### 安全密钥 — `security-key`

密钥注册、PIN 与重置

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions-launchsecuritykeyenrollment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 管理安全密钥 | `security-key.2c16e903` | 操作 | 未实现 | — |
| 设置密钥 PIN | `security-key.ef14bdad` | 操作 | 未实现 | — |
| 重置安全密钥 | `security-key.9d94adb9` | 操作 | 未实现 | — |

### 家庭 — `family`

家庭成员与家长控制参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:family-group`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加家庭成员 | `family.4a69e379` | 操作 | 不适用 | — |
| 查看家庭组 | `family.140354ae` | 操作 | 不适用 | — |
| 管理家长控制 | `family.fc605dfe` | 操作 | 不适用 | — |

### 其他用户 — `other-users`

本地用户与账户类型

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:otherusers`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加用户 | `other-users.4f965d49` | 操作 | 未实现 | — |
| 更改账户类型 | `other-users.bcb938ac` | 操作 | 未实现 | — |
| 移除账户 | `other-users.b15b73d2` | 操作 | 未实现 | — |
| 设置自助终端 | `other-users.bf429391` | 操作 | 未实现 | — |

### 访问工作或学校 — `work`

组织账户与设备管理参考

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:workplace`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 连接组织账户 | `work.15cc03bd` | 操作 | 未实现 | — |
| 断开组织账户 | `work.840a0f15` | 操作 | 未实现 | — |
| 导出管理日志 | `work.89aa0c9d` | 操作 | 未实现 | — |
| 预配软件包 | `work.c24f1bf1` | 操作 | 未实现 | — |

### 系统备份 — `backup`

应用、偏好与同步参考

页面状态：**未实现**；条目：15；已实现 0 / 未实现 15 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:sync`、`ms-settings:backup`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 记住我的应用 | `backup.cecf4caf` | 开关 | 未实现 | — |
| 记住我的偏好 | `backup.66503cb5` | 开关 | 未实现 | — |
| 辅助功能偏好 | `backup.d018d14b` | 开关 | 未实现 | — |
| 账户和 Wi-Fi 网络 | `backup.af22a256` | 开关 | 未实现 | — |
| 个性化偏好 | `backup.bcd1955e` | 开关 | 未实现 | — |
| 语言偏好 | `backup.5d5065a9` | 开关 | 未实现 | — |
| 其他系统设置 | `backup.3f79292e` | 开关 | 未实现 | — |
| 管理同步内容 | `backup.1b959d02` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Windows Backup › Remember my apps | `backup.reference.04edcf6f` | 开关 | 未实现 | — |
| Windows Backup › Remember my preferences (toggle) › Accessibility | `backup.reference.52e80604` | 开关 | 未实现 | — |
| Windows Backup › Remember my preferences (toggle) › Accounts, WiFi networks and passwords | `backup.reference.33a8643d` | 开关 | 未实现 | — |
| Windows Backup › Remember my preferences (toggle) › Personalization | `backup.reference.60ff3096` | 开关 | 未实现 | — |
| Windows Backup › Remember my preferences (toggle) › Language preferences and dictionary | `backup.reference.b695b07e` | 开关 | 未实现 | — |
| Windows Backup › Remember my preferences (toggle) › Other Windows settings | `backup.reference.802b32da` | 开关 | 未实现 | — |
| Windows Backup › Email and Accounts › Accounts used by other apps (MSA accounts only) | `backup.reference.c0c91ce4` | 开关 | 未实现 | — |

### 自助终端 — `kiosk`

专用会话与单应用限制

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:assignedaccess`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 开始设置 | `kiosk.279497bb` | 操作 | 未实现 | — |
| 会话名称 | `kiosk.864aff36` | 文本输入 | 未实现 | — |
| 选择应用 | `kiosk.9ec480c1` | 操作 | 未实现 | — |

### 预配软件包 — `provisioning`

企业配置包参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:provisioning`、`ms-settings:workplace-provisioning`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加预配包 | `provisioning.2588f918` | 操作 | 不适用 | — |
| 移除预配包 | `provisioning.bceb2cc7` | 操作 | 不适用 | — |

### 修复令牌 — `repair-token`

企业身份修复参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:workplace-repairtoken`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 修复令牌 | `repair-token.ad0f71f6` | 文本输入 | 不适用 | — |
| 应用令牌 | `repair-token.6006fa6c` | 操作 | 不适用 | — |

### Windows Anywhere — `windows-anywhere`

Windows 专用跨设备体验参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:windowsanywhere`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 管理设备同步 | `windows-anywhere.32121bde` | 操作 | 不适用 | — |
| 设备支持状态 | `windows-anywhere.e67d4f70` | 信息展示 | 不适用 | — |

### 通行密钥 — `passkeys`

设备上的凭据与提供程序

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

相关页面 ID：`passkeys-advanced`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 搜索通行密钥 | `passkeys.8fbaa646` | 文本输入 | 未实现 | — |
| 已保存的通行密钥 | `passkeys.6e953913` | 信息展示 | 未实现 | — |
| 删除通行密钥 | `passkeys.53d248e4` | 操作 | 未实现 | — |
| 高级通行密钥选项 | `passkeys.93d889c1` | 操作 | 未实现 | — |

### 通行密钥高级选项 — `passkeys-advanced`

本地保存与第三方密钥服务

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 在此设备保存通行密钥 | `passkeys-advanced.71fe6bdc` | 开关 | 未实现 | — |
| 第三方通行密钥提供程序 | `passkeys-advanced.973ee8b8` | 开关 | 未实现 | — |
| 配置密钥服务 | `passkeys-advanced.786de3b4` | 操作 | 未实现 | — |

### 云存储 — `cloud-storage`

Windows 首页云存储卡片参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 云存储用量 | `cloud-storage.718afb24` | 信息展示 | 不适用 | — |
| 管理云存储 | `cloud-storage.1cc744fa` | 操作 | 不适用 | — |
| 升级云存储 | `cloud-storage.9d773e3a` | 操作 | 不适用 | — |

### 订阅 — `subscriptions`

Windows 首页 Microsoft 365 和 Xbox 卡片参考

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Microsoft 365 | `subscriptions.1fafdfea` | 信息展示 | 不适用 | — |
| Xbox Game Pass | `subscriptions.462bee9f` | 信息展示 | 不适用 | — |
| 管理订阅 | `subscriptions.2e529b53` | 操作 | 不适用 | — |
| 查看订阅权益 | `subscriptions.a0f44278` | 操作 | 不适用 | — |


<a id="category-time"></a>

## 时间和语言

日期、地区与输入语言

### 日期和时间 — `date-time`

时间同步、时区与日历

页面状态：**未实现**；条目：11；已实现 0 / 未实现 11 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:dateandtime`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 自动设置时间 | `date-time.db451de3` | 开关 | 未实现 | — |
| 自动设置时区 | `date-time.2af5dabe` | 开关 | 未实现 | — |
| 时区 | `date-time.fb2a23dc` | 选择 | 未实现 | — |
| 自动调整夏令时 | `date-time.753113c2` | 开关 | 未实现 | — |
| 手动设置日期和时间 | `date-time.6422d209` | 操作 | 未实现 | — |
| 立即同步 | `date-time.098d06ec` | 操作 | 未实现 | — |
| 时间服务器 | `date-time.7e33a213` | 文本输入 | 未实现 | — |
| 其他日历 | `date-time.d1937ca7` | 选择 | 未实现 | — |
| 显示秒数 | `date-time.3d9b3c71` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Date & time › Set timezone automatically › Timezone | `date-time.reference.7e2d22fe` | 选择 | 未实现 | — |
| Date & time › Show additional calendars in the taskbar | `date-time.reference.d2ebb693` | 选择 | 未实现 | — |

### 语言和区域 — `language`

显示语言、首选语言与区域格式

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:regionlanguage`、`ms-settings:regionformatting`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 显示语言 | `language.9cbb05d0` | 选择 | 未实现 | — |
| 添加首选语言 | `language.187780a3` | 操作 | 未实现 | — |
| 国家或地区 | `language.cc725f51` | 选择 | 未实现 | — |
| 区域格式 | `language.b77c691e` | 选择 | 未实现 | — |
| 语言选项 | `language.feb9d380` | 操作 | 未实现 | — |
| 管理语言设置 | `language.5f7e5146` | 操作 | 未实现 | — |
| 全球语言支持使用 UTF-8 | `language.3fb068b9` | 开关 | 未实现 | — |

### 输入 — `typing`

拼写、文本建议与触摸键盘

页面状态：**未实现**；条目：18；已实现 0 / 未实现 18 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:typing`、`ms-settings:devicestyping-hwkbtextsuggestions`。

相关页面 ID：`keyboard`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 物理键盘文本建议 | `typing.207b56c1` | 开关 | 未实现 | — |
| 多语言文本建议 | `typing.b2ad8556` | 开关 | 未实现 | — |
| 自动更正拼写错误 | `typing.6928bd78` | 开关 | 未实现 | — |
| 突出显示拼写错误 | `typing.6069542b` | 开关 | 未实现 | — |
| 按键声音 | `typing.081118d6` | 开关 | 未实现 | — |
| 句首字母大写 | `typing.247b1cdd` | 开关 | 未实现 | — |
| 双击空格添加句号 | `typing.59c75352` | 开关 | 未实现 | — |
| 双击 Shift 使用大写 | `typing.0bc4c2d7` | 开关 | 未实现 | — |
| 输入见解 | `typing.509b2541` | 操作 | 未实现 | — |
| 高级键盘设置 | `typing.4709bab2` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Typing › Touch Keyboard › Play key sounds as I type | `typing.reference.f2b8f9a3` | 开关 | 未实现 | — |
| Typing › Touch Keyboard › Capitalize the first letter of each sentence | `typing.reference.60050a6c` | 开关 | 未实现 | — |
| Typing › Touch Keyboard › Add a period after I double-tap the Spacebar | `typing.reference.e553e73c` | 开关 | 未实现 | — |
| Typing › Touch Keyboard › Use all uppercase letters when I double-tap Shift | `typing.reference.f932de70` | 开关 | 未实现 | — |
| Typing › Show text suggestions when typing on the physical keyboard | `typing.reference.c7d6bbd6` | 开关 | 未实现 | — |
| Typing › Multilingual text suggestions | `typing.reference.27daeccc` | 开关 | 未实现 | — |
| Typing › Autocorrect misspelled words | `typing.reference.0fa3afa7` | 开关 | 未实现 | — |
| Typing › Highlight misspelled words | `typing.reference.f924c774` | 开关 | 未实现 | — |

### 高级键盘设置 — `keyboard`

输入法切换与默认输入法

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:keyboard`、`ms-settings:keyboard-advanced`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 替代默认输入法 | `keyboard.9a05b740` | 选择 | 未实现 | — |
| 每个应用使用不同输入法 | `keyboard.0a36a21a` | 开关 | 未实现 | — |
| 使用桌面语言栏 | `keyboard.c7f2c70f` | 开关 | 未实现 | — |
| 输入语言热键 | `keyboard.a6a3d5c6` | 操作 | 未实现 | — |
| 语言栏选项 | `keyboard.5c8d8c52` | 操作 | 未实现 | — |

### 语音 — `speech`

识别语言、声音与麦克风

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:speech`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 语音语言 | `speech.48cd0efa` | 选择 | 未实现 | — |
| 识别非母语口音 | `speech.2ef677a1` | 开关 | 未实现 | — |
| 语音 | `speech.7a73e125` | 选择 | 未实现 | — |
| 语速 | `speech.74737477` | 滑块 | 未实现 | — |
| 预览声音 | `speech.3e0d83e2` | 操作 | 未实现 | — |
| 添加语音 | `speech.c47063f5` | 操作 | 未实现 | — |
| 设置麦克风 | `speech.56f17992` | 操作 | 未实现 | — |

### 日语 Microsoft IME — `regionlanguage-jpnime`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-jpnime`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-jpnime.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-jpnime.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-jpnime.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-jpnime.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-jpnime.9be757c1` | 操作 | 不适用 | — |

### 注音输入法 — `regionlanguage-bpmfime`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-bpmfime`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-bpmfime.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-bpmfime.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-bpmfime.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-bpmfime.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-bpmfime.9be757c1` | 操作 | 不适用 | — |

### 仓颉输入法 — `regionlanguage-cangjieime`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-cangjieime`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-cangjieime.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-cangjieime.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-cangjieime.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-cangjieime.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-cangjieime.9be757c1` | 操作 | 不适用 | — |

### 五笔用户词典 — `regionlanguage-chsime-wubi-udp`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-chsime-wubi-udp`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-chsime-wubi-udp.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-chsime-wubi-udp.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-chsime-wubi-udp.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-chsime-wubi-udp.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-chsime-wubi-udp.9be757c1` | 操作 | 不适用 | — |

### 速成输入法 — `regionlanguage-quickime`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-quickime`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-quickime.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-quickime.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-quickime.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-quickime.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-quickime.9be757c1` | 操作 | 不适用 | — |

### 韩语 Microsoft IME — `regionlanguage-korime`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-korime`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-korime.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-korime.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-korime.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-korime.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-korime.9be757c1` | 操作 | 不适用 | — |

### 微软拼音 — `regionlanguage-chsime-pinyin`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-chsime-pinyin`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-chsime-pinyin.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-chsime-pinyin.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-chsime-pinyin.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-chsime-pinyin.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-chsime-pinyin.9be757c1` | 操作 | 不适用 | — |

### 拼音专业词典 — `regionlanguage-chsime-pinyin-domainlexicon`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-chsime-pinyin-domainlexicon`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-chsime-pinyin-domainlexicon.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-chsime-pinyin-domainlexicon.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-chsime-pinyin-domainlexicon.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-chsime-pinyin-domainlexicon.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-chsime-pinyin-domainlexicon.9be757c1` | 操作 | 不适用 | — |

### 拼音按键设置 — `regionlanguage-chsime-pinyin-keyconfig`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-chsime-pinyin-keyconfig`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-chsime-pinyin-keyconfig.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-chsime-pinyin-keyconfig.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-chsime-pinyin-keyconfig.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-chsime-pinyin-keyconfig.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-chsime-pinyin-keyconfig.9be757c1` | 操作 | 不适用 | — |

### 拼音用户词典 — `regionlanguage-chsime-pinyin-udp`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-chsime-pinyin-udp`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-chsime-pinyin-udp.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-chsime-pinyin-udp.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-chsime-pinyin-udp.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-chsime-pinyin-udp.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-chsime-pinyin-udp.9be757c1` | 操作 | 不适用 | — |

### 微软五笔 — `regionlanguage-chsime-wubi`

Windows 输入法选项参考

页面状态：**不适用**；条目：5；已实现 0 / 未实现 0 / 不适用 5。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:regionlanguage-chsime-wubi`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 默认输入模式 | `regionlanguage-chsime-wubi.59c4e62a` | 选择 | 不适用 | — |
| 候选窗口 | `regionlanguage-chsime-wubi.00473b0c` | 选择 | 不适用 | — |
| 云候选建议 | `regionlanguage-chsime-wubi.01c381ff` | 开关 | 不适用 | — |
| 用户词典 | `regionlanguage-chsime-wubi.953dcd7c` | 操作 | 不适用 | — |
| 按键设置 | `regionlanguage-chsime-wubi.9be757c1` | 操作 | 不适用 | — |


<a id="category-gaming"></a>

## 游戏

游戏模式、录制与快捷键

### 游戏栏 — `game-bar`

录制入口与快捷键参考

页面状态：**未实现**；条目：13；已实现 0 / 未实现 13 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:gaming-gamebar`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 使用控制器打开游戏栏 | `game-bar.ea0a7460` | 开关 | 未实现 | — |
| 自定义快捷键 | `game-bar.cb1b0cb0` | 操作 | 未实现 | — |
| 打开游戏栏快捷键 | `game-bar.96f83311` | 文本输入 | 未实现 | — |
| 截图快捷键 | `game-bar.4c21a586` | 文本输入 | 未实现 | — |
| 录制快捷键 | `game-bar.8c6677b3` | 文本输入 | 未实现 | — |
| 麦克风快捷键 | `game-bar.cb09c7dd` | 文本输入 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Game Bar | `game-bar.reference.2c2d66f8` | 开关 | 未实现 | — |
| Game Bar shortcuts (in-app settings) › Game Bar (Win + G) | `game-bar.reference.c2ddeb9e` | 开关 | 未实现 | — |
| Game Bar shortcuts (in-app settings) › Take a screenshot (Win + Alt + PrtScrn) | `game-bar.reference.08b320f8` | 开关 | 未实现 | — |
| Game Bar shortcuts (in-app settings) › Record last 30 seconds (Win + Alt + G) | `game-bar.reference.20695066` | 开关 | 未实现 | — |
| Game Bar shortcuts (in-app settings) › Start/stop recording (Win + Alt + R) | `game-bar.reference.b67958ca` | 开关 | 未实现 | — |
| Game Bar shortcuts (in-app settings) › Microphone on/off (Win + Alt + M) | `game-bar.reference.f983d88b` | 开关 | 未实现 | — |
| Game Bar shortcuts (in-app settings) › HDR on/off (Win + Alt + B) | `game-bar.reference.9bc24c92` | 开关 | 未实现 | — |

### 摄像与录制 — `captures`

录制目录、质量与音频

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:gaming-gamedvr`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 录制保存目录 | `captures.83b75112` | 文本输入 | 未实现 | — |
| 录制刚刚发生的内容 | `captures.dc4c5631` | 开关 | 未实现 | — |
| 最长录制时长 | `captures.ae31435d` | 选择 | 未实现 | — |
| 录制音频 | `captures.21ad33bd` | 开关 | 未实现 | — |
| 麦克风音量 | `captures.cdc9e129` | 滑块 | 未实现 | — |
| 系统音量 | `captures.d17879a4` | 滑块 | 未实现 | — |
| 视频帧率 | `captures.720a9c6c` | 选择 | 未实现 | — |
| 视频质量 | `captures.327df78f` | 选择 | 未实现 | — |
| 录制鼠标指针 | `captures.70b4169d` | 开关 | 未实现 | — |

### 游戏模式 — `game-mode`

游戏优化与相关图形设置

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:gaming-gamemode`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 游戏模式 | `game-mode.65634ae8` | 开关 | 未实现 | — |
| 图形性能选项 | `game-mode.3df22bbd` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Game Mode | `game-mode.reference.9424db05` | 选择 | 未实现 | — |

### Xbox 模式 — `xbox-mode`

全屏游戏会话参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:gaming-fullscreen`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 启用 Xbox 模式 | `xbox-mode.43ced550` | 开关 | 不适用 | — |
| 默认游戏应用 | `xbox-mode.b7596ef6` | 选择 | 不适用 | — |
| 启动时进入全屏 | `xbox-mode.815d8436` | 开关 | 不适用 | — |

### TruePlay — `trueplay`

已移除的 Windows 游戏功能参考

页面状态：**不适用**；条目：1；已实现 0 / 未实现 0 / 不适用 1。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:gaming-trueplay`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 功能状态 | `trueplay.540cc78d` | 信息展示 | 不适用 | — |


<a id="category-accessibility"></a>

## 辅助功能

视觉、听觉与交互

### 文本大小 — `text-size`

调整系统文字的可读性

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-display`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 文本大小 | `text-size.a4a0d6b4` | 滑块 | 未实现 | — |
| 应用文本大小 | `text-size.71eba864` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Text Size › Text Size | `text-size.reference.8ff6836a` | 选择 | 未实现 | — |

### 视觉效果 — `visual-effects`

动画、透明度与通知时长

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-visualeffects`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 始终显示滚动条 | `visual-effects.fe13858e` | 开关 | 未实现 | — |
| 透明效果 | `visual-effects.3630e7d0` | 开关 | 未实现 | — |
| 动画效果 | `visual-effects.321355a5` | 开关 | 未实现 | — |
| 通知显示时长 | `visual-effects.db944e6b` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Visual effects › Always show scrollbars | `visual-effects.reference.22476e4b` | 开关 | 未实现 | — |
| Visual effects › Transparency effects | `visual-effects.reference.8e1825a1` | 开关 | 未实现 | — |
| Visual effects › Animation effects | `visual-effects.reference.6aa5bc02` | 开关 | 未实现 | — |
| Visual effects › Dismiss notifications after preferred amount of time | `visual-effects.reference.5b6b06b4` | 选择 | 未实现 | — |

### 鼠标指针和触控 — `pointer`

指针样式、尺寸与触控提示

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-mousepointer`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 指针样式 | `pointer.6de7c60b` | 选择 | 未实现 | — |
| 自定义指针颜色 | `pointer.86209eba` | 颜色 | 未实现 | — |
| 指针大小 | `pointer.e8c2f48c` | 滑块 | 未实现 | — |
| 触控指示器 | `pointer.09f053c7` | 开关 | 未实现 | — |
| 加深并放大触控指示器 | `pointer.14b7860f` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mouse pointer and touch › Mouse pointer style | `pointer.reference.8a9af3b1` | 选择 | 未实现 | — |
| Mouse pointer and touch › Size | `pointer.reference.966d030b` | 选择 | 未实现 | — |
| Mouse pointer and touch › Touch indicator | `pointer.reference.09b6b51e` | 开关 | 未实现 | — |
| Mouse pointer and touch › Make the touch indicator circle darker and larger | `pointer.reference.5ed3015e` | 开关 | 未实现 | — |

### 文本光标 — `text-cursor`

指示器颜色与光标粗细

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-cursor`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 文本光标指示器 | `text-cursor.bb54f6b0` | 开关 | 未实现 | — |
| 指示器大小 | `text-cursor.5829d690` | 滑块 | 未实现 | — |
| 指示器颜色 | `text-cursor.d04d1b72` | 颜色 | 未实现 | — |
| 文本光标粗细 | `text-cursor.60ececbf` | 滑块 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Text cursor › Text cursor indicator › Text cursor indicator size | `text-cursor.reference.4c40f3ca` | 滑块 | 未实现 | — |
| Text cursor › Text cursor indicator › Text cursor indicator color | `text-cursor.reference.b0cd3942` | 选择 | 未实现 | — |
| Text cursor › Text cursor thickness | `text-cursor.reference.7beee9f0` | 滑块 | 未实现 | — |

### 放大镜 — `magnifier`

缩放、视图与跟随行为

页面状态：**未实现**；条目：30；已实现 0 / 未实现 30 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-magnifier`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 放大镜 | `magnifier.0398d9d8` | 开关 | 未实现 | — |
| 登录前启动 | `magnifier.21f929d8` | 开关 | 未实现 | — |
| 登录后启动 | `magnifier.c42bf921` | 开关 | 未实现 | — |
| 缩放级别 | `magnifier.618e6091` | 滑块 | 未实现 | — |
| 缩放增量 | `magnifier.b9f2d9f8` | 选择 | 未实现 | — |
| 视图 | `magnifier.cebbb470` | 选择 | 未实现 | — |
| 跟随鼠标指针 | `magnifier.b5377eb2` | 开关 | 未实现 | — |
| 跟随键盘焦点 | `magnifier.e54d3c2b` | 开关 | 未实现 | — |
| 跟随文本光标 | `magnifier.5cffca3c` | 开关 | 未实现 | — |
| 跟随讲述人光标 | `magnifier.7fea4dd7` | 开关 | 未实现 | — |
| 透镜宽度 | `magnifier.eb3a7a29` | 滑块 | 未实现 | — |
| 透镜高度 | `magnifier.2750621a` | 滑块 | 未实现 | — |
| 反色 | `magnifier.f7ddef87` | 开关 | 未实现 | — |
| 平滑图像和文本 | `magnifier.edc4f6f3` | 开关 | 未实现 | — |
| 朗读快捷键 | `magnifier.af7b8808` | 文本输入 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Magnifier › Magnifier (toggle) › Start Magnifier before sign-in | `magnifier.reference.54348147` | 开关 | 未实现 | — |
| Magnifier › Magnifier (toggle) › Start Magnifier after sign-in | `magnifier.reference.0a370c37` | 开关 | 未实现 | — |
| Magnifier › Zoom level | `magnifier.reference.05c8bf1b` | 滑块 | 未实现 | — |
| Magnifier › Zoom increment | `magnifier.reference.027b1d5b` | 滑块 | 未实现 | — |
| Magnifier › View › View preference | `magnifier.reference.f46dfa93` | 选择 | 未实现 | — |
| Magnifier › View › Have Magnifier follow my (when selected Docked and Full Screen View) › Mouse pointer | `magnifier.reference.353f0bce` | 开关 | 未实现 | — |
| Magnifier › View › Have Magnifier follow my (when selected Docked and Full Screen View) › Keyboard focus | `magnifier.reference.3b4676ec` | 开关 | 未实现 | — |
| Magnifier › View › Have Magnifier follow my (when selected Docked and Full Screen View) › Text cursor | `magnifier.reference.709e0120` | 开关 | 未实现 | — |
| Magnifier › View › Have Magnifier follow my (when selected Docked and Full Screen View) › Narrator cursor | `magnifier.reference.38c4b18b` | 开关 | 未实现 | — |
| Magnifier › View › Change lens size (when selected Lens View) › Height / Width sliders | `magnifier.reference.7dec5770` | 滑块 | 未实现 | — |
| Magnifier › View › Keep the mouse pointer location (when selected Full Screen View) | `magnifier.reference.16d01cce` | 开关 | 未实现 | — |
| Magnifier › View › Keep the text cursor location (when selected Full Screen View) | `magnifier.reference.3b25fbba` | 开关 | 未实现 | — |
| Magnifier › View › Invert Colors | `magnifier.reference.54f55938` | 选择 | 未实现 | — |
| Magnifier › View › Smooth edges of images and text | `magnifier.reference.16440b75` | 开关 | 未实现 | — |
| Magnifier › View › Reading shortcut | `magnifier.reference.164500de` | 选择 | 未实现 | — |

### 颜色筛选器 — `color-filters`

色觉辅助与快捷键

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-colorfilter`、`ms-settings:easeofaccess-colorfilter-adaptivecolorlink`、`ms-settings:easeofaccess-colorfilter-bluelightlink`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 颜色筛选器 | `color-filters.e71f8ff5` | 开关 | 未实现 | — |
| 筛选器 | `color-filters.1242069d` | 选择 | 未实现 | — |
| 筛选器键盘快捷键 | `color-filters.c95fb3d5` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Color filters › Color filters | `color-filters.reference.93c3c16a` | 选择 | 未实现 | — |
| Color filters › Preferred color filter selection | `color-filters.reference.d1a1684b` | 选择 | 未实现 | — |
| Color filters › Keyboard shortcut for color filters | `color-filters.reference.3a55c85c` | 选择 | 未实现 | — |

### 对比度主题 — `contrast`

高对比度主题和自定义色彩

页面状态：**未实现**；条目：16；已实现 0 / 未实现 16 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-highcontrast`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 主题 | `contrast.e848ddd4` | 选择 | 未实现 | — |
| 背景颜色 | `contrast.4a2d8a28` | 颜色 | 未实现 | — |
| 文字颜色 | `contrast.07f568da` | 颜色 | 未实现 | — |
| 超链接颜色 | `contrast.58aecbd7` | 颜色 | 未实现 | — |
| 禁用文字颜色 | `contrast.9d947f02` | 颜色 | 未实现 | — |
| 选中文字颜色 | `contrast.450ad5bc` | 颜色 | 未实现 | — |
| 按钮文字颜色 | `contrast.e0124b6b` | 颜色 | 未实现 | — |
| 应用对比度主题 | `contrast.88185761` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Contrast themes › Contrast Themes | `contrast.reference.08c75109` | 选择 | 未实现 | — |
| Contrast themes › Choose a theme | `contrast.reference.2f32f7fc` | 选择 | 未实现 | — |
| Contrast themes › Text | `contrast.reference.4ef5eef9` | 开关 | 未实现 | — |
| Contrast themes › Hyperlinks | `contrast.reference.01e89338` | 开关 | 未实现 | — |
| Contrast themes › Disabled Text | `contrast.reference.15794103` | 开关 | 未实现 | — |
| Contrast themes › Selected Text | `contrast.reference.d200a697` | 开关 | 未实现 | — |
| Contrast themes › Button Text | `contrast.reference.ea31e5bf` | 开关 | 未实现 | — |
| Contrast themes › Background | `contrast.reference.3fb30d73` | 开关 | 未实现 | — |

### 屏幕阅读器 — `narrator`

语音、详细程度与光标

页面状态：**未实现**；条目：65；已实现 0 / 未实现 65 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-narrator`、`ms-settings:easeofaccess-narrator-isautostartenabled`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 讲述人 | `narrator.7de905aa` | 开关 | 未实现 | — |
| 登录前启动 | `narrator.21f929d8` | 开关 | 未实现 | — |
| 登录后启动 | `narrator.c42bf921` | 开关 | 未实现 | — |
| 键盘快捷键 | `narrator.021cf99c` | 开关 | 未实现 | — |
| 启动时显示主页 | `narrator.711fb05d` | 开关 | 未实现 | — |
| 声音 | `narrator.ab9ff81d` | 选择 | 未实现 | — |
| 语速 | `narrator.74737477` | 滑块 | 未实现 | — |
| 音调 | `narrator.bf36f9d8` | 滑块 | 未实现 | — |
| 音量 | `narrator.1aa999a5` | 滑块 | 未实现 | — |
| 朗读时降低其他应用音量 | `narrator.ec0a8ee8` | 开关 | 未实现 | — |
| 详细程度 | `narrator.cf87e928` | 选择 | 未实现 | — |
| 朗读格式变化 | `narrator.40c0b763` | 开关 | 未实现 | — |
| 按字符朗读时使用语音拼读 | `narrator.51f65979` | 开关 | 未实现 | — |
| 标点处停顿 | `narrator.d84ce611` | 开关 | 未实现 | — |
| 朗读高级控件帮助 | `narrator.492635a8` | 开关 | 未实现 | — |
| 大写文字朗读方式 | `narrator.eaf16e86` | 选择 | 未实现 | — |
| 控件上下文级别 | `narrator.39056697` | 选择 | 未实现 | — |
| 朗读交互提示 | `narrator.94e0cadb` | 开关 | 未实现 | — |
| 解释不可执行的操作 | `narrator.b5086345` | 开关 | 未实现 | — |
| 声音代替常用播报 | `narrator.fd4018ae` | 开关 | 未实现 | — |
| 朗读控件详细信息 | `narrator.aa9912c5` | 开关 | 未实现 | — |
| 朗读输入字符 | `narrator.2db63053` | 开关 | 未实现 | — |
| 朗读输入单词 | `narrator.73386aca` | 开关 | 未实现 | — |
| 朗读功能键 | `narrator.eea5ecd2` | 开关 | 未实现 | — |
| 朗读导航键 | `narrator.d5d97fcb` | 开关 | 未实现 | — |
| 朗读锁定键 | `narrator.6d524a17` | 开关 | 未实现 | — |
| 朗读修饰键 | `narrator.e9b26889` | 开关 | 未实现 | — |
| 讲述人键 | `narrator.d43e692e` | 选择 | 未实现 | — |
| 抬手时激活触摸键 | `narrator.15a20ebd` | 开关 | 未实现 | — |
| 鼠标朗读屏幕 | `narrator.94935b9e` | 开关 | 未实现 | — |
| 光标跟随鼠标 | `narrator.d26dc234` | 开关 | 未实现 | — |
| 显示讲述人光标 | `narrator.ec048ee8` | 开关 | 未实现 | — |
| 同步文本光标 | `narrator.e1afa623` | 开关 | 未实现 | — |
| 同步系统焦点 | `narrator.46d9f44c` | 开关 | 未实现 | — |
| 讲述人扩展 | `narrator.7f4b6188` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Narrator › Narrator (toggle) › Start Narrator before sign-in | `narrator.reference.eda89fb6` | 开关 | 未实现 | — |
| Narrator › Narrator (toggle) › Start Narrator after sign-in | `narrator.reference.385fc6f8` | 开关 | 未实现 | — |
| Narrator › Keyboard shortcut for Narrator | `narrator.reference.257eaf83` | 选择 | 未实现 | — |
| Narrator › Narrator Home › Show Narrator Home when Narrator starts | `narrator.reference.5d68306a` | 开关 | 未实现 | — |
| Narrator › Choose a voice › Speed | `narrator.reference.292ae141` | 滑块 | 未实现 | — |
| Narrator › Choose a voice › Pitch | `narrator.reference.10c29e0c` | 滑块 | 未实现 | — |
| Narrator › Choose a voice › Volume | `narrator.reference.36f3b8e5` | 滑块 | 未实现 | — |
| Narrator › Lower the volume of other apps when Narrator is speaking | `narrator.reference.05dc20b9` | 滑块 | 未实现 | — |
| Narrator › Verbosity level › Emphasize formatted text | `narrator.reference.db00112d` | 选择 | 未实现 | — |
| Narrator › Verbosity level › Read phonetically when reading by character | `narrator.reference.8b69d44f` | 开关 | 未实现 | — |
| Narrator › Verbosity level › Pause slightly when reading punctuation | `narrator.reference.104339a2` | 开关 | 未实现 | — |
| Narrator › Verbosity level › Read advanced details like help text on buttons and other controls | `narrator.reference.57fc18dc` | 开关 | 未实现 | — |
| Narrator › Change how capitalized text is read | `narrator.reference.4f442eb5` | 开关 | 未实现 | — |
| Narrator › Context level for buttons and controls › Read hints on how to interact with buttons and other controls | `narrator.reference.cbb531ac` | 开关 | 未实现 | — |
| Narrator › Context level for buttons and controls › Tell me why actions can't be performed | `narrator.reference.29167366` | 开关 | 未实现 | — |
| Narrator › Context level for buttons and controls › Play sounds instead of announcements for common actions | `narrator.reference.a3b181a7` | 开关 | 未实现 | — |
| Narrator › Context level for buttons and controls › Tell me details about buttons and other controls | `narrator.reference.203122a4` | 开关 | 未实现 | — |
| Narrator › Have Narrator announce when I type › Letters, numbers, and punctuation | `narrator.reference.4af62bdf` | 开关 | 未实现 | — |
| Narrator › Have Narrator announce when I type › Words | `narrator.reference.90a5b7a3` | 开关 | 未实现 | — |
| Narrator › Have Narrator announce when I type › Function keys | `narrator.reference.d8b45f58` | 开关 | 未实现 | — |
| Narrator › Have Narrator announce when I type › Arrow, Tab, and other navigation keys | `narrator.reference.912b4b1e` | 开关 | 未实现 | — |
| Narrator › Have Narrator announce when I type › Toggle keys, like Caps lock and Num lock | `narrator.reference.7c37961a` | 开关 | 未实现 | — |
| Narrator › Have Narrator announce when I type › Shift, Alt, and other modifier keys | `narrator.reference.4c9af18e` | 开关 | 未实现 | — |
| Narrator › Narrator key | `narrator.reference.d4ef110b` | 选择 | 未实现 | — |
| Narrator › On touch keyboards, activate keys when I lift my finger | `narrator.reference.e8183e12` | 开关 | 未实现 | — |
| Narrator › Read and interact with the screen using the mouse › Have the Narrator cursor follow my mouse | `narrator.reference.27190ac0` | 开关 | 未实现 | — |
| Narrator › Show the Narrator cursor | `narrator.reference.e91a6959` | 开关 | 未实现 | — |
| Narrator › Move my text cursor with the Narrator cursor as Narrator reads text | `narrator.reference.bf4148da` | 开关 | 未实现 | — |
| Narrator › Sync the Narrator cursor and system focus | `narrator.reference.e90861de` | 开关 | 未实现 | — |
| Narrator › Enable Narrator Extensions | `narrator.reference.14f46908` | 开关 | 未实现 | — |

### 音频辅助 — `accessibility-audio`

单声道与声音视觉提示

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-audio`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 单声道音频 | `accessibility-audio.1a90a9eb` | 开关 | 未实现 | — |
| 音频通知闪烁 | `accessibility-audio.49a25e92` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Audio › Mono Audio | `accessibility-audio.reference.0d993fdd` | 开关 | 未实现 | — |
| Audio › Flash my screen during audio notifications | `accessibility-audio.reference.380697ec` | 开关 | 未实现 | — |

### 字幕 — `captions`

实时字幕、位置与外观

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-closedcaptioning`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 实时字幕 | `captions.ac8a8db0` | 开关 | 未实现 | — |
| 过滤不雅内容 | `captions.ddbbae5a` | 开关 | 未实现 | — |
| 字幕位置 | `captions.d31e8823` | 选择 | 未实现 | — |
| 字幕样式 | `captions.41085f11` | 选择 | 未实现 | — |
| 编辑字幕样式 | `captions.9fe387bc` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Captions › Live Captions › Filter Profanity | `captions.reference.b233720a` | 开关 | 未实现 | — |
| Captions › Live Captions › Position | `captions.reference.07051098` | 选择 | 未实现 | — |
| Captions › Caption Style | `captions.reference.0472a68c` | 选择 | 未实现 | — |

### 语音访问 — `voice-access`

通过语音控制设备

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-speechrecognition`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 语音访问 | `voice-access.3712e4ef` | 开关 | 未实现 | — |
| 登录后启动 | `voice-access.c42bf921` | 开关 | 未实现 | — |
| 登录前启动 | `voice-access.21f929d8` | 开关 | 未实现 | — |
| 语音访问语言 | `voice-access.26a8d374` | 选择 | 未实现 | — |
| 设置麦克风 | `voice-access.56f17992` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Speech › Voice access (main toggle) › Start voice access after you sign in to your PC | `voice-access.reference.1353c86e` | 开关 | 未实现 | — |
| Speech › Voice access (main toggle) › Start voice access before you sign in to your PC | `voice-access.reference.5c4cd1f8` | 开关 | 未实现 | — |

### 键盘辅助 — `accessibility-keyboard`

粘滞键、筛选键与屏幕键盘

页面状态：**未实现**；条目：40；已实现 0 / 未实现 40 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-keyboard`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 粘滞键 | `accessibility-keyboard.68b234ce` | 开关 | 未实现 | — |
| 粘滞键快捷键 | `accessibility-keyboard.841c4322` | 开关 | 未实现 | — |
| 显示粘滞键图标 | `accessibility-keyboard.715c940f` | 开关 | 未实现 | — |
| 连续按两次锁定修饰键 | `accessibility-keyboard.fb47ad4a` | 开关 | 未实现 | — |
| 同时按两个键时关闭 | `accessibility-keyboard.14c24f2f` | 开关 | 未实现 | — |
| 按下和释放快捷键时播放声音 | `accessibility-keyboard.97f39b35` | 开关 | 未实现 | — |

#### 筛选键

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 筛选键 | `accessibility-keyboard.97ddab93` | 开关 | 未实现 | — |
| 筛选键快捷键 | `accessibility-keyboard.92ad3aa0` | 开关 | 未实现 | — |
| 显示筛选键图标 | `accessibility-keyboard.5d234460` | 开关 | 未实现 | — |
| 按键时发出提示音 | `accessibility-keyboard.5b712c8f` | 开关 | 未实现 | — |
| 忽略快速击键 | `accessibility-keyboard.643a1e0a` | 开关 | 未实现 | — |
| 接受击键前等待 | `accessibility-keyboard.1ce6181f` | 选择 | 未实现 | — |
| 忽略意外重复击键 | `accessibility-keyboard.d556de2d` | 开关 | 未实现 | — |
| 重复击键等待 | `accessibility-keyboard.bc491238` | 选择 | 未实现 | — |
| 忽略重复击键 | `accessibility-keyboard.a272bfd3` | 开关 | 未实现 | — |
| 首次重复等待 | `accessibility-keyboard.676ac6a7` | 选择 | 未实现 | — |
| 后续重复等待 | `accessibility-keyboard.a0212e71` | 选择 | 未实现 | — |

#### 其他

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 切换键 | `accessibility-keyboard.9667278b` | 开关 | 未实现 | — |
| 辅助按键通知 | `accessibility-keyboard.84b1c363` | 开关 | 未实现 | — |
| 开关辅助按键时播放声音 | `accessibility-keyboard.0c6593c1` | 开关 | 未实现 | — |
| 为访问键加下划线 | `accessibility-keyboard.791e84ff` | 开关 | 未实现 | — |
| Print Screen 打开截图 | `accessibility-keyboard.cc8561a8` | 开关 | 未实现 | — |
| 屏幕键盘 | `accessibility-keyboard.8654a9c6` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Keyboard › Sticky keys (main toggle) › Keyboard shortcut for Sticky keys | `accessibility-keyboard.reference.1766f98b` | 选择 | 未实现 | — |
| Keyboard › Sticky keys (main toggle) › Show the sticky keys icon on the taskbar | `accessibility-keyboard.reference.cb1dbaf2` | 开关 | 未实现 | — |
| Keyboard › Sticky keys (main toggle) › Lock shortcut keys when pressed twice in a row | `accessibility-keyboard.reference.c06b6443` | 选择 | 未实现 | — |
| Keyboard › Sticky keys (main toggle) › Turn off Sticky keys when two keys are pressed at the same time › Play a sound when shortcut keys are pressed and released | `accessibility-keyboard.reference.59e11b79` | 选择 | 未实现 | — |
| Keyboard › Filter keys (main toggle) | `accessibility-keyboard.reference.8fdb2ef9` | 开关 | 未实现 | — |
| Keyboard › Keyboard shortcut for Filter keys | `accessibility-keyboard.reference.61d353a2` | 选择 | 未实现 | — |
| Keyboard › Show the Filter keys icon on the taskbar | `accessibility-keyboard.reference.e15cf0d4` | 开关 | 未实现 | — |
| Keyboard › Beep when keys are pressed | `accessibility-keyboard.reference.78978487` | 开关 | 未实现 | — |
| Keyboard › Ignore quick keystrokes › Wait before accepting a keystroke | `accessibility-keyboard.reference.4440fbf5` | 开关 | 未实现 | — |
| Keyboard › Ignore unintended keystrokes (bounce keys) › Wait before accepting repeated keystrokes | `accessibility-keyboard.reference.bf8c6dd7` | 开关 | 未实现 | — |
| Keyboard › Ignore repeated keystrokes (repeat keys) › Wait before accepting the first repeated keystroke | `accessibility-keyboard.reference.28c292fb` | 开关 | 未实现 | — |
| Keyboard › Ignore repeated keystrokes (repeat keys) › Wait before accepting subsequent repeated keystrokes | `accessibility-keyboard.reference.bb32e872` | 开关 | 未实现 | — |
| Keyboard › Toggle keys | `accessibility-keyboard.reference.dd8bff2c` | 开关 | 未实现 | — |
| Keyboard › Notification preferences › Notify me when I turn on Sticky, Filter, or Toggle keys from the keyboard | `accessibility-keyboard.reference.fa916f67` | 开关 | 未实现 | — |
| Keyboard › Notification preferences › Play a sound when I turn Sticky, Filter, or Toggle keys on or off from the keyboard | `accessibility-keyboard.reference.8754adfd` | 开关 | 未实现 | — |
| Keyboard › Underline acess keys | `accessibility-keyboard.reference.4a5a5e4c` | 开关 | 未实现 | — |
| Keyboard › Use the print screen to open screen capture | `accessibility-keyboard.reference.6f3d637b` | 开关 | 未实现 | — |

### 鼠标键 — `mouse-keys`

使用数字键盘移动指针

页面状态：**未实现**；条目：12；已实现 0 / 未实现 12 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-mouse`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 鼠标键 | `mouse-keys.af8ff2e3` | 开关 | 未实现 | — |
| 仅 Num Lock 开启时使用 | `mouse-keys.2625b861` | 开关 | 未实现 | — |
| 显示鼠标键图标 | `mouse-keys.21f5aea4` | 开关 | 未实现 | — |
| Ctrl 加速和 Shift 减速 | `mouse-keys.28c033e9` | 开关 | 未实现 | — |
| 鼠标键速度 | `mouse-keys.7754307e` | 滑块 | 未实现 | — |
| 鼠标键加速度 | `mouse-keys.06700d63` | 滑块 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mouse › Mouse keys | `mouse-keys.reference.da0c9570` | 开关 | 未实现 | — |
| Mouse › Mouse keys (main toggle) › Only use mouse keys when Num lock is on | `mouse-keys.reference.bdf1cbf2` | 开关 | 未实现 | — |
| Mouse › Mouse keys (main toggle) › Show the mouse keys icon on the taskbar | `mouse-keys.reference.f113b78d` | 开关 | 未实现 | — |
| Mouse › Mouse keys (main toggle) › Hold the Ctrl key to speed up and the Shift key to slow down | `mouse-keys.reference.4f1675d1` | 滑块 | 未实现 | — |
| Mouse › Mouse keys (main toggle) › Mouse keys speed | `mouse-keys.reference.fe021cfe` | 滑块 | 未实现 | — |
| Mouse › Mouse keys (main toggle) › Mouse keys acceleration | `mouse-keys.reference.df0cfb8c` | 滑块 | 未实现 | — |

### 眼动控制 — `eye-control`

眼动设备、停留与指针

页面状态：**未实现**；条目：22；已实现 0 / 未实现 22 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-eyecontrol`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 眼动控制 | `eye-control.4f780bcb` | 开关 | 未实现 | — |
| 单击方式 | `eye-control.c4f9e8b6` | 选择 | 未实现 | — |
| 显示注视光标 | `eye-control.f1f7bb34` | 开关 | 未实现 | — |
| 形状书写 | `eye-control.9d4cca2d` | 开关 | 未实现 | — |
| 高级鼠标功能 | `eye-control.cfdf7df6` | 开关 | 未实现 | — |
| 输入停留时间 | `eye-control.969166aa` | 滑块 | 未实现 | — |
| 常规停留时间 | `eye-control.cbc0cef4` | 滑块 | 未实现 | — |
| 平滑 | `eye-control.ab22223d` | 滑块 | 未实现 | — |
| 延迟 | `eye-control.e9f09214` | 滑块 | 未实现 | — |
| 停靠位置 | `eye-control.ca848e41` | 选择 | 未实现 | — |
| 键盘停靠按钮 | `eye-control.9e089fc0` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Eye Control › Eye Control (toggle) | `eye-control.reference.907d9244` | 开关 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Choose how to "click" - Click by dwelling/with a switch | `eye-control.reference.21352930` | 选择 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Show gaze cursor | `eye-control.reference.6a77b7f2` | 开关 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Use shape writing | `eye-control.reference.d6f76a93` | 开关 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Use advanced mouse features | `eye-control.reference.4b13d6bb` | 开关 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Typing dwell time | `eye-control.reference.78e70cc1` | 滑块 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › General dwell time | `eye-control.reference.cd2d145c` | 滑块 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Smoothing | `eye-control.reference.116858e7` | 滑块 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Lag | `eye-control.reference.20b71f9e` | 滑块 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Dock bottom | `eye-control.reference.2938eea9` | 选择 | 未实现 | — |
| Eye Control › Gaze app (Eye Control in-app settings) › Keyboard dock button | `eye-control.reference.da32acee` | 选择 | 未实现 | — |

### 听力设备 — `hearing`

蓝牙 LE Audio 助听设备

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-hearingaids`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 添加听力设备 | `hearing.111c1d53` | 操作 | 未实现 | — |
| 预设 | `hearing.9a0158b4` | 选择 | 未实现 | — |
| 左耳音量 | `hearing.62883390` | 滑块 | 未实现 | — |
| 右耳音量 | `hearing.d5119674` | 滑块 | 未实现 | — |
| 麦克风环境音 | `hearing.c5d3fccf` | 开关 | 未实现 | — |


<a id="category-privacy"></a>

## 隐私和安全性

设备安全与应用权限

### 系统安全 — `security`

安全概览与保护区域

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsdefender`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 安全状态 | `security.f4700677` | 信息展示 | 未实现 | — |
| 病毒和威胁防护 | `security.111b451f` | 操作 | 未实现 | — |
| 账户保护 | `security.4fb1be9f` | 操作 | 未实现 | — |
| 防火墙和网络保护 | `security.7934d1e5` | 操作 | 未实现 | — |
| 应用和浏览器控制 | `security.3e8cd48e` | 操作 | 未实现 | — |
| 设备安全 | `security.b23021fa` | 操作 | 未实现 | — |
| 设备性能和运行状况 | `security.dcf23926` | 操作 | 未实现 | — |

### 设备加密 — `encryption`

设备加密与恢复密钥

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:deviceencryption`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 设备加密 | `encryption.47011073` | 开关 | 未实现 | — |
| 备份恢复密钥 | `encryption.850ab6af` | 操作 | 未实现 | — |
| 加密状态 | `encryption.45dd31ac` | 信息展示 | 未实现 | — |

### 查找我的设备 — `find-device`

设备位置与远程查找参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:findmydevice`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 查找我的设备 | `find-device.9436d046` | 开关 | 不适用 | — |
| 查看已关联设备 | `find-device.a33ef3cc` | 操作 | 不适用 | — |

### 常规隐私 — `general-privacy`

推荐内容、广告与应用跟踪

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy`、`ms-settings:privacy-general`、`ms-settings:privacy-advertisingid`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 允许应用使用广告标识符 | `general-privacy.17180bb6` | 开关 | 未实现 | — |
| 网站访问语言列表 | `general-privacy.688b695e` | 开关 | 未实现 | — |
| 跟踪应用启动 | `general-privacy.f06cf7db` | 开关 | 未实现 | — |
| 显示建议的内容 | `general-privacy.c252e344` | 开关 | 未实现 | — |
| 个性化优惠 | `general-privacy.87512f3b` | 开关 | 未实现 | — |

### 在线语音识别 — `online-speech`

云端语音处理参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-speech`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 在线语音识别 | `online-speech.0a66701f` | 开关 | 不适用 | — |
| 管理云端语音数据 | `online-speech.20caf0a6` | 操作 | 不适用 | — |

### 墨迹书写和键入个性化 — `inking`

个人词典与输入改进

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-speechtyping`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 个人墨迹书写和键入词典 | `inking.db87cccf` | 开关 | 未实现 | — |
| 查看个人词典 | `inking.a2290b51` | 操作 | 未实现 | — |
| 清除词典 | `inking.af3aefc5` | 操作 | 未实现 | — |

### 诊断和反馈 — `diagnostics`

诊断数据、改进体验与反馈

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-feedback`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 发送可选诊断数据 | `diagnostics.1670f2f6` | 开关 | 未实现 | — |
| 改进墨迹书写和键入 | `diagnostics.9ed076ac` | 开关 | 未实现 | — |
| 定制体验 | `diagnostics.44f00cc6` | 开关 | 未实现 | — |
| 查看诊断数据 | `diagnostics.e46bf6ba` | 开关 | 未实现 | — |
| 删除诊断数据 | `diagnostics.693a0492` | 操作 | 未实现 | — |
| 反馈频率 | `diagnostics.193e06c4` | 选择 | 未实现 | — |

### 活动历史记录 — `activity`

本地活动记录参考

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-activityhistory`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 在此设备存储活动历史记录 | `activity.4e2323e9` | 开关 | 未实现 | — |
| 清除活动历史记录 | `activity.f6afab60` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Activity history › Store my activity history on this device | `activity.reference.c2152566` | 开关 | 未实现 | — |

### 搜索权限 — `search-permissions`

内容筛选、云内容与搜索记录

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:search-permissions`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 安全搜索 | `search-permissions.17512e70` | 选择 | 未实现 | — |
| 个人账户云内容 | `search-permissions.c7813935` | 开关 | 未实现 | — |
| 工作或学校云内容 | `search-permissions.501e5ac5` | 开关 | 未实现 | — |
| 此设备上的搜索历史记录 | `search-permissions.781a175d` | 开关 | 未实现 | — |
| 清除设备搜索历史记录 | `search-permissions.4a111c5a` | 操作 | 未实现 | — |
| 显示搜索要点 | `search-permissions.34652d10` | 开关 | 未实现 | — |

### 搜索与索引 — `search-index`

索引范围、排除目录与诊断

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:search`、`ms-settings:search-moredetails`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 查找文件 | `search-index.acf33b0f` | 选择 | 未实现 | — |
| 索引时遵守电源设置 | `search-index.5fc76958` | 开关 | 未实现 | — |
| 添加排除文件夹 | `search-index.cd42d36e` | 操作 | 未实现 | — |
| 高级索引选项 | `search-index.0690cd83` | 操作 | 未实现 | — |
| 索引疑难解答 | `search-index.d4c992e9` | 操作 | 未实现 | — |
| 索引状态 | `search-index.5a5afb60` | 信息展示 | 未实现 | — |

### Recall 和快照 — `recall`

Windows AI+ 专属快照参考

页面状态：**不适用**；条目：8；已实现 0 / 未实现 0 / 不适用 8。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 保存快照 | `recall.75bf7faf` | 开关 | 不适用 | — |
| 最大磁盘使用量 | `recall.35e00b88` | 选择 | 不适用 | — |
| 保留时长 | `recall.8c714efb` | 选择 | 不适用 | — |
| 筛选应用 | `recall.08113799` | 操作 | 不适用 | — |
| 筛选网站 | `recall.f4366b8d` | 操作 | 不适用 | — |
| 筛选敏感信息 | `recall.6f074486` | 开关 | 不适用 | — |
| 删除快照 | `recall.5b62e0a8` | 操作 | 不适用 | — |
| 重置 Recall | `recall.6e493e99` | 操作 | 不适用 | — |

### 存在感应权限 — `presence-permissions`

应用对存在感应器的访问

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 存在感应访问 | `presence-permissions.0c794eb6` | 开关 | 未实现 | — |
| 允许应用访问存在感应器 | `presence-permissions.60318dc7` | 开关 | 未实现 | — |
| 允许桌面应用访问存在感应器 | `presence-permissions.77c98092` | 开关 | 未实现 | — |
| 最近访问 | `presence-permissions.249b0d1c` | 信息展示 | 未实现 | — |

### 配件应用 — `privacy-accessoryapps`

应用访问权限与最近活动

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-accessoryapps`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 配件应用权限 | `privacy-accessoryapps.17592407` | 开关 | 不适用 | — |
| 允许应用访问配件应用 | `privacy-accessoryapps.3cdc5c32` | 开关 | 不适用 | — |
| 允许桌面应用访问配件应用 | `privacy-accessoryapps.abbd3539` | 开关 | 不适用 | — |
| 应用访问记录 | `privacy-accessoryapps.bc0f5a5a` | 信息展示 | 不适用 | — |

### 账户信息访问 — `privacy-accountinfo`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-accountinfo`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 账户信息访问权限 | `privacy-accountinfo.c14db834` | 开关 | 未实现 | — |
| 允许应用访问账户信息访问 | `privacy-accountinfo.b3922642` | 开关 | 未实现 | — |
| 允许桌面应用访问账户信息访问 | `privacy-accountinfo.53ddbab7` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-accountinfo.bc0f5a5a` | 信息展示 | 未实现 | — |

### 应用诊断 — `privacy-appdiagnostics`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-appdiagnostics`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 应用诊断权限 | `privacy-appdiagnostics.2bae941b` | 开关 | 未实现 | — |
| 允许应用访问应用诊断 | `privacy-appdiagnostics.cf86a8de` | 开关 | 未实现 | — |
| 允许桌面应用访问应用诊断 | `privacy-appdiagnostics.ca992042` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-appdiagnostics.bc0f5a5a` | 信息展示 | 未实现 | — |

### 自动文件下载 — `privacy-automaticfiledownloads`

应用访问权限与最近活动

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-automaticfiledownloads`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 自动文件下载权限 | `privacy-automaticfiledownloads.62830e87` | 开关 | 不适用 | — |
| 允许应用访问自动文件下载 | `privacy-automaticfiledownloads.4fe8b8e8` | 开关 | 不适用 | — |
| 允许桌面应用访问自动文件下载 | `privacy-automaticfiledownloads.9f89bad5` | 开关 | 不适用 | — |
| 应用访问记录 | `privacy-automaticfiledownloads.bc0f5a5a` | 信息展示 | 不适用 | — |

### 后台应用 — `privacy-backgroundapps`

应用访问权限与最近活动

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-backgroundapps`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 后台应用权限 | `privacy-backgroundapps.bef9974b` | 开关 | 不适用 | — |
| 允许应用访问后台应用 | `privacy-backgroundapps.d50bfa1c` | 开关 | 不适用 | — |
| 允许桌面应用访问后台应用 | `privacy-backgroundapps.d22436de` | 开关 | 不适用 | — |
| 应用访问记录 | `privacy-backgroundapps.bc0f5a5a` | 信息展示 | 不适用 | — |

### 后台空间感知 — `privacy-backgroundspatialperception`

应用访问权限与最近活动

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-backgroundspatialperception`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 后台空间感知权限 | `privacy-backgroundspatialperception.ffd33ca3` | 开关 | 不适用 | — |
| 允许应用访问后台空间感知 | `privacy-backgroundspatialperception.5a4a9f2a` | 开关 | 不适用 | — |
| 允许桌面应用访问后台空间感知 | `privacy-backgroundspatialperception.efd56719` | 开关 | 不适用 | — |
| 应用访问记录 | `privacy-backgroundspatialperception.bc0f5a5a` | 信息展示 | 不适用 | — |

### 日历 — `privacy-calendar`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-calendar`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 日历权限 | `privacy-calendar.592b49d7` | 开关 | 未实现 | — |
| 允许应用访问日历 | `privacy-calendar.a6e2d578` | 开关 | 未实现 | — |
| 允许桌面应用访问日历 | `privacy-calendar.4f84b48b` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-calendar.bc0f5a5a` | 信息展示 | 未实现 | — |

### 通话记录 — `privacy-callhistory`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-callhistory`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 通话记录权限 | `privacy-callhistory.96bc87a0` | 开关 | 未实现 | — |
| 允许应用访问通话记录 | `privacy-callhistory.39e7e03f` | 开关 | 未实现 | — |
| 允许桌面应用访问通话记录 | `privacy-callhistory.7eec1e7e` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-callhistory.bc0f5a5a` | 信息展示 | 未实现 | — |

### 摄像头访问 — `privacy-webcam`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-webcam`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 摄像头访问权限 | `privacy-webcam.bb196d05` | 开关 | 未实现 | — |
| 允许应用访问摄像头访问 | `privacy-webcam.c68d5137` | 开关 | 未实现 | — |
| 允许桌面应用访问摄像头访问 | `privacy-webcam.1dfd1d96` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-webcam.bc0f5a5a` | 信息展示 | 未实现 | — |

### 联系人 — `privacy-contacts`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-contacts`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 联系人权限 | `privacy-contacts.1c5f9f91` | 开关 | 未实现 | — |
| 允许应用访问联系人 | `privacy-contacts.99623b2d` | 开关 | 未实现 | — |
| 允许桌面应用访问联系人 | `privacy-contacts.45a2b39a` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-contacts.bc0f5a5a` | 信息展示 | 未实现 | — |

### 文档 — `privacy-documents`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-documents`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 文档权限 | `privacy-documents.8835bb59` | 开关 | 未实现 | — |
| 允许应用访问文档 | `privacy-documents.9dc435b3` | 开关 | 未实现 | — |
| 允许桌面应用访问文档 | `privacy-documents.408a98a0` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-documents.bc0f5a5a` | 信息展示 | 未实现 | — |

### 下载文件夹 — `privacy-downloadsfolder`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-downloadsfolder`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 下载文件夹权限 | `privacy-downloadsfolder.d7359a4d` | 开关 | 未实现 | — |
| 允许应用访问下载文件夹 | `privacy-downloadsfolder.5d935f1c` | 开关 | 未实现 | — |
| 允许桌面应用访问下载文件夹 | `privacy-downloadsfolder.0f87cc9c` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-downloadsfolder.bc0f5a5a` | 信息展示 | 未实现 | — |

### 电子邮件访问 — `privacy-email`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-email`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 电子邮件访问权限 | `privacy-email.6743c4a8` | 开关 | 未实现 | — |
| 允许应用访问电子邮件访问 | `privacy-email.b1eccdff` | 开关 | 未实现 | — |
| 允许桌面应用访问电子邮件访问 | `privacy-email.0f9728b4` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-email.bc0f5a5a` | 信息展示 | 未实现 | — |

### 眼动跟踪器 — `privacy-eyetracker`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-eyetracker`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 眼动跟踪器权限 | `privacy-eyetracker.e409bf85` | 开关 | 未实现 | — |
| 允许应用访问眼动跟踪器 | `privacy-eyetracker.9536184e` | 开关 | 未实现 | — |
| 允许桌面应用访问眼动跟踪器 | `privacy-eyetracker.90447213` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-eyetracker.bc0f5a5a` | 信息展示 | 未实现 | — |

### 文件系统 — `privacy-broadfilesystemaccess`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-broadfilesystemaccess`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 文件系统权限 | `privacy-broadfilesystemaccess.201c9daf` | 开关 | 未实现 | — |
| 允许应用访问文件系统 | `privacy-broadfilesystemaccess.85ed3ea9` | 开关 | 未实现 | — |
| 允许桌面应用访问文件系统 | `privacy-broadfilesystemaccess.e0e3dac0` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-broadfilesystemaccess.bc0f5a5a` | 信息展示 | 未实现 | — |

### 屏幕截图和录制 — `privacy-graphicscaptureprogrammatic`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-graphicscaptureprogrammatic`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 屏幕截图和录制权限 | `privacy-graphicscaptureprogrammatic.f4796772` | 开关 | 未实现 | — |
| 允许应用访问屏幕截图和录制 | `privacy-graphicscaptureprogrammatic.36f7273e` | 开关 | 未实现 | — |
| 允许桌面应用访问屏幕截图和录制 | `privacy-graphicscaptureprogrammatic.7b1ff9cb` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-graphicscaptureprogrammatic.bc0f5a5a` | 信息展示 | 未实现 | — |

### 无边框截图 — `privacy-graphicscapturewithoutborder`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-graphicscapturewithoutborder`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 无边框截图权限 | `privacy-graphicscapturewithoutborder.864101f4` | 开关 | 未实现 | — |
| 允许应用访问无边框截图 | `privacy-graphicscapturewithoutborder.c791799e` | 开关 | 未实现 | — |
| 允许桌面应用访问无边框截图 | `privacy-graphicscapturewithoutborder.e6ef1f02` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-graphicscapturewithoutborder.bc0f5a5a` | 信息展示 | 未实现 | — |

### 位置 — `privacy-location`

应用访问权限与最近活动

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-location`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 位置权限 | `privacy-location.b53f9ca7` | 开关 | 未实现 | — |
| 允许应用访问位置 | `privacy-location.6d137050` | 开关 | 未实现 | — |
| 允许桌面应用访问位置 | `privacy-location.46291e42` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-location.bc0f5a5a` | 信息展示 | 未实现 | — |
| 位置服务 | `privacy-location.082addf9` | 开关 | 未实现 | — |
| 默认位置 | `privacy-location.fec9248d` | 操作 | 未实现 | — |
| 清除位置历史记录 | `privacy-location.a348ea51` | 操作 | 未实现 | — |

### 消息 — `privacy-messaging`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-messaging`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 消息权限 | `privacy-messaging.1c868b63` | 开关 | 未实现 | — |
| 允许应用访问消息 | `privacy-messaging.75f65f66` | 开关 | 未实现 | — |
| 允许桌面应用访问消息 | `privacy-messaging.ebdef2d0` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-messaging.bc0f5a5a` | 信息展示 | 未实现 | — |

### 麦克风访问 — `privacy-microphone`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-microphone`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 麦克风访问权限 | `privacy-microphone.2298fc11` | 开关 | 未实现 | — |
| 允许应用访问麦克风访问 | `privacy-microphone.d65280b9` | 开关 | 未实现 | — |
| 允许桌面应用访问麦克风访问 | `privacy-microphone.3740edb1` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-microphone.bc0f5a5a` | 信息展示 | 未实现 | — |

### 运动 — `privacy-motion`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-motion`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 运动权限 | `privacy-motion.d4e74455` | 开关 | 未实现 | — |
| 允许应用访问运动 | `privacy-motion.3c8df88a` | 开关 | 未实现 | — |
| 允许桌面应用访问运动 | `privacy-motion.7dadf4d9` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-motion.bc0f5a5a` | 信息展示 | 未实现 | — |

### 音乐库 — `privacy-musiclibrary`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-musiclibrary`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 音乐库权限 | `privacy-musiclibrary.e44d696b` | 开关 | 未实现 | — |
| 允许应用访问音乐库 | `privacy-musiclibrary.25913a47` | 开关 | 未实现 | — |
| 允许桌面应用访问音乐库 | `privacy-musiclibrary.88c26df1` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-musiclibrary.bc0f5a5a` | 信息展示 | 未实现 | — |

### 通知访问 — `privacy-notifications`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-notifications`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 通知访问权限 | `privacy-notifications.fcd04817` | 开关 | 未实现 | — |
| 允许应用访问通知访问 | `privacy-notifications.27c3ae78` | 开关 | 未实现 | — |
| 允许桌面应用访问通知访问 | `privacy-notifications.4b6a2eab` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-notifications.bc0f5a5a` | 信息展示 | 未实现 | — |

### 其他设备 — `privacy-customdevices`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-customdevices`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 其他设备权限 | `privacy-customdevices.2ae3eaa4` | 开关 | 未实现 | — |
| 允许应用访问其他设备 | `privacy-customdevices.116586b1` | 开关 | 未实现 | — |
| 允许桌面应用访问其他设备 | `privacy-customdevices.71162fd5` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-customdevices.bc0f5a5a` | 信息展示 | 未实现 | — |

### 电话呼叫 — `privacy-phonecalls`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-phonecalls`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 电话呼叫权限 | `privacy-phonecalls.f6415e0a` | 开关 | 未实现 | — |
| 允许应用访问电话呼叫 | `privacy-phonecalls.61c3930e` | 开关 | 未实现 | — |
| 允许桌面应用访问电话呼叫 | `privacy-phonecalls.4fde61dd` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-phonecalls.bc0f5a5a` | 信息展示 | 未实现 | — |

### 图片 — `privacy-pictures`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-pictures`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 图片权限 | `privacy-pictures.1b549e5c` | 开关 | 未实现 | — |
| 允许应用访问图片 | `privacy-pictures.d31bf02a` | 开关 | 未实现 | — |
| 允许桌面应用访问图片 | `privacy-pictures.c20698c1` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-pictures.bc0f5a5a` | 信息展示 | 未实现 | — |

### 无线通信 — `privacy-radios`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-radios`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 无线通信权限 | `privacy-radios.fd561c64` | 开关 | 未实现 | — |
| 允许应用访问无线通信 | `privacy-radios.11a432f0` | 开关 | 未实现 | — |
| 允许桌面应用访问无线通信 | `privacy-radios.6792cc19` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-radios.bc0f5a5a` | 信息展示 | 未实现 | — |

### 任务 — `privacy-tasks`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-tasks`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 任务权限 | `privacy-tasks.0fafdae2` | 开关 | 未实现 | — |
| 允许应用访问任务 | `privacy-tasks.8fd4d927` | 开关 | 未实现 | — |
| 允许桌面应用访问任务 | `privacy-tasks.86b78432` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-tasks.bc0f5a5a` | 信息展示 | 未实现 | — |

### 视频 — `privacy-videos`

应用访问权限与最近活动

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-videos`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 视频权限 | `privacy-videos.feacfffa` | 开关 | 未实现 | — |
| 允许应用访问视频 | `privacy-videos.0e261070` | 开关 | 未实现 | — |
| 允许桌面应用访问视频 | `privacy-videos.5b20e2b2` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-videos.bc0f5a5a` | 信息展示 | 未实现 | — |

### 语音激活 — `privacy-voiceactivation`

应用访问权限与最近活动

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:privacy-voiceactivation`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 语音激活权限 | `privacy-voiceactivation.2ccffeb1` | 开关 | 未实现 | — |
| 允许应用访问语音激活 | `privacy-voiceactivation.ab979cad` | 开关 | 未实现 | — |
| 允许桌面应用访问语音激活 | `privacy-voiceactivation.67d3b590` | 开关 | 未实现 | — |
| 应用访问记录 | `privacy-voiceactivation.bc0f5a5a` | 信息展示 | 未实现 | — |
| 锁屏时允许语音激活 | `privacy-voiceactivation.0b683ed1` | 开关 | 未实现 | — |


<a id="category-update"></a>

## 系统更新

更新历史、维护与预览计划

### 系统更新 — `updates`

更新状态与维护安排

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsupdate`、`ms-settings:windowsupdate-action`、`ms-settings:windowsupdate-seekerondemand`。

相关页面 ID：`update-history`、`update-options`、`insider`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 更新状态 | `updates.69d14924` | 信息展示 | 未实现 | — |
| 检查更新 | `updates.a6df3858` | 操作 | 未实现 | — |
| 尽早获取最新更新 | `updates.999d9943` | 开关 | 未实现 | — |
| 暂停更新 | `updates.70b991bf` | 选择 | 未实现 | — |
| 更新历史记录 | `updates.0c4e326b` | 操作 | 未实现 | — |
| 高级选项 | `updates.378a5408` | 操作 | 未实现 | — |
| 预览体验计划 | `updates.6b27d490` | 操作 | 未实现 | — |

### 更新历史记录 — `update-history`

功能、质量与驱动更新

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsupdate-history`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 功能更新 | `update-history.019e680d` | 操作 | 未实现 | — |
| 质量更新 | `update-history.02ffa466` | 操作 | 未实现 | — |
| 驱动程序更新 | `update-history.96574344` | 操作 | 未实现 | — |
| 定义更新 | `update-history.09e476b4` | 操作 | 未实现 | — |
| 其他更新 | `update-history.7cf8d3a1` | 操作 | 未实现 | — |
| 卸载更新 | `update-history.ffac73c3` | 操作 | 未实现 | — |

### 更新高级选项 — `update-options`

下载、重启与可选更新

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsupdate-options`。

相关页面 ID：`active-hours`、`restart`、`optional-updates`、`delivery`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 接收其他产品更新 | `update-options.7bd2f5b5` | 开关 | 未实现 | — |
| 通过按流量计费连接下载 | `update-options.3f139dcf` | 开关 | 未实现 | — |
| 尽快重新启动 | `update-options.0a009ef6` | 开关 | 未实现 | — |
| 需要重新启动时通知我 | `update-options.1439f298` | 开关 | 未实现 | — |
| 活动时间 | `update-options.abe0ecdb` | 操作 | 未实现 | — |
| 可选更新 | `update-options.0680a7f3` | 操作 | 未实现 | — |
| 传递优化 | `update-options.cdf4d30f` | 操作 | 未实现 | — |
| 恢复 | `update-options.79748ca1` | 操作 | 未实现 | — |

### 活动时间 — `active-hours`

避免在工作时重启

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsupdate-activehours`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 调整活动时间 | `active-hours.f2a92e6f` | 选择 | 未实现 | — |
| 开始时间 | `active-hours.e8868af6` | 文本输入 | 未实现 | — |
| 结束时间 | `active-hours.a0bb9f49` | 文本输入 | 未实现 | — |

### 重新启动选项 — `restart`

预约更新重启参考

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsupdate-restartoptions`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 计划重新启动 | `restart.44b9c516` | 开关 | 未实现 | — |
| 重新启动时间 | `restart.389c87b1` | 文本输入 | 未实现 | — |
| 重新启动日期 | `restart.a9e43782` | 文本输入 | 未实现 | — |

### 可选更新 — `optional-updates`

可选驱动与其他更新

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:windowsupdate-optionalupdates`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 驱动程序更新 | `optional-updates.96574344` | 操作 | 未实现 | — |
| 其他更新 | `optional-updates.7cf8d3a1` | 操作 | 未实现 | — |
| 下载并安装 | `optional-updates.f4df9977` | 操作 | 未实现 | — |

### 传递优化 — `delivery`

Windows 对等更新下载参考

页面状态：**不适用**；条目：4；已实现 0 / 未实现 0 / 不适用 4。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:delivery-optimization`。

相关页面 ID：`delivery-advanced`、`delivery-activity`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 允许从其他电脑下载 | `delivery.e6f32237` | 开关 | 不适用 | — |
| 下载来源 | `delivery.f92ab4a0` | 选择 | 不适用 | — |
| 高级带宽选项 | `delivery.e4b8232a` | 操作 | 不适用 | — |
| 活动监视器 | `delivery.8af97a09` | 操作 | 不适用 | — |

### 传递优化高级选项 — `delivery-advanced`

下载上传带宽限制参考

页面状态：**不适用**；条目：7；已实现 0 / 未实现 0 / 不适用 7。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:delivery-optimization-advanced`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 限制后台下载带宽 | `delivery-advanced.e83387e1` | 开关 | 不适用 | — |
| 后台下载带宽 | `delivery-advanced.ca6cbdef` | 滑块 | 不适用 | — |
| 限制前台下载带宽 | `delivery-advanced.e7da235d` | 开关 | 不适用 | — |
| 前台下载带宽 | `delivery-advanced.9a68eea5` | 滑块 | 不适用 | — |
| 限制上传带宽 | `delivery-advanced.4fd3fe9e` | 开关 | 不适用 | — |
| 上传带宽 | `delivery-advanced.833b5a72` | 滑块 | 不适用 | — |
| 每月上传限额 | `delivery-advanced.cfbe4220` | 文本输入 | 不适用 | — |

### 传递优化活动 — `delivery-activity`

Windows 更新流量统计参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:delivery-optimization-activity`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 下载统计 | `delivery-activity.f2c09a5a` | 信息展示 | 不适用 | — |
| 上传统计 | `delivery-activity.ae448372` | 信息展示 | 不适用 | — |
| 平均下载速度 | `delivery-activity.f1acf34e` | 信息展示 | 不适用 | — |

### Windows 预览体验计划 — `insider`

Windows 预览版本参考

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：Windows 专属或旧版参考，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:windowsinsider`、`ms-settings:windowsinsider-optin`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| 注册预览体验计划 | `insider.378311bc` | 操作 | 不适用 | — |
| 预览频道 | `insider.a4eb980c` | 选择 | 不适用 | — |
| 停止获取预览版本 | `insider.3a8e2507` | 开关 | 不适用 | — |
