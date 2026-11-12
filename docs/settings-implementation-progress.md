# 设置功能实现进度清单

目录基线：2026-10-26；清单建立：2026-10-26。

本清单逐项对应 [设置目录](../assets/settings/catalog.json)，用于后续接入 Hyprland / Linux 系统功能时跟踪进度。页面已能打开、控件已能显示，不代表其系统功能已经实现。

清单覆盖现有目录中的全部设置项，包括主要中文控件和保留原名的设计参考细项（受 Windows 等桌面系统启发，作为设计参考与基准对照，而非直接照搬）；实际架构和功能已针对 Linux / Hyprland 进行了适配与差异化演进。相同概念可能存在多个展示位置。下述数量统计的是控件条目，不是去重后的独立后端功能数量。参考来源与实际实现的边界见 [调研说明](windows-settings-research.md)。

Hyprland 内容包含 22 个独立页面及并入常规页面的设置项，共 484 项设置与 2 个分类。来源与版本边界见 [Hyprland 补充调研](hyprland-settings-research.md)。

## 当前概况

- 设置分类：16 个；详情页面：114 个；设置条目：1138 项。
- 已实现：439 项；未实现：689 项；不适用：10 项。
- Material Design 组的 Light/Dark 控件通过 Rust 读取、修改已安装 GNOME/GTK 的明确深浅色设置，并将 Qt Quick 官方主题环境变量保存到 fish 与 Hyprland Lua 配置。本应用遵循选定的 Material 外观；其余不可用控件仍为界面示例，不扫描设备或持久化预览值。

- 日期时间通过 Rust / system D-Bus 连接 systemd-timedated；时区只允许系统 ListTimezones 返回的有限集合。首次启动采用系统配置，冲突在顶部由用户选择同步方向；墙上时间不保存为启动恢复值。冲突提示仅列出实际变化的字段及双方值；`test/service_controllers_test.dart` 覆盖各偏好的提示。显示语言与区域格式由 Language and Region 页经 systemd-localed 管理。

- 声音通过 Rust libpulse 连接 PipeWire，支持输出、输入、应用音量/路由与设备清单；所有声音控制跟随系统实时状态，不持久化、不比对或恢复配置。见[声音文档](sound.md)。

- Camera 通过原生 PipeWire 读取设备能力、调节图像参数和处理配置冲突；支持显式开启的本地实时预览。见[Camera 文档](camera.md)。

- 网络通过 Rust / system D-Bus 连接 NetworkManager，提供网络状态、Wi-Fi、已知网络、以太网、VPN 与移动热点；代理读写 GSettings 桌面代理并跟随实时状态；设置项见[网络文档](network.md)。

- Night light 行标题与通用设置行统一使用 `bodyLarge`。

- Night light 通过 Rust 写 `hyprsunset.conf` 并经 `hyprctl hyprsunset` 控制运行状态，定时由 hyprsunset 原生 profile 执行；见[公开接口](public-api.md)。

- 系统更新由随图形会话启动的常驻服务执行：普通用户检查仓库（checkupdates）与 AUR（yay -Qua，仅列出），仓库升级经 pkexec 调用固定的 root 更新器在独立 systemd 单元中运行 `pacman -Syu`；自动更新在活动时间结束时运行，只有错过整个非活动时段时才在活动时间补跑。见[系统更新文档](updates.md)。

- 鼠标、触控板与键盘快捷键通过 Rust 读取 Hyprland 实时选项与键绑定，写入 Settings 自有的 `hypr/remya-settings/input.lua`（由 `hyprland.lua` 末尾受管块 require）并回读；冲突按系统配置同步规则处理。快捷键页不再放在窗口与工作区分类；见[输入设备与快捷键](input.md)。

- 多任务（系统）与光标（外观）：窗口布局、间距、边框、吸附与边框拖动，以及光标隐藏与指针移动，写入 Settings 自有的 `hypr/remya-settings/desktop.lua`；光标主题、大小与图标主题写入 GNOME 接口设置、GTK、KDE、XCursor 默认主题、fish 与 Hyprland 环境，并支持从文件夹或归档添加、删除用户主题包；见[光标与图标主题](themes.md)。

- 窗口外观、动画（外观）、Dwindle 布局选项（多任务）与工作区（系统，含工作区规则）写入 Settings 自有的 `desktop.lua`；语言和区域经 systemd-localed 设置显示语言与区域格式，键盘布局写入 `input.lua`；文字大小写入 GNOME/GTK `text-scaling-factor`。原 Hyprland 分类中的 Dwindle、布局总览与工作区预览页已并入或删除。

- 显示通过 Rust 经 `hyprctl` 读取并实时应用 Hyprland 显示规则，确认后写入 `monitors.lua`，并按系统配置同步规则处理冲突；亮度为实时值（logind 背光 / `ddcutil`），不保存。

### 已完成的界面能力（不计入系统功能进度）

- [x] 首页、常驻分类侧栏与自适应内容布局（窄窗口常驻图标侧栏）。
- [x] 一级目录在首页与侧栏按用途分为六组，使用一致的彩色圆形图标、分组间距与连接卡片；验证：`test/catalog_test.dart`。
- [x] 各分类的 More 统一放在二级选项末尾，其余选项保持目录顺序。
- [x] 按页面、设置名称和参考 URI 进行本地搜索。
- [x] 相关页面跳转、Alt+Left 键盘历史导航及参考细项展开。
- [x] 已实现 / 未实现 / 不适用的文字、图标和控件禁用状态。
- [x] 应用图标、About、版本和仓库信息。
- [x] 项目许可证及第三方许可查看。
- [x] 应用来源、版本、大小使用 Material 标签；已接管 AppImage 单独分类，更新进度围绕图标显示，速度自适应单位；验证：`test/application_lists_test.dart`、applications crate 测试。
- [x] 可变长数据列表共用固定标题栏、有限滚动区域与按需构建；字体预览等待滚动停稳后加载，加载前等高留白；验证：`test/settings_list_test.dart`、`test/fonts_test.dart`、本机 profile 翻页检查。

## 状态与记录方式

| 状态 | 含义 | 何时更新 |
| --- | --- | --- |
| 未实现 | 仅有界面，尚未接入对应系统能力 | 实现真实读取 / 修改或明确的只读查询，完成错误处理和相关验证后再更新 |
| 已实现 | 已接入可用的真实系统功能，并有验证依据 | 在“跟踪 / 验证”中记录提交、问题单、测试或实机验证记录 |
| 不适用 | 仅为参考基准专属、旧版或当前平台没有确定对应能力 | 保留条目作为设计参考；确认 Linux 替代方案后，记录决策并改为未实现 |

实现一个小项时，同步更新本表与目录中的 `availability` / `reason`，并更新页面汇总状态；不能只修改徽标或让示例控件响应。部分完成的页面应保持未实现，逐项记录已接入能力。开发阶段 ID 可以变动，变动时同步本表。新增或删除控件时也同步清单与分类统计；已删除的页面和控件不保留记录。

同一后端能力服务多个展示条目时，逐个登记所覆盖的 ID，并链接同一实现与验证依据。本项目以现代桌面设置（如 Windows 11）为启发和参考基准，但并非直接照搬，且已结合 Linux 与 Hyprland 实际需求进行深度适配与差异化调整。`不适用` 仅代表该参考项不适用于当前平台，不代表承诺实现 Windows 专有服务；是否纳入 Hyprland 的产品范围需要另作决定。参考区域的选项和范围仍需在接入时核实。

## 分类索引与统计

| 分类 | 页面 | 条目 | 已实现 | 未实现 | 不适用 |
| --- | ---: | ---: | ---: | ---: | ---: |
| [AI](#category-ai) | 2 | 2 | 2 | 0 | 0 |
| [系统](#category-system) | 15 | 201 | 113 | 88 | 0 |
| [声音](#category-sound) | 3 | 17 | 15 | 2 | 0 |
| [电源与电池](#category-power) | 3 | 20 | 19 | 1 | 0 |
| [通知](#category-notifications) | 4 | 19 | 12 | 7 | 0 |
| [蓝牙和设备](#category-devices) | 11 | 103 | 57 | 46 | 0 |
| [网络和 Internet](#category-network) | 8 | 63 | 63 | 0 | 0 |
| [外观](#category-appearance) | 10 | 212 | 95 | 117 | 0 |
| [应用](#category-apps) | 5 | 35 | 30 | 5 | 0 |
| [账户](#category-accounts) | 11 | 58 | 2 | 50 | 6 |
| [时间和语言](#category-time) | 4 | 19 | 11 | 8 | 0 |
| [辅助功能](#category-accessibility) | 10 | 192 | 1 | 191 | 0 |
| [隐私和安全性](#category-privacy) | 9 | 39 | 0 | 35 | 4 |
| [系统更新](#category-update) | 2 | 9 | 9 | 0 | 0 |
| [窗口与工作区](#category-hyprland) | 13 | 166 | 0 | 166 | 0 |
| [会话与配置](#category-session) | 9 | 80 | 0 | 80 | 0 |

<a id="category-system"></a>

## 系统

显示、存储与系统信息

### Display — `display`

排列、亮度、颜色、缩放、分辨率与刷新率

页面状态：**未实现**；条目：31；已实现 30 / 未实现 1 / 不适用 0。

原因：显示设置通过 Hyprland 实现；夜间模式与 Graphics 页面尚未实现。

Windows 参考入口：`ms-settings:display`、`ms-settings:screenrotation`、`ms-settings:display-advanced`。

参考资料：[hypr-monitors](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/monitors/_index.md)。

Display 交互：Position 使用 X/Y 输入；刷新操作移动到排列框右上角，移除框内操作提示；Brightness 拖动时合并串行硬件写入并回读；Resolution 支持 Preferred 或 X/Y，Rust 修正到最近的显示器支持模式；Orientation 分开选择 Rotation/Flip；Advanced 使用独立分组标题，展开后才显示设置卡片。验证：`test/display_test.dart`、Rust display 测试、隔离桌面 smoke tests。

#### 排列

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Selected display | `display.output` | 选择 | 已实现 | 实机 GUI；`test/display_test.dart` |
| Position | `display.position` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57）；`test/display_test.dart`（布局计算） |
| Refresh displays（排列框右上角按钮） | `display.15697afc` | 操作 | 已实现 | 实机读取；`cargo test -p remya_settings_display` |

#### 亮度与颜色

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Brightness | `display.5d419889` | 滑块 | 已实现 | 实机：eDP-1 logind 背光、DP-1/DP-3 ddcutil 读写回读 |
| Color preset | `display.af8e280d` | 选择 | 已实现 | Hyprland 0.57 实机（DP-1，含还原）；`test/display_smoke.py`（嵌套 Hyprland 0.57） |
| HDR | `display.0ce92088` | 开关 | 已实现 | 实机：DP-3 开启 HDR 回读 `hdr` 后还原 |
| Night light | `display.e32be03e` | 操作 | 已实现 | 打开 Night light 页面 |

#### 缩放与布局

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Scale | `display.12e2ed4d` | 选择 | 已实现 | Hyprland 0.57 实机（DP-1，含还原）；`test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Resolution | `display.44f6b9b0` | 选择 | 已实现 | Hyprland 0.57 实机（DP-1，含还原）；`test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Refresh rate | `display.34d8396d` | 选择 | 已实现 | Hyprland 0.57 实机（DP-1，含还原）；`test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Orientation | `display.9843ad76` | 选择 | 已实现 | Hyprland 0.57 实机（DP-1，含还原）；`test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Multiple displays | `display.7cb5dc06` | 选择 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57）；未在实机停用或镜像，以免移动工作区 |

#### Advanced（默认折叠）

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Desktop mode | `display.3b3ebb60` | 信息展示 | 已实现 | 实机读取三台显示器 |
| Active signal mode | `display.761b7ac8` | 信息展示 | 已实现 | 实机读取三台显示器 |
| Color space | `display.3278abf9` | 信息展示 | 已实现 | 实机读取三台显示器 |
| Display information | `display.device` | 信息展示 | 已实现 | 实机读取三台显示器 |
| Bit depth | `display.91720250` | 选择 | 已实现 | Hyprland 0.57 实机（DP-1，含还原）；`test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Variable refresh rate | `display.2d80c2c4` | 选择 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57）；本机显示器均不报告 VRR，仅验证默认与关闭 |
| SDR transfer function | `display.sdr-eotf` | 选择 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| SDR brightness in HDR | `display.sdrbrightness` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| SDR saturation in HDR | `display.sdrsaturation` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| SDR minimum luminance | `display.sdr-min-luminance` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| SDR maximum luminance | `display.sdr-max-luminance` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Display minimum luminance | `display.min-luminance` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Display peak luminance | `display.max-luminance` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Display average luminance | `display.max-avg-luminance` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| HDR capability | `display.supports-hdr` | 选择 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| Wide color capability | `display.supports-wide-color` | 选择 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |
| ICC profile | `display.icc` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57）（错误路径拒绝）；单元测试；未用真实 ICC 配置文件验证 |
| Reserved area | `display.reserved-area` | 文本输入 | 已实现 | `test/display_smoke.py`（嵌套 Hyprland 0.57） |

#### 图形

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Graphics | `display.2f32a8c2` | 操作 | 未实现 | — |

### Night light — `night-light`

暖色显示与时间安排

页面状态：**未实现**；条目：6；已实现 5 / 未实现 1 / 不适用 0。

原因：开关、色温和固定时段通过 hyprsunset 实现；Sunset to sunrise 尚未实现。

Windows 参考入口：`ms-settings:nightlight`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Night light | `night-light.e32be03e` | 开关 | 已实现 | `cargo test -p remya_settings_display night_light`；Hyprland 0.57 实机 |
| Color temperature | `night-light.temperature` | 滑块 | 已实现 | `cargo test -p remya_settings_display night_light`；Hyprland 0.57 实机 |
| Schedule | `night-light.7e6239c9` | 开关 | 已实现 | `cargo test -p remya_settings_display night_light`；Hyprland 0.57 实机 |
| Timing | `night-light.50840111` | 选择 | 未实现 | — |
| Start time | `night-light.e8868af6` | 文本输入 | 已实现 | `cargo test -p remya_settings_display night_light`；Hyprland 0.57 实机 |
| End time | `night-light.a0bb9f49` | 文本输入 | 已实现 | `cargo test -p remya_settings_display night_light`；Hyprland 0.57 实机 |

### Graphics — `graphics`

默认图形选项与每应用 GPU 偏好

页面状态：**未实现**；条目：38；已实现 0 / 未实现 38 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:display-advancedgraphics`、`ms-settings:display-advancedgraphics-default`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Windowed game optimization | `graphics.66507566` | 开关 | 未实现 | — |
| Hardware accelerated GPU scheduling | `graphics.c76f798a` | 开关 | 未实现 | — |
| Variable refresh rate | `graphics.4ee2d0bc` | 开关 | 未实现 | — |
| Add desktop apps | `graphics.f6aaf67c` | 操作 | 未实现 | — |
| Add app store apps | `graphics.232eb7f3` | 操作 | 未实现 | — |
| Apply GPU preferences | `graphics.49ad9ee9` | 选择 | 未实现 | — |

#### Advanced: compositor previews

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| OpenGL: nvidia anti flicker (nvidia_anti_flicker) | `graphics.opengl-nvidia-anti-flicker` | 开关 | 未实现 | — |
| Rendering: async commit (async_commit) | `graphics.render-async-commit` | 开关 | 未实现 | — |
| Rendering: cm auto hdr (cm_auto_hdr) | `graphics.render-cm-auto-hdr` | 滑块 | 未实现 | — |
| Rendering: Color management switch (cm_enabled) | `graphics.render-cm-enabled` | 开关 | 未实现 | — |
| Rendering: cm sdr eotf (cm_sdr_eotf) | `graphics.render-cm-sdr-eotf` | 文本输入 | 未实现 | — |
| Rendering: ctm animation (ctm_animation) | `graphics.render-ctm-animation` | 滑块 | 未实现 | — |
| Rendering: commit timing enabled (commit_timing_enabled) | `graphics.render-commit-timing-enabled` | 开关 | 未实现 | — |
| Rendering: Direct scan output strategy (direct_scanout) | `graphics.render-direct-scanout` | 滑块 | 未实现 | — |
| Rendering: expand undersized textures (expand_undersized_textures) | `graphics.render-expand-undersized-textures` | 开关 | 未实现 | — |
| Rendering: fp16 sdr tf (fp16_sdr_tf) | `graphics.render-fp16-sdr-tf` | 滑块 | 未实现 | — |
| Rendering: icc vcgt enabled (icc_vcgt_enabled) | `graphics.render-icc-vcgt-enabled` | 开关 | 未实现 | — |
| Rendering: keep unmodified copy (keep_unmodified_copy) | `graphics.render-keep-unmodified-copy` | 滑块 | 未实现 | — |
| Rendering: Rendering scheduling strategy (new_render_scheduling) | `graphics.render-new-render-scheduling` | 开关 | 未实现 | — |
| Rendering: not shown fifo lock (not_shown_fifo_lock) | `graphics.render-not-shown-fifo-lock` | 滑块 | 未实现 | — |
| Rendering: non shader cm (non_shader_cm) | `graphics.render-non-shader-cm` | 滑块 | 未实现 | — |
| Rendering: non shader cm interop (non_shader_cm_interop) | `graphics.render-non-shader-cm-interop` | 滑块 | 未实现 | — |
| Rendering: send content type (send_content_type) | `graphics.render-send-content-type` | 开关 | 未实现 | — |
| Rendering: use fp16 (use_fp16) | `graphics.render-use-fp16` | 滑块 | 未实现 | — |
| Rendering: use shader blur blend (use_shader_blur_blend) | `graphics.render-use-shader-blur-blend` | 开关 | 未实现 | — |
| Rendering: xp mode (xp_mode) | `graphics.render-xp-mode` | 开关 | 未实现 | — |
| Unfocused rendering frame rate (render_unfocused_fps) | `graphics.compositor-unfocused-fps` | 滑块 | 未实现 | — |
| XWayland: enabled (enabled) | `graphics.xwayland-enabled` | 开关 | 未实现 | — |
| XWayland: create abstract socket (create_abstract_socket) | `graphics.xwayland-create-abstract-socket` | 开关 | 未实现 | — |
| XWayland: XWayland force integer scaling (force_zero_scaling) | `graphics.xwayland-force-zero-scaling` | 开关 | 未实现 | — |
| XWayland: Nearest neighbor scaling (use_nearest_neighbor) | `graphics.xwayland-use-nearest-neighbor` | 开关 | 未实现 | — |
| Application compatibility: prefer hdr (prefer_hdr) | `graphics.compatibility-prefer-hdr` | 滑块 | 未实现 | — |
| Application compatibility: skip non kms dmabuf formats (skip_non_kms_dmabuf_formats) | `graphics.compatibility-skip-non-kms-dmabuf-formats` | 开关 | 未实现 | — |
| GPU selection: DRM device selection sequence | `graphics.gpu-devices` | 文本输入 | 未实现 | — |
| GPU selection: Rendering GPU selection | `graphics.gpu-render-device` | 文本输入 | 未实现 | — |
| GPU selection: GPU and driver information | `graphics.gpu-vendor` | 信息展示 | 未实现 | — |
| GPU selection: Connection relationship between monitor and GPU | `graphics.gpu-mapping` | 信息展示 | 未实现 | — |
| GPU selection: Graphics card environment variable override | `graphics.gpu-variables` | 文本输入 | 未实现 | — |

### Storage — `storage`

Space usage, disks and volumes

页面状态：**已实现**；条目：7；已实现 7 / 未实现 0 / 不适用 0。

原因：Rust 提供实时扫描、UDisks2 与经过校验的清理操作；自动清理属于应用偏好，不覆盖系统配置。缺少主机工具时逐项报告不适用。

Windows 参考入口：`ms-settings:storagesense`、`ms-settings:disksandvolumes`。

验证：`cargo test -p remya_settings_storage -p remya_settings_service`、`test/storage_test.dart` 和隔离 `test/interface_smoke.py`。实机破坏性操作未测试；范围与精度见 [Storage](storage.md)。

#### Usage

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Storage usage | `storage.usage` | 信息展示 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Scan again | `storage.scan` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |

#### Disks and volumes

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Disks and volumes | `storage.volumes` | 信息展示 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Mount or unmount | `storage.mount` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Eject or power off | `storage.eject` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Rename volume | `storage.label` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Open in file manager | `storage.open` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |

### Cleanup — `cleanup`

Free up space and clean up automatically

页面状态：**已实现**；条目：11；已实现 11 / 未实现 0 / 不适用 0。

原因：Rust 提供实时扫描、UDisks2 与经过校验的清理操作；自动清理属于应用偏好，不覆盖系统配置。缺少主机工具时逐项报告不适用。

Windows 参考入口：`ms-settings:storagepolicies`、`ms-settings:storagerecommendations`。

验证：`cargo test -p remya_settings_storage -p remya_settings_service`、`test/storage_test.dart` 和隔离 `test/interface_smoke.py`。实机破坏性操作未测试；范围与精度见 [Storage](storage.md)。

#### Cleanup recommendations

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Trash | `cleanup.trash` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Cached files | `cleanup.cache` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Package cache | `cleanup.package-cache` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Unused packages | `cleanup.orphans` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Large files | `cleanup.large-files` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |

#### Automatic cleanup

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Clean up automatically | `cleanup.auto` | 开关 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Frequency | `cleanup.auto-frequency` | 选择 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Trash retention | `cleanup.auto-trash` | 选择 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Cache retention | `cleanup.auto-cache` | 选择 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Downloads retention | `cleanup.auto-downloads` | 选择 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |
| Run now | `cleanup.run-now` | 操作 | 已实现 | Rust storage tests、Flutter storage widget tests、隔离 CLI/D-Bus parity |

### Multitasking — `multitasking`

Window layout, spacing, borders, snapping and resizing

页面状态：**已实现**；条目：29；已实现 29 / 未实现 0 / 不适用 0。

原因：Uses Hyprland window options through the Settings service.

Windows 参考入口：`ms-settings:multitasking`。

实现与边界见 [输入设备与快捷键](input.md) 的 desktop 分组：读取 `hyprctl descriptions` 实时值，经 `hyprctl eval` 校验后写入 Settings 自有的 `hypr/remya-settings/desktop.lua` 并回读。布局缩略图选择排列方式，页首示意图随布局、间距与边框宽度（拖动中也）实时变化；吸附与边框拖动的子选项在父项关闭时自动隐藏。原 `hypr-general` 与 `hypr-general-snap` 页面并入本页，界面语言覆盖（locale）因与“语言和区域”重复而删除。Dwindle 布局选项（原 `hypr-layout-dwindle` 页面）并入本页，仅在当前布局为 Dwindle 时显示；原 `hypr-layout-overview` 页面与布局选择重复，其余操作属于快捷键，已删除。

#### Window layout

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Arrange windows | `multitasking.layout` | 选择 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Dwindle layout

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Place new windows | `multitasking.dwindle-force-split` | 选择 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Keep each split direction | `multitasking.dwindle-preserve-split` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Split toward the pointer | `multitasking.dwindle-smart-split` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| New window share | `multitasking.dwindle-split-ratio` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Spacing and borders

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Space between windows | `multitasking.gaps-in` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Space at screen edges | `multitasking.gaps-out` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Border width | `multitasking.border-size` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Snapping

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Snap floating windows | `multitasking.snap` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Snap to other windows within | `multitasking.snap-window-gap` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Snap to screen edges within | `multitasking.snap-monitor-gap` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Keep window spacing when snapping | `multitasking.snap-respect-gaps` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Share one border between snapped windows | `multitasking.snap-border-overlap` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Resizing

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Resize by dragging window borders | `multitasking.resize-on-border` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Extra grab area outside the border | `multitasking.border-grab-area` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Show the resize pointer on borders | `multitasking.border-hover-icon` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Space between floating windows and screen edges | `multitasking.float-gaps` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Space between workspaces while switching | `multitasking.gaps-workspaces` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Floating window resize corner | `multitasking.resize-corner` | 选择 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Block the window behind a dialog | `multitasking.modal-parent-blocking` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Keep focus when no window is in that direction | `multitasking.no-focus-fallback` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Allow screen tearing for games | `multitasking.allow-tearing` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Split the focused window | `multitasking.dwindle-use-active` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Resize from the nearest edge | `multitasking.dwindle-smart-resizing` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Keep a chosen split direction | `multitasking.dwindle-permanent-direction` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Split ratio goes to | `multitasking.dwindle-split-bias` | 选择 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Wide window threshold | `multitasking.dwindle-split-width` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Scratchpad window size | `multitasking.dwindle-special-scale` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Drop dragged windows where the pointer is | `multitasking.dwindle-precise-move` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

### Workspaces — `workspaces`

Which workspaces each display starts with, which stay when empty, and how the scratchpad behaves

页面状态：**已实现**；条目：7；已实现 7 / 未实现 0 / 不适用 0。

原因：Uses desktop workspace options and rules through the Settings service.

实现与边界见 [输入设备与快捷键](input.md) 的 desktop 分组：工作区选项与 `hl.workspace_rule` 规则（工作区、显示器、起始工作区、保留空工作区、默认名称）写入 Settings 自有的 `hypr/remya-settings/desktop.lua`，重载后等待 `hyprctl workspacerules` 回读。页首按实时显示器位置与逻辑尺寸绘制各显示器及其工作区；其他配置文件（如 `workspaces.lua`）中的规则只读显示，Settings 从不修改。原工作区预览页面并入本页，暂存区（scratchpad）相关的合成器选项也移入本页。

#### Workspace rules

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Your workspace rules | `workspaces.rule-set` | 操作 | 已实现 | 见下文“Workspaces (2026-11-09)” |
| Remove a workspace rule | `workspaces.rule-remove` | 操作 | 已实现 | 见下文“Workspaces (2026-11-09)” |

#### Behavior

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Open windows on the workspace they were launched from | `workspaces.initial-workspace-tracking` | 选择 | 已实现 | 见下文“Workspaces (2026-11-09)” |
| Hide the scratchpad when its last window closes | `workspaces.close-special-on-empty` | 开关 | 已实现 | 见下文“Workspaces (2026-11-09)” |
| Hide the scratchpad when switching workspaces | `workspaces.hide-special-on-change` | 开关 | 已实现 | 见下文“Workspaces (2026-11-09)” |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Pointer after switching to a workspace on another display | `workspaces.center-on` | 选择 | 已实现 | 见下文“Workspaces (2026-11-09)” |
| Click through a scratchpad that has only floating windows | `workspaces.special-fallthrough` | 开关 | 已实现 | 见下文“Workspaces (2026-11-09)” |

### Environment variables — `environment-variables`

Session variables for apps the desktop starts, such as Wayland preferences for toolkits

页面状态：**已实现**；条目：2；已实现 2 / 未实现 0 / 不适用 0。

原因：Writes session variables to the Settings-owned desktop configuration and reloads it.

`hl.env` 变量写入 Settings 自有的 `hypr/remya-settings/desktop.lua`，显式重载并检查 `hyprctl configerrors`；光标、Qt Quick 深浅色等由其他页面负责的变量与会话关键变量被拒绝。替代原 `hypr-environment` 预览页。

#### Variables

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Your environment variables | `environment.set` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |
| Remove an environment variable | `environment.remove` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |

### Project to this computer — `projection`

无线显示与投影许可

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:project`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Allow projection | `projection.ec71f569` | 选择 | 未实现 | — |
| Request projection confirmation | `projection.d8103e93` | 选择 | 未实现 | — |
| PIN required | `projection.7d2dd2be` | 选择 | 未实现 | — |
| Only discoverable when powered on | `projection.80db4c9e` | 开关 | 未实现 | — |
| Install wireless display | `projection.6e4baff3` | 操作 | 未实现 | — |

### Remote Desktop — `remote-desktop`

远程访问与允许的用户

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:remotedesktop`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Enable remote desktop | `remote-desktop.308c8bda` | 开关 | 未实现 | — |
| Require network level authentication | `remote-desktop.0d46b931` | 开关 | 未实现 | — |
| Computer name | `remote-desktop.2f2f4cf1` | 信息展示 | 未实现 | — |
| Remote Desktop User | `remote-desktop.ddee4fd6` | 操作 | 未实现 | — |

### Clipboard — `clipboard`

Remya Launcher 的历史记录、保留上限与清除

页面状态：**已实现**；条目：4；已实现 4 / 未实现 0 / 不适用 0。

原因：通过 Launcher 服务读取与更新专用策略，改动即时生效。独立的第三方剪贴板管理器与跨设备同步不在本页的范围内。

Windows 参考入口：`ms-settings:clipboard`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Clipboard history | `clipboard.history-enabled` | 开关 | 已实现 | `test/clipboard_page_test.dart`、`test/clipboard_smoke.py` |
| Maximum history items | `clipboard.max-items` | 文本输入 | 已实现 | `test/clipboard_page_test.dart`、`test/clipboard_smoke.py` |
| Retention period | `clipboard.retention-days` | 文本输入 | 已实现 | `test/clipboard_smoke.py` |
| Clear clipboard history | `clipboard.clear-history` | 操作 | 已实现 | `test/clipboard_page_test.dart`、`test/clipboard_smoke.py` |

### Presence sensing — `presence`

离开锁定与接近唤醒

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:presence`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Turn off the screen when you leave | `presence.bc279609` | 开关 | 未实现 | — |
| Wake device when approaching | `presence.5641252e` | 开关 | 未实现 | — |
| Dim the screen when you look away | `presence.b9bc699d` | 开关 | 未实现 | — |
| Leaving detection distance | `presence.fb638054` | 选择 | 未实现 | — |
| Lock delay | `presence.043eb133` | 选择 | 未实现 | — |

### System information — `about`

设备规格、系统版本与相关信息

页面状态：**已实现**；条目：17；已实现 17 / 未实现 0 / 不适用 0。

原因：Rust sysinfo 0.40.1 只读设备与系统信息；重命名经 Rust、私有授权进程与 systemd-hostnamed 完成，保存静态名并处理冲突。Device identifier 与 Advanced system settings 已按用户要求删除。硬件读取结果不持久化；主机名仅保存静态配置，运行名称只读。

Windows 参考入口：`ms-settings:about`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Device name | `about.4433eb13` | 信息展示 | 已实现 | Rust 字段错误测试；Flutter 读取/刷新/360px 测试；实机 CLI/D-Bus 回读 |
| Processor | `about.b4366749` | 信息展示 | 已实现 | Rust 字段错误测试；Flutter 读取/刷新/360px 测试；实机 CLI/D-Bus 回读 |
| Memory | `about.d014ab77` | 信息展示 | 已实现 | Rust 字段错误测试；Flutter 读取/刷新/360px 测试；实机 CLI/D-Bus 回读 |
| System type | `about.96af9884` | 信息展示 | 已实现 | Rust 字段错误测试；Flutter 读取/刷新/360px 测试；实机 CLI/D-Bus 回读 |
| Operating system version | `about.d0a7f225` | 信息展示 | 已实现 | Rust 字段错误测试；Flutter 读取/刷新/360px 测试；实机 CLI/D-Bus 回读 |
| Manufacturer | `about.manufacturer` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Model | `about.model` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Model revision | `about.model-version` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Motherboard manufacturer | `about.board-manufacturer` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Motherboard model | `about.board-model` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Firmware manufacturer | `about.firmware-manufacturer` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Firmware version | `about.firmware-version` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Firmware release date | `about.firmware-date` | 信息展示 | 已实现 | DMI 日期校验；依当前 localed LC_TIME（继承 LANG）格式化；中英文 locale 测试与 CLI/D-Bus 回读 |
| Physical CPU cores | `about.cpu-cores` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Logical processors | `about.cpu-threads` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Kernel version | `about.kernel-version` | 信息展示 | 已实现 | Rust 字段校验；Flutter 宽/窄窗口测试；实机 sysfs 与 CLI/D-Bus 回读 |
| Rename device | `about.0f142010` | 操作 | 已实现 | 私有 hostnamed D-Bus 成功/拒绝/冲突/回读测试；初始化、双向同步与持久化失败测试；宽/窄窗口编辑图标及弹窗验证；未改实机名称 |

Windows reference settings 已按要求删除；其 Rename this PC 来源覆盖映射到保留的 `about.0f142010`。内存为 Linux 可用总容量。

### Advanced settings — `advanced`

开发工具、终端与文件管理器参考

页面状态：**未实现**；条目：14；已实现 0 / 未实现 14 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:developers`。

相关页面 ID：`file-explorer`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Developer mode | `advanced.16ab0c5a` | 开关 | 未实现 | — |
| Device Portal | `advanced.da8193cc` | 开关 | 未实现 | — |
| Device discovery | `advanced.cb620100` | 开关 | 未实现 | — |
| Default terminal | `advanced.216f8db4` | 选择 | 未实现 | — |
| Enable sudo | `advanced.809d3128` | 开关 | 未实现 | — |
| Long path support | `advanced.d2ec4f10` | 开关 | 未实现 | — |
| End the task in the taskbar | `advanced.d68b8048` | 开关 | 未实现 | — |
| File Explorer Options | `advanced.001394d6` | 操作 | 未实现 | — |
| Virtual Workspace | `advanced.daee0454` | 操作 | 未实现 | — |
| Dev Drive | `advanced.80afb07b` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Show file extensions | `advanced.reference.96b6fa8d` | 开关 | 未实现 | — |
| Show hidden and system files | `advanced.reference.f09f62a2` | 开关 | 未实现 | — |
| Show full path in title bar | `advanced.reference.d6ad9b0f` | 开关 | 未实现 | — |
| Show empty drives | `advanced.reference.4c7d62c7` | 开关 | 未实现 | — |

### File manager options — `file-explorer`

文件显示与版本控制参考

页面状态：**未实现**；条目：20；已实现 0 / 未实现 20 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Display file extensions | `file-explorer.aae5a85e` | 开关 | 未实现 | — |
| Show hidden and system files | `file-explorer.548c9a49` | 开关 | 未实现 | — |
| Title bar displays full path | `file-explorer.a484d4f3` | 开关 | 未实现 | — |
| Empty drive shown | `file-explorer.e0952b14` | 开关 | 未实现 | — |
| Show run as other user | `file-explorer.7a72391c` | 开关 | 未实现 | — |
| Show checkboxes | `file-explorer.32a40852` | 开关 | 未实现 | — |
| Compact view | `file-explorer.e2ebcb73` | 开关 | 未实现 | — |
| Delete confirmation | `file-explorer.726b6ec5` | 开关 | 未实现 | — |
| Open project mode | `file-explorer.de1fb32c` | 选择 | 未实现 | — |
| Version control integration | `file-explorer.b3551149` | 操作 | 未实现 | — |

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
| Display delete confirmation dialog | `file-explorer.reference.163ce553` | 开关 | 未实现 | — |
| View (Icon size, Auto arrange icons, Show desktop icons) | `file-explorer.reference.f24ca65a` | 选择 | 未实现 | — |
| Sort by (Name, Size, Item type, Date modified) | `file-explorer.reference.ed11d482` | 选择 | 未实现 | — |

### More — `system-more`

打开实际已安装的外部设置应用。未安装的入口自动隐藏。

页面状态：**已实现**；条目：3；已实现 3 / 未实现 0 / 不适用 0。

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| KDE System Settings | `system-more.kde` | 操作 | 已实现 | Rust 检测测试、CLI/D-Bus 对等与实机打开验证 |
| GNOME Settings | `system-more.gnome` | 操作 | 已实现 | 检测与 GNOME/Unity 会话限制验证；Hyprland 下显示原因而不启动 |
| LocalSend | `system-more.localsend` | 操作 | 已实现 | Rust 可执行检测测试、已安装 CLI/D-Bus 对等与实机打开验证 |

<a id="category-sound"></a>

## 声音

输出、输入、应用音量与音频设备

实时状态回归验证：Rust sound/service 测试、`test/sound_test.dart` 和隔离 PipeWire 测试通过；`test/sound_smoke.py` 的 debug/release 验证覆盖外部音量、静音、默认设备变更、服务重启、无配置写入以及已删除恢复接口的拒绝。

### Output & input — `sound-volume`

Default output and input devices, volume and mute

页面状态：**已实现**；条目：7；已实现 7 / 未实现 0 / 不适用 0。

原因：Rust reads and controls the per-user PipeWire audio server through libpulse and sets the Hyprland compositor bell, with validated writes and readback.

Windows 参考入口：`ms-settings:sound`、`ms-settings:sound-defaultoutputproperties`、`ms-settings:sound-properties`、`ms-settings:sound-defaultinputproperties`。

#### Output

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Output device | `sound.output-device` | 选择 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Output volume | `sound.output-volume` | 滑块 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Mute output | `sound.output-muted` | 开关 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |

#### Input

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Input device | `sound.input-device` | 选择 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Input volume | `sound.input-volume` | 滑块 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Mute microphone | `sound.input-muted` | 开关 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Compositor bell sound (bell_sound) | `sound.compositor-bell` | 文本输入 | 已实现 | Rust input/desktop 测试；`test/sound_test.dart`；`test/desktop_smoke.py`（嵌套 Hyprland 0.57） |

### Volume mixer — `volume-mixer`

Playback and recording application volumes and routing

页面状态：**已实现**；条目：4；已实现 4 / 未实现 0 / 不适用 0。

原因：Rust reads and controls the per-user PipeWire audio server through libpulse, with validated writes and readback.

Windows 参考入口：`ms-settings:apps-volume`。

#### Settings

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Active audio applications | `sound.streams` | 信息展示 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Application volume | `sound.stream-volume` | 滑块 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Mute application | `sound.stream-muted` | 开关 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Application audio device | `sound.stream-device` | 选择 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |

### Devices — `sound-devices`

Connected physical and virtual audio devices

页面状态：**未实现**；条目：6；已实现 4 / 未实现 2 / 不适用 0。

原因：Rust reads and controls the per-user PipeWire audio server through libpulse, with validated writes and readback. Additional compositor options remain unimplemented previews.

Windows 参考入口：`ms-settings:sound-devices`。

#### Settings

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Audio device inventory | `sound.devices` | 信息展示 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Device volume | `sound.device-volume` | 滑块 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Mute device | `sound.device-muted` | 开关 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |
| Refresh audio | `sound.refresh` | 操作 | 已实现 | `test/sound_test.dart`；Rust sound 测试；隔离 PipeWire 音量/静音/默认设备读写验证 |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| PipeWire routing: Audio device configuration file | `sound.pipewire-profile` | 文本输入 | 未实现 | — |
| PipeWire routing: Input and output ports | `sound.pipewire-port` | 文本输入 | 未实现 | — |

<a id="category-power"></a>

## 电源与电池

能耗、电池、睡眠与电源管理

### Power & battery — `power`

能耗、屏幕超时与电池

页面状态：**已实现**；条目：10；已实现 10 / 未实现 0 / 不适用 0。

原因：电源模式、hypridle 超时与锁定、显示唤醒均通过 Rust 接入真实系统。

Windows 参考入口：`ms-settings:powersleep`。

相关页面 ID：`battery-saver`、`battery-usage`、`energy`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Power mode | `power.5a4f0131` | 选择 | 已实现 | Rust power tests; live PowerProfiles/backlight readback |
| Turn off screen time | `power.5e3af39c` | 选择 | 已实现 | Rust power tests; live PowerProfiles/backlight readback |
| Lock screen after | `power.lock-after` | 选择 | 已实现 | `cargo test -p remya_settings_power idle`；`test/power_test.dart`；本机 hypridle.conf 读回无改动 |
| Sleep time | `power.8b4c8522` | 选择 | 已实现 | Rust power tests; live PowerProfiles/backlight readback |
| Lock before sleep | `power.lock-before-sleep` | 开关 | 已实现 | `cargo test -p remya_settings_power idle`；`test/power_test.dart`；本机 hypridle.conf 读回无改动 |
| Keep awake | `power.keep-awake` | 开关 | 已实现 | hypridle D-Bus 抑制 |
| Energy saving mode | `power.743773bd` | 操作 | 已实现 | 跳转至 Energy saver |
| Battery usage | `power.03bd05ee` | 操作 | 已实现 | 跳转至 Battery usage |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Wake displays on key press | `power.wake-key` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57） |
| Wake displays on pointer movement | `power.wake-pointer` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57） |

### Energy saver — `battery-saver`

节能策略与自动启用和关闭阈值

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

原因：基础功能通过 Rust 接入真实系统，其余高级项保持预览。

Windows 参考入口：`ms-settings:batterysaver`、`ms-settings:batterysaver-settings`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Energy saving mode | `battery-saver.743773bd` | 开关 | 已实现 | Rust power tests; live PowerProfiles/backlight readback |
| Turn on automatically at | `battery-saver.9b0caf70` | 选择 | 已实现 | Rust power tests and live PowerProfiles readback |
| Turn off automatically at | `battery-saver.off-threshold` | 选择 | 已实现 | Rust threshold tests and isolated CLI/D-Bus readback |
| Reduce screen brightness when saving energy | `battery-saver.07945503` | 开关 | 已实现 | Rust power tests; live PowerProfiles/backlight readback |
| Also enable when plugged in | `battery-saver.power-source` | 开关 | 已实现 | Rust policy tests; live automatic policy roundtrip |

### Battery usage — `battery-usage`

电量历史与每应用耗电

页面状态：**已实现**；条目：5；已实现 4 / 未实现 1 / 不适用 0。

原因：SQLite 电量曲线、屏幕与睡眠时长已接入；每应用耗电保持预览。

Windows 参考入口：`ms-settings:batterysaver-usagedetails`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Time frame | `battery-usage.2be90408` | 选择 | 已实现 | test/battery_history_test.dart; SQLite readback |
| Screen on time | `battery-usage.37bfb377` | 信息展示 | 已实现 | test/battery_history_test.dart; SQLite readback |
| Screen off time | `battery-usage.1aa63c64` | 信息展示 | 已实现 | test/battery_history_test.dart; SQLite readback |
| Sleep time | `battery-usage.adee81f9` | 信息展示 | 已实现 | test/battery_history_test.dart; SQLite readback |
| Battery usage per app | `battery-usage.68bac7d6` | 信息展示 | 未实现 | — |

<a id="category-notifications"></a>

## 通知

系统通知、免打扰与专注时段

### Notifications — `notifications`

声音、免打扰与弹窗

页面状态：**已实现**；条目：6；已实现 5 / 未实现 1 / 不适用 0。

原因：Applies to the notifications shown by Remy'a Bar, the desktop notification service.

Windows 参考入口：`ms-settings:notifications`。

相关页面 ID：`quiet-schedule`、`priority-notifications`。

偏好保存在 `notifications.toml`，由 Remy'a Bar 通知服务实时应用；见 [公共接口](public-api.md#notifications)。已删除不适用于 Linux / Hyprland 的条目（锁屏通知、铃铛图标、欢迎体验与提示）。

#### 免打扰

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Do not disturb | `notifications.do-not-disturb` | 开关 | 已实现 | Settings 服务持久化与 CLI/D-Bus 对等测试；Bar 通知服务实时隐藏非优先弹窗与声音，实机验证 |
| Turn on Do Not Disturb automatically | `notifications.automatic-dnd` | 操作 | 已实现 | 打开 Automatic Do Not Disturb 页面；`test/notifications_page_test.dart` |
| Set priority notifications | `notifications.priority` | 操作 | 已实现 | 打开 Priority notification 页面 |

#### 弹窗

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Popup duration | `notifications.popup-duration` | 选择 | 已实现 | Settings 校验 1–60 秒并持久化；Bar 实时应用默认弹窗时长 |
| Play sounds | `notifications.sounds` | 开关 | 已实现 | Bar 通过 libcanberra `canberra-gtk-play` 播放请求或主题消息声音，遵守 suppress-sound |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Show notifications on the lock screen | `notifications.reference.c7fafa9e` | 开关 | 未实现 | — |

### Focus — `focus`

专注时段与减少干扰

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:quiethours`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Session duration | `focus.9eac723a` | 选择 | 未实现 | — |
| Start focus period | `focus.e9d3186d` | 操作 | 未实现 | — |
| Display timer | `focus.72877c30` | 开关 | 未实现 | — |
| Hide taskbar app badges | `focus.4c84c9c8` | 开关 | 未实现 | — |
| Hide taskbar flickering | `focus.18b69b82` | 开关 | 未实现 | — |
| Turn on Do Not Disturb | `focus.fadd18ca` | 开关 | 未实现 | — |

### Automatic Do Not Disturb — `quiet-schedule`

计划与全屏条件

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

原因：Turns on Do Not Disturb automatically for Remy'a Bar notifications.

#### 计划

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| During these times | `quiet-schedule.enabled` | 开关 | 已实现 | Bar Rust 按计划计算免打扰（跨午夜属于开始日）；Rust 单元测试 |
| Start time | `quiet-schedule.start` | 文本输入 | 已实现 | HH:MM 校验与持久化；Rust 单元测试 |
| End time | `quiet-schedule.end` | 文本输入 | 已实现 | HH:MM 校验与持久化；Rust 单元测试 |
| Repeat | `quiet-schedule.repeat` | 选择 | 已实现 | 每天 / 工作日 / 周末；Rust 单元测试 |

#### 条件

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| When an app is full screen | `quiet-schedule.fullscreen` | 开关 | 已实现 | 各输出上报 Hyprland 全屏状态，任一全屏即免打扰；Rust 单元测试 |

### Priority notification — `priority-notifications`

穿透免打扰的来电与应用

页面状态：**已实现**；条目：2；已实现 2 / 未实现 0 / 不适用 0。

原因：Priority notifications still pop up and play sounds while Do Not Disturb is on.

#### 优先

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Incoming calls | `priority-notifications.calls` | 开关 | 已实现 | category 为 call / call.incoming 的通知穿透免打扰；Rust 单元测试 |
| Priority apps | `priority-notifications.apps` | 操作 | 已实现 | 按 desktop-entry 或应用名匹配；从已安装应用添加；Rust 单元测试 |

<a id="category-devices"></a>

## 蓝牙和设备

连接设备、输入与外设

### Bluetooth — `bluetooth`

蓝牙适配器、配对与设备连接

页面状态：**已实现**；条目：12；已实现 12 / 未实现 0 / 不适用 0。

原因：Rust/GIO 通过系统 BlueZ 实现。写操作与配对由隔离 BlueZ 验证；真实硬件仅验证读取与扫描，不切断现有键鼠或删除配对。

Windows 参考入口：`ms-settings:bluetooth`。

详见 [蓝牙功能与验证边界](bluetooth.md)。

#### Bluetooth

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Bluetooth | `bluetooth.enabled` | 开关 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Adapter | `bluetooth.adapter` | 选择 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Add device / scan | `bluetooth.scan` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |

#### Devices

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Paired devices | `bluetooth.devices` | 信息展示 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Pair | `bluetooth.pair` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Connect | `bluetooth.connect` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Disconnect | `bluetooth.disconnect` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Remove device | `bluetooth.forget` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Cancel pairing | `bluetooth.cancel` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Pairing response | `bluetooth.respond` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Adapter information | `bluetooth.information` | 信息展示 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |
| Temporarily discoverable | `bluetooth.discoverable` | 操作 | 已实现 | `test/bluetooth_test.dart`；`test/bluetooth_smoke.py`（隔离 BlueZ） |

### Devices — `device-list`

连接设备与设备属性

页面状态：**未实现**；条目：18；已实现 0 / 未实现 18 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:connecteddevices`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Add device | `device-list.1d30ae60` | 操作 | 未实现 | — |
| Connected devices | `device-list.c4c19ef3` | 信息展示 | 未实现 | — |
| Monitors and docking stations | `device-list.eabd0e62` | 操作 | 未实现 | — |
| Remove the device | `device-list.9064c223` | 操作 | 未实现 | — |

#### Advanced: compositor previews

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Input device: Device name or match | `device-list.input-device` | 文本输入 | 未实现 | — |
| Input device: Enable this device | `device-list.input-enabled` | 开关 | 未实现 | — |
| Input device: Shortcut keys enabled for this device | `device-list.input-keybinds` | 开关 | 未实现 | — |
| Input device: Device labeling and grouping | `device-list.input-tags` | 文本输入 | 未实现 | — |
| Input device: This device keyboard layout overrides | `device-list.input-keyboard` | 文本输入 | 未实现 | — |
| Input device: Pointer sensitivity override for this device | `device-list.input-sensitivity` | 文本输入 | 未实现 | — |
| Input device: Bind the tablet to the monitor | `device-list.input-output` | 文本输入 | 未实现 | — |
| Input device: View inherited global options | `device-list.input-inherit` | 操作 | 未实现 | — |
| Hardware switch: Device name or label | `device-list.switch-device` | 文本输入 | 未实现 | — |
| Hardware switch: Hardware switch name | `device-list.switch-switch` | 文本输入 | 未实现 | — |
| Hardware switch: Switch trigger conditions | `device-list.switch-state` | 选择 | 未实现 | — |
| Hardware switch: Trigger action | `device-list.switch-callback` | 文本输入 | 未实现 | — |
| Hardware switch: Notebook closing action | `device-list.switch-lid` | 文本输入 | 未实现 | — |
| Hardware switch: Tablet mode switching action | `device-list.switch-tablet` | 文本输入 | 未实现 | — |

### Printers — `printers`

Installed printers, the default printer and print queues

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

原因：Uses CUPS through its command-line tools.

通过 CUPS 命令行工具（`LC_ALL=C` 的 `lpstat`、`lpoptions`、`lp`、`cancel`、`cupsenable`/`cupsdisable`、`lpadmin -x`）读取和管理已安装打印机；打印机与队列跟随 CUPS 实时状态，不保存、不比对。见[打印机文档](printers.md)。添加打印机、打印首选项与扫描仪未实现，Windows 专属的自动管理默认打印机与按流量下载驱动已删除。

#### Printers

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Default printer | `printers.default` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |
| Print a test page | `printers.test-page` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |
| Pause or resume a printer | `printers.pause` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |
| Cancel a print job | `printers.cancel-job` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |
| Remove a printer | `printers.remove` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |

### Camera — `cameras`

PipeWire 摄像头清单与图像调节，实时预览由 GUI 本地 Rust 后端提供。

页面状态：**已实现**；条目：6；已实现 6 / 未实现 0 / 不适用 0。

原因：通过 PipeWire 原生接口读取能力、验证写入与回读，并保存真实配置和处理冲突。

Windows 参考入口：`ms-settings:camera`。

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connected cameras | `cameras.devices` | 信息展示 | 已实现 | Rust Camera 测试、真实设备参数写入与恢复验证；详见 [Camera](camera.md) |
| Brightness | `cameras.brightness` | 滑块 | 已实现 | Rust Camera 测试、真实设备参数写入与恢复验证；详见 [Camera](camera.md) |
| Contrast | `cameras.contrast` | 滑块 | 已实现 | Rust Camera 测试、真实设备参数写入与恢复验证；详见 [Camera](camera.md) |
| Saturation | `cameras.saturation` | 滑块 | 已实现 | Rust Camera 测试、真实设备参数写入与恢复验证；详见 [Camera](camera.md) |
| Sharpness | `cameras.sharpness` | 滑块 | 已实现 | Rust Camera 测试、真实设备参数写入与恢复验证；详见 [Camera](camera.md) |
| Reset camera settings | `cameras.reset` | 操作 | 已实现 | Rust Camera 测试、真实设备参数写入与恢复验证；详见 [Camera](camera.md) |

### Mouse — `mouse`

Buttons, pointer speed, scrolling and focus

页面状态：**已实现**；条目：12；已实现 12 / 未实现 0 / 不适用 0。

原因：Uses Hyprland input options through the Settings service.

Windows 参考入口：`ms-settings:mousetouchpad`。

实现与边界见 [输入设备与快捷键](input.md)：读取 `hyprctl descriptions` 实时值，经 `hyprctl eval` 校验后写入 Settings 自有的 `hypr/remya-settings/input.lua` 并回读；鼠标示意图随主按钮与自然滚动变化，依赖父项的选项自动隐藏。

#### Buttons

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connected mice | `mouse.devices` | 信息展示 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Primary mouse button | `mouse.primary-button` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Pointer

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Pointer speed | `mouse.pointer-speed` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Pointer acceleration | `mouse.acceleration` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Scrolling

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Natural scrolling | `mouse.natural-scroll` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Scroll speed | `mouse.scroll-speed` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Focus and selection

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Window focus | `mouse.focus-follows` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Middle-click paste | `mouse.middle-click-paste` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Refocus without crossing a window edge | `mouse.refocus` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Focus the display under the pointer | `mouse.monitor-focus` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Wheel step emulation | `mouse.discrete-scroll` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Scrolling just outside a window | `mouse.scroll-outside` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

### Touchpad — `touchpad`

Taps, clicks, scrolling and swipe gestures

页面状态：**已实现**；条目：18；已实现 18 / 未实现 0 / 不适用 0。

原因：Uses Hyprland input options through the Settings service.

Windows 参考入口：`ms-settings:devices-touchpad`。

实现与边界见 [输入设备与快捷键](input.md)；触控板示意图随右键方式切换为按键区域或多指点击，轻触相关选项在轻触关闭时自动隐藏。逐设备启用/禁用因 Hyprland 无可回读接口而未提供。

#### Taps

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connected touchpads | `touchpad.devices` | 信息展示 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Tap to click | `touchpad.tap-to-click` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Two-finger tap | `touchpad.tap-buttons` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Tap and drag | `touchpad.tap-and-drag` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Keep dragging after lifting a finger | `touchpad.drag-lock` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Clicks and dragging

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Right click | `touchpad.click-method` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Drag with several fingers | `touchpad.three-finger-drag` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Turn off the touchpad while typing | `touchpad.disable-while-typing` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Scrolling

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Natural scrolling | `touchpad.natural-scroll` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Scroll speed | `touchpad.scroll-speed` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Workspace swipe

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Swipe distance | `touchpad.swipe-distance` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Invert swipe direction | `touchpad.swipe-invert` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Create a workspace past the last one | `touchpad.swipe-create-new` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Middle click by pressing both buttons | `touchpad.middle-button` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Swipe needed to switch | `touchpad.swipe-cancel-ratio` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Speed that always switches | `touchpad.swipe-min-speed` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Keep swiping past neighbouring workspaces | `touchpad.swipe-forever` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Lock the swipe direction | `touchpad.swipe-direction-lock` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

### Keyboard shortcuts — `keyboard-shortcuts`

Key combinations for windows, workspaces, apps and commands

页面状态：**已实现**；条目：9；已实现 9 / 未实现 0 / 不适用 0。

原因：Uses Hyprland key bindings through the Settings service.

实现与边界见 [输入设备与快捷键](input.md)：键盘图按修饰键高亮已绑定按键；自定义快捷键与关闭的快捷键以 `hl.bind` / `hl.unbind` 写入 `input.lua` 并按实时 `hyprctl binds` 校验；录制时进入空 submap 暂停合成器快捷键。底层为 Hyprland 键绑定。

#### Shortcuts

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Your shortcuts | `keyboard-shortcuts.add` | 操作 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| All shortcuts | `keyboard-shortcuts.list` | 信息展示 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Turned-off shortcuts | `keyboard-shortcuts.disable` | 操作 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Remove a custom shortcut | `keyboard-shortcuts.remove` | 操作 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Record a key combination | `keyboard-shortcuts.record` | 操作 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Pressing the current workspace's shortcut | `keyboard-shortcuts.workspace-back-and-forth` | 选择 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Remember the previous workspace across switches | `keyboard-shortcuts.workspace-cycles` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Delay between scroll shortcuts | `keyboard-shortcuts.scroll-delay` | 滑块 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |
| Pass mouse events after a shortcut | `keyboard-shortcuts.pass-mouse` | 开关 | 已实现 | `cargo test -p remya_settings_input`; `test/input_test.dart`; `test/input_smoke.py`（嵌套 Hyprland 0.57） |

### Touch — `touch`

触摸手势与唤醒

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:devices-touch`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Three- and four-finger touch gestures | `touch.5cfa5330` | 开关 | 未实现 | — |
| Touch screen to wake up | `touch.de9f8969` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Three- and four-finger touch gestures | `touch.reference.b3eb626b` | 开关 | 未实现 | — |
| Touch the screen to wake (supported on some devices only) | `touch.reference.4283e4ac` | 开关 | 未实现 | — |

#### Advanced: compositor previews

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Touch mapping: enabled (enabled) | `touch.mapping-enabled` | 开关 | 未实现 | — |
| Touch mapping: Target display (output) | `touch.mapping-output` | 文本输入 | 未实现 | — |
| Touch mapping: Rotation and flipping (transform) | `touch.mapping-transform` | 滑块 | 未实现 | — |

### Autoplay — `autoplay`

可移动介质与存储卡默认行为

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:autoplay`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Use autoplay for all media and devices | `autoplay.aef48ac6` | 开关 | 未实现 | — |
| Removable drives | `autoplay.cf7a8268` | 选择 | 未实现 | — |
| Memory card | `autoplay.16fc14e6` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Use AutoPlay for all media and devices | `autoplay.reference.60b8b8bf` | 开关 | 未实现 | — |
| Removable drive | `autoplay.reference.ea178ab2` | 开关 | 未实现 | — |
| Memory card | `autoplay.reference.9dce54e3` | 开关 | 未实现 | — |

### USB — `usb`

连接问题、充电与节能

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:usb`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Notify me of connection problems | `usb.ef54bf0f` | 开关 | 未实现 | — |
| Notify me when USB charging is slow | `usb.4b9d110f` | 开关 | 未实现 | — |
| Stop USB devices when screen is off to save power | `usb.cbd35db8` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connection notifications | `usb.reference.efa5ab97` | 开关 | 未实现 | — |
| Show a notification if this PC is charging slowly over USB | `usb.reference.d575fa71` | 开关 | 未实现 | — |

### Mobile devices — `mobile`

手机连接与跨设备体验

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:mobile-devices`、`ms-settings:mobile-devices-addphone`、`ms-settings:mobile-devices-addphone-direct`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Allow access to mobile devices | `mobile.56e3e122` | 开关 | 未实现 | — |
| Manage mobile devices | `mobile.1ec69bd1` | 操作 | 未实现 | — |
| Add mobile phone | `mobile.8031425b` | 操作 | 未实现 | — |
| Show mobile suggestions | `mobile.1c9889d2` | 开关 | 未实现 | — |

<a id="category-network"></a>

## 网络和 Internet

Wi-Fi、以太网、VPN 与代理

二级页面调整：删除 `ip-dns`（IP 与 DNS 并入以太网和已知网络的每个连接）、`data-usage`（NetworkManager 无按应用计量与限额；累计用量并入网络状态）与 `network-advanced`（连接性检查并入网络状态的 Advanced，其余 Windows 专有条目删除）；页面顺序改为 网络状态、Wi-Fi、已知网络、以太网、VPN、移动热点、飞行模式、代理。

### Network status — `network-status`

Internet connection, live traffic and adapters

页面状态：**已实现**；条目：15；已实现 15 / 未实现 0 / 不适用 0。

通过 NetworkManager 读取连接、实时流量、累计用量与适配器；连接路径图显示本机、路由器与 Internet 各段状态。Advanced 中的连接性检查写入 NM `ConnectivityCheckEnabled` 并参与配置冲突比对。

Windows 参考入口：`ms-settings:network-status`、`ms-settings:network-advancedsettings`。

#### Connection

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connection status | `network-status.connection` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Network name | `network-status.name` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Current speed | `network-status.traffic` | 信息展示 | 已实现 | Rust 假后端；已安装应用实测 |
| Data used since connected | `network-status.usage` | 信息展示 | 已实现 | Rust 假后端；`test/network_test.dart` 速度与累计用量 |
| Connection type | `network-status.type` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| IPv4 address | `network-status.ipv4` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Gateway | `network-status.gateway` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| DNS servers | `network-status.dns` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| IPv6 address | `network-status.ipv6` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Link speed | `network-status.link-speed` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Hardware address | `network-status.hardware-address` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Sign in to this network | `network-status.sign-in` | 操作 | 已实现 | 仅桩验证（Rust 假后端与 `test/network_smoke.py`），按用户授权标记，未在真机切断当前网络测试 |

#### Adapters

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Network adapters | `network-status.adapters` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Virtual adapters | `network-status.virtual-adapters` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Check internet connectivity | `network-status.connectivity-check` | 开关 | 已实现 | Rust 假后端冲突与双向解决；`test/network_smoke.py` 写入读回 |

### Wi-Fi — `wifi`

无线网络与当前连接

页面状态：**已实现**；条目：8；已实现 8 / 未实现 0 / 不适用 0。

原因：已通过 NetworkManager 实现。

Windows 参考入口：`ms-settings:network-wifi`。

#### Wi-Fi

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Wi-Fi | `wifi.enabled` | 开关 | 已实现 | 仅桩验证（Rust 假后端与 `test/network_smoke.py`），按用户授权标记，未在真机切断当前网络测试 |
| Adapter | `wifi.adapter` | 选择 | 已实现 | 仅桩验证（Rust 假后端与 `test/network_smoke.py`），按用户授权标记，未在真机切断当前网络测试 |

#### Current connection

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Current network | `wifi.current` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Disconnect | `wifi.disconnect` | 操作 | 已实现 | 仅桩验证（Rust 假后端与 `test/network_smoke.py`），按用户授权标记，未在真机切断当前网络测试 |

#### Available networks

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Available networks | `wifi.networks` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Refresh | `wifi.refresh` | 操作 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Connect | `wifi.connect` | 操作 | 已实现 | 仅桩验证（Rust 假后端与 `test/network_smoke.py`），按用户授权标记，未在真机切断当前网络测试 |

#### Saved networks

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Known networks | `wifi.known-networks` | 操作 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |

### Known networks — `known-networks`

Saved networks and connection preferences

页面状态：**已实现**；条目：15；已实现 15 / 未实现 0 / 不适用 0。

已保存 Wi-Fi 的偏好均通过 NM 配置文件 `Update` 写入并读回。随机硬件地址写入 `assigned-mac-address`；连接优先级写入 `autoconnect-priority`（低 -10 / 普通 0 / 高 10），二者在 iwd 后端时自动隐藏。IP 与 DNS 编辑与以太网共用对话框。

Windows 参考入口：`ms-settings:network-wifisettings`。

#### Add a network

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Add network | `known-networks.add` | 操作 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Network name | `known-networks.name` | 文本输入 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Security type | `known-networks.security` | 选择 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Password | `known-networks.password` | 文本输入 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Hidden network | `known-networks.hidden` | 开关 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |

#### Saved networks

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Search networks | `known-networks.search` | 文本输入 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Last connected | `known-networks.last-connected` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Connect automatically | `known-networks.autoconnect` | 开关 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Metered connection | `known-networks.metered` | 选择 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Random hardware address | `known-networks.mac` | 选择 | 已实现 | Rust 假后端；`test/network_smoke.py` 经 Update/GetSettings 读回；iwd 后端时隐藏 |
| IP assignment | `known-networks.ip` | 操作 | 已实现 | Rust 假后端校验与 Reapply；`test/network_smoke.py` |
| DNS server assignment | `known-networks.dns` | 操作 | 已实现 | 同上 |
| Change password | `known-networks.change-password` | 操作 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |
| Forget | `known-networks.forget` | 操作 | 已实现 | Rust 假后端与 `test/network_smoke.py`；真实 NM 读取或一次性配置实测 |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connection priority | `known-networks.priority` | 选择 | 已实现 | Rust 假后端；`test/network_smoke.py` 读回；`test/network_test.dart`；iwd 后端时隐藏 |

### Ethernet — `ethernet`

Wired connections, addressing and DNS

页面状态：**已实现**；条目：7；已实现 7 / 未实现 0 / 不适用 0。

每个物理有线适配器显示状态、连接按钮与连接详情；其绑定的配置文件可修改自动连接、按流量计费、IP 分配与 DNS 分配。已连接时以 `Device.Reapply` 立即生效。原 Windows 网络配置文件（公用 / 专用）条目已移除。

Windows 参考入口：`ms-settings:network-ethernet`。

#### Ethernet

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Connection status | `ethernet.status` | 信息展示 | 已实现 | Rust 假后端；已安装应用读取真实 eno1 |
| Connect | `ethernet.connect` | 操作 | 已实现 | 仅桩验证（Rust 假后端），未在真机断开唯一有线连接 |
| Connect automatically | `ethernet.autoconnect` | 开关 | 已实现 | Rust 假后端；`test/network_smoke.py` |
| Metered connection | `ethernet.metered` | 选择 | 已实现 | Rust 假后端；`test/network_smoke.py` |
| IP assignment | `ethernet.ip` | 操作 | 已实现 | Rust 假后端；`test/network_smoke.py` 手动 IPv4/DNS 读回；`test/network_test.dart` 对话框校验 |
| DNS server assignment | `ethernet.dns` | 操作 | 已实现 | 同上 |
| Connection details | `ethernet.details` | 信息展示 | 已实现 | Rust 假后端；已安装应用读取真实 eno1 |

### VPN — `vpn`

WireGuard and VPN plugin connections

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

列出 NM 的 VPN 插件与 WireGuard 配置文件，开关连接；通过 `nmcli connection import` 复用 NetworkManager 自带的 WireGuard 与 VPN 插件导入器，导入后关闭自动连接并保持断开。由 Tailscale 等其他程序管理的隧道只读显示。手工创建表单与 Windows 漫游 / 计费条目已移除。

Windows 参考入口：`ms-settings:network-vpn`。

#### VPN connections

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| VPN connections | `vpn.connections` | 信息展示 | 已实现 | Rust 假后端；`test/network_smoke.py`；`test/network_test.dart` |
| Connect | `vpn.connect` | 开关 | 已实现 | Rust 假后端与 `test/network_smoke.py`（桩） |
| Import a VPN file | `vpn.import` | 操作 | 已实现 | Rust 假后端；真实 NM 1.58 导入一次性 WireGuard 文件后删除 |
| Remove | `vpn.remove` | 操作 | 已实现 | Rust 假后端；真实 NM 1.58 删除上述一次性配置 |
| VPNs managed by other apps | `vpn.external` | 信息展示 | 已实现 | `test/network_test.dart`；已安装应用读取真实 tailscale0 |

### Mobile hotspot — `hotspot`

Share this device's internet connection over Wi-Fi

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

以 NM 接入点配置文件（`mode=ap`、`ipv4.method=shared`、WPA2 CCMP）共享当前连接，适配器需支持 AP；频段按适配器能力限制。开关状态为实时状态，不保存或启动恢复；名称与频段作为配置文件偏好参与冲突比对。密码只写入 NM。无对应后端的共享来源、共享方式、空闲自动关闭条目已移除。

Windows 参考入口：`ms-settings:network-mobilehotspot`。

#### Mobile hotspot

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mobile hotspot | `hotspot.enabled` | 开关 | 已实现 | 仅桩验证（Rust 假后端与 `test/network_smoke.py`），未在真机广播热点 |
| Sharing internet from | `hotspot.source` | 信息展示 | 已实现 | `test/network_test.dart` |
| Network name | `hotspot.name` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py` |
| Network band | `hotspot.band` | 信息展示 | 已实现 | Rust 假后端与 `test/network_smoke.py` |
| Name, password and band | `hotspot.configure` | 操作 | 已实现 | Rust 假后端与 `test/network_smoke.py`；`test/network_test.dart` 设置对话框 |

### Airplane mode — `airplane`

页面状态：**已实现**；条目：2；已实现 2 / 未实现 0 / 不适用 0。

通过 NetworkManager 的 WirelessEnabled / WwanEnabled 与所有 BlueZ Adapter1.Powered 控制无线电；状态实时派生，不保存或在启动时恢复。关闭飞行模式会启用这些无线电；硬件阻止、授权失败和部分失败均报告错误，并保留真实读回状态。有线网络不受影响。

Windows 参考入口：`ms-settings:network-airplanemode`、`ms-settings:proximity`。

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Airplane mode | `airplane.enabled` | 开关 | 已实现 | Rust network airplane tests; `test/airplane_test.dart`; `test/airplane_smoke.py` |
| Wi-Fi wireless devices | `airplane.wifi` | 开关 | 已实现 | 同上；写入后读回验证 |

### Proxy — `proxy`

Desktop proxy for apps that follow system settings

页面状态：**已实现**；条目：6；已实现 6 / 未实现 0 / 不适用 0。

读写 GSettings `org.gnome.system.proxy`（GIO、libproxy、Chromium、Firefox 使用）。代理工具会频繁切换，因此实时跟随系统状态，不保存或比对（已在 AGENTS.md 记录）。模式为关闭 / 自动检测（WPAD）/ 设置脚本 / 手动；手动包含 HTTP、HTTPS、SOCKS 与例外主机。

Windows 参考入口：`ms-settings:network-proxy`。

#### Proxy

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Proxy | `proxy.mode` | 选择 | 已实现 | Rust GSettings 内存后端测试；`test/network_smoke.py` 隔离 keyfile 后端 |
| Script address | `proxy.script` | 文本输入 | 已实现 | Rust GSettings 内存后端测试；`test/network_smoke.py` 隔离 keyfile 后端 |
| HTTP proxy | `proxy.http` | 文本输入 | 已实现 | Rust GSettings 内存后端测试；`test/network_smoke.py` 隔离 keyfile 后端 |
| HTTPS proxy | `proxy.https` | 文本输入 | 已实现 | Rust GSettings 内存后端测试；`test/network_smoke.py` 隔离 keyfile 后端 |
| SOCKS host | `proxy.socks` | 文本输入 | 已实现 | Rust GSettings 内存后端测试；`test/network_smoke.py` 隔离 keyfile 后端 |
| Don't use the proxy for | `proxy.ignore` | 文本输入 | 已实现 | Rust GSettings 内存后端测试；`test/network_smoke.py` 隔离 keyfile 后端 |

<a id="category-appearance"></a>

## 外观

背景、主题与桌面外观

### Background — `background`

桌面背景：图片（hyprpaper）或视频（mpvpaper），以及窗口模糊

页面状态：**已实现**；条目：21；已实现 21 / 未实现 0 / 不适用 0。

原因：图片和视频背景、窗口模糊、备用背景色与 Hyprland 标志均已实现。

Windows 参考入口：`ms-settings:personalization-background`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Background type | `background.99b01ada` | 选择 | 已实现 | 见下文“Background, accent and fonts” |
| Display | `background.display` | 选择 | 已实现 | 见下文“Background, accent and fonts” |
| Background file | `background.9e58290b` | 操作 | 已实现 | 见下文“Background, accent and fonts” |
| Fit | `background.56c289eb` | 选择 | 已实现 | 见下文“Background, accent and fonts” |

#### Window blur

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Blur behind windows | `background.blur-enabled` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Blur style | `background.blur-variant` | 选择 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Blur radius | `background.blur-size` | 滑块 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Blur passes | `background.blur-passes` | 滑块 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Video when covered | `background.video-pause` | 选择 | 已实现 | 见下文“Background, accent and fonts” |
| Show splash text | `background.splash` | 开关 | 已实现 | 见下文“Background, accent and fonts” |
| Splash offset | `background.splash-offset` | 滑块 | 已实现 | 见下文“Background, accent and fonts” |
| Splash opacity | `background.splash-opacity` | 滑块 | 已实现 | 见下文“Background, accent and fonts” |
| Noise | `background.blur-noise` | 滑块 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Contrast | `background.blur-contrast` | 滑块 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Brightness | `background.blur-brightness` | 滑块 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Vibrancy | `background.blur-vibrancy` | 滑块 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Floating windows blur only the background | `background.blur-xray` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Blur menus | `background.blur-popups` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Blur behind special workspaces | `background.blur-special` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Fallback color | `background.fallback-color` | 颜色 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |
| Hide Hyprland logo | `background.hide-logo` | 开关 | 已实现 | Rust `remya_settings_input` desktop tests；`test/desktop_smoke.py`（嵌套 Hyprland 0.57）；`test/background_test.dart` |

### Colors and themes — `themes`

深浅色、强调色、Material 调色板与主题

页面状态：**已实现**；条目：7；已实现 7 / 未实现 0 / 不适用 0。

原因：Light/Dark, accent color, Material palette and icon themes use the Settings service and the app configuration.

Windows 参考入口：`ms-settings:personalization-colors`、`ms-settings:colors`、`ms-settings:themes`。

图标主题与主题包见下文“Multitasking, cursor and icon themes (2026-11-09)”。窗口装饰与动画预览移至“窗口外观”和“动画”页面；Windows 主题包（选择主题、保存主题、背景、声音链接）、透明效果（与“背景”中的窗口模糊重复）、渐变编辑器、桌面组件预设与屏幕着色器路径已删除。

#### Color

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Dark theme | `themes.material-theme-mode` | 选择 | 已实现 | Rust GNOME/GTK Light/Dark and documented Qt Quick defaults via fish/Hyprland; Light/Dark icon buttons, backend target diagnostics hidden; see app-preferences.md and backend tests |
| Accent color source | `themes.8983f367` | 选择 | 已实现 | 见下文“Background, accent and fonts” |
| Accent Color | `themes.6f67371e` | 颜色 | 已实现 | 见下文“Background, accent and fonts” |
| Material style variant | `themes.material-style-variant` | 选择 | 已实现 | App-only TOML persistence and runtime theme; Tonal spot default; see app-preferences.md and appearance tests |

#### Icons

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Icon theme | `themes.icon-theme` | 选择 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Add an icon or cursor theme | `themes.icon-install` | 操作 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Remove an added theme | `themes.icon-remove` | 操作 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

### Cursor — `cursor`

Cursor theme, size, hiding and pointer movement

页面状态：**已实现**；条目：14；已实现 14 / 未实现 0 / 不适用 0。

原因：Uses GNOME interface settings, GTK, KDE, XCursor and Hyprland through the Settings service.

Windows 参考入口：`ms-settings:easeofaccess-cursor`、`ms-settings:easeofaccess-mousepointer`。

光标主题与大小写入 GNOME 接口设置、GTK 3/4 settings.ini、XCursor `default` 主题、KDE（kcminputrc，经 kwriteconfig6）、fish 与 Hyprland 环境块，并经 `hyprctl setcursor` 即时生效；隐藏与指针移动选项属于 desktop 分组。主题包从图标搜索路径与 `XCURSOR_PATH` 发现，可从文件夹或归档添加到用户图标目录、删除用户添加的主题。Windows 专属的指针颜色、文本光标指示器与参考项，以及缩放（属于放大镜）、调试类光标选项已删除。

#### Cursor theme

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Cursor theme | `cursor.theme` | 选择 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Cursor size | `cursor.size` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Theme packs

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Add a cursor or icon theme | `cursor.install` | 操作 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Remove an added theme | `cursor.remove` | 操作 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Theme folders | `cursor.folders` | 信息展示 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Hiding

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Hide while typing | `cursor.hide-on-key-press` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Hide when not moved for | `cursor.inactive-timeout` | 滑块 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Hide while using a touchscreen | `cursor.hide-on-touch` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Hide while using a pen tablet | `cursor.hide-on-tablet` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Pointer movement

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Keep the pointer where you leave it | `cursor.no-warps` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Move the pointer after switching workspaces | `cursor.warp-on-change-workspace` | 选择 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Return to the last position in a window | `cursor.persistent-warps` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Hardware cursor | `cursor.hardware` | 选择 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
| Prefer scalable cursor themes | `cursor.enable-hyprcursor` | 开关 | 已实现 | 见下文“Multitasking, cursor and icon themes (2026-11-09)” |
### Window appearance — `window-appearance`

圆角、边框颜色、透明度、调暗、阴影与发光

页面状态：**已实现**；条目：23；已实现 23 / 未实现 0 / 不适用 0。

原因：Uses Hyprland window options through the Settings service.

实现与边界见 [输入设备与快捷键](input.md) 的 desktop 分组：读取 `hyprctl descriptions` 实时值，经 `hyprctl eval` 校验后写入 Settings 自有的 `hypr/remya-settings/desktop.lua` 并回读。页首示意图以前后两个窗口实时呈现圆角（含曲率）、边框颜色与宽度、透明度、非焦点调暗、阴影与内发光；子选项在父项关闭时自动隐藏。非焦点阴影 / 发光颜色（未设置时的回退语义无法回读）与仅窗口规则使用的 dim_around 已删除。

#### Corners

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Corner radius | `window-appearance.rounding` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Corner shape | `window-appearance.rounding-power` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Borders

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Focused window border | `window-appearance.active-border` | 颜色 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Other window borders | `window-appearance.inactive-border` | 颜色 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Transparency

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Focused window | `window-appearance.active-opacity` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Other windows | `window-appearance.inactive-opacity` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Full screen windows | `window-appearance.fullscreen-opacity` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Dimming

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Dim windows that are not focused | `window-appearance.dim-inactive` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Dimming strength | `window-appearance.dim-strength` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Dim the window behind a dialog | `window-appearance.dim-modal` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Dim the desktop behind the scratchpad | `window-appearance.dim-special` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Shadow

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Window shadow | `window-appearance.shadow` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Shadow color | `window-appearance.shadow-color` | 颜色 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Shadow size | `window-appearance.shadow-range` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Shadow offset | `window-appearance.shadow-offset` | 文本输入 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Glow

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Inner glow | `window-appearance.glow` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Glow color | `window-appearance.glow-color` | 颜色 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Glow size | `window-appearance.glow-range` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Shadow falloff | `window-appearance.shadow-render-power` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Shadow scale | `window-appearance.shadow-scale` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Sharp shadow edge | `window-appearance.shadow-sharp` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Glow falloff | `window-appearance.glow-render-power` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Count the border as part of the window | `window-appearance.border-part-of-window` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

### Animations — `animations`

窗口与工作区动画、动态模糊与果冻窗口

页面状态：**已实现**；条目：14；已实现 14 / 未实现 0 / 不适用 0。

原因：Uses Hyprland window options through the Settings service.

实现与边界同 desktop 分组（见 [输入设备与快捷键](input.md)）。单个动画树（`hl.animation` 与曲线）编辑已删除：它需要独立的动画/曲线行格式与回读，暂不纳入。动态模糊与果冻窗口的参数仅在对应开关打开时显示。

#### Animations

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Animation effects | `animations.enabled` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Animate windows while resizing them | `animations.resize` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Animate windows while dragging them | `animations.drag` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Wrap around between the first and last workspace | `animations.workspace-wraparound` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Motion blur

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Motion blur | `animations.motion-blur` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Blur quality | `animations.motion-blur-samples` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Wobbly windows

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Wobbly windows | `animations.wobble` | 开关 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Wobble strength | `animations.wobble-intensity` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Stiffness | `animations.wobble-stiffness` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Damping | `animations.wobble-damping` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Mass | `animations.wobble-mass` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Wobble mesh detail | `animations.wobble-mesh` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Settle distance | `animations.wobble-value-epsilon` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |
| Settle speed | `animations.wobble-velocity-epsilon` | 滑块 | 已实现 | 见下文“Window appearance, animations and dwindle (2026-11-09)” |

### Lock screen interface — `lockscreen`

锁屏背景、状态与登录画面

页面状态：**未实现**；条目：111；已实现 0 / 未实现 111 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:lockscreen`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Lock screen background | `lockscreen.70c5d385` | 选择 | 未实现 | — |
| Select image | `lockscreen.18104edf` | 操作 | 未实现 | — |
| Lock screen status | `lockscreen.a0216293` | 选择 | 未实现 | — |
| Show tips and suggestions | `lockscreen.827be04c` | 开关 | 未实现 | — |
| Login interface displays lock screen background | `lockscreen.74460c63` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Personalize your lock screen | `lockscreen.reference.3ada0526` | 开关 | 未实现 | — |
| Get fun facts, tips, tricks, and more on your lock screen | `lockscreen.reference.252498b5` | 开关 | 未实现 | — |
| Show the lock screen background picture on the sign-in screen | `lockscreen.reference.6437619e` | 开关 | 未实现 | — |

#### Advanced: compositor previews

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Restore session lock (allow_session_lock_restore) | `lockscreen.compositor-restore` | 开关 | 未实现 | — |
| Unresponsive lock screen delay (lockdead_screen_delay) | `lockscreen.compositor-dead-delay` | 滑块 | 未实现 | — |
| Compositor lock blur (session_lock_blur) | `lockscreen.compositor-blur` | 开关 | 未实现 | — |
| Compositor lock xray (session_lock_xray) | `lockscreen.compositor-xray` | 开关 | 未实现 | — |
| Lock screen: Hide cursor (hide_cursor) | `lockscreen.general-hide-cursor` | 开关 | 未实现 | — |
| Lock screen: ignore empty input (ignore_empty_input) | `lockscreen.general-ignore-empty-input` | 开关 | 未实现 | — |
| Lock screen: immediate render (immediate_render) | `lockscreen.general-immediate-render` | 开关 | 未实现 | — |
| Lock screen: text trim (text_trim) | `lockscreen.general-text-trim` | 开关 | 未实现 | — |
| Lock screen: fractional scaling (fractional_scaling) | `lockscreen.general-fractional-scaling` | 文本输入 | 未实现 | — |
| Lock screen: screencopy mode (screencopy_mode) | `lockscreen.general-screencopy-mode` | 文本输入 | 未实现 | — |
| Lock screen: fail timeout (fail_timeout) | `lockscreen.general-fail-timeout` | 文本输入 | 未实现 | — |
| Lock authentication: pam:enabled (pam:enabled) | `lockscreen.authentication-pam-enabled` | 开关 | 未实现 | — |
| Lock authentication: pam:module (pam:module) | `lockscreen.authentication-pam-module` | 文本输入 | 未实现 | — |
| Lock authentication: fingerprint:enabled (fingerprint:enabled) | `lockscreen.authentication-fingerprint-enabled` | 开关 | 未实现 | — |
| Lock authentication: fingerprint:ready message (fingerprint:ready_message) | `lockscreen.authentication-fingerprint-ready-message` | 文本输入 | 未实现 | — |
| Lock authentication: fingerprint:present message (fingerprint:present_message) | `lockscreen.authentication-fingerprint-present-message` | 文本输入 | 未实现 | — |
| Lock authentication: fingerprint:retry delay (fingerprint:retry_delay) | `lockscreen.authentication-fingerprint-retry-delay` | 文本输入 | 未实现 | — |
| Lock animation: enabled (enabled) | `lockscreen.animation-enabled` | 开关 | 未实现 | — |
| Lock shadow: shadow passes (shadow_passes) | `lockscreen.shadow-shadow-passes` | 文本输入 | 未实现 | — |
| Lock shadow: shadow size (shadow_size) | `lockscreen.shadow-shadow-size` | 文本输入 | 未实现 | — |
| Lock shadow: shadow color (shadow_color) | `lockscreen.shadow-shadow-color` | 文本输入 | 未实现 | — |
| Lock shadow: shadow boost (shadow_boost) | `lockscreen.shadow-shadow-boost` | 文本输入 | 未实现 | — |
| Lock interaction: onclick (onclick) | `lockscreen.click-onclick` | 文本输入 | 未实现 | — |
| Lock background: Monitor matching (monitor) | `lockscreen.background-monitor` | 文本输入 | 未实现 | — |
| Lock background: Resource path (path) | `lockscreen.background-path` | 文本输入 | 未实现 | — |
| Lock background: color (color) | `lockscreen.background-color` | 文本输入 | 未实现 | — |
| Lock background: Lock screen background blur times (blur_passes) | `lockscreen.background-blur-passes` | 文本输入 | 未实现 | — |
| Lock background: Lock screen background blur size (blur_size) | `lockscreen.background-blur-size` | 文本输入 | 未实现 | — |
| Lock background: Noise intensity (noise) | `lockscreen.background-noise` | 文本输入 | 未实现 | — |
| Lock background: Contrast (contrast) | `lockscreen.background-contrast` | 文本输入 | 未实现 | — |
| Lock background: Brightness adjustment (brightness) | `lockscreen.background-brightness` | 文本输入 | 未实现 | — |
| Lock background: Blur color saturation improvement (vibrancy) | `lockscreen.background-vibrancy` | 文本输入 | 未实现 | — |
| Lock background: Effect of dark area saturation (vibrancy_darkness) | `lockscreen.background-vibrancy-darkness` | 文本输入 | 未实现 | — |
| Lock background: reload time (reload_time) | `lockscreen.background-reload-time` | 文本输入 | 未实现 | — |
| Lock background: reload cmd (reload_cmd) | `lockscreen.background-reload-cmd` | 文本输入 | 未实现 | — |
| Lock background: Background switching time (crossfade_time) | `lockscreen.background-crossfade-time` | 文本输入 | 未实现 | — |
| Lock background: zindex (zindex) | `lockscreen.background-zindex` | 文本输入 | 未实现 | — |
| Lock image: Monitor matching (monitor) | `lockscreen.image-monitor` | 文本输入 | 未实现 | — |
| Lock image: Resource path (path) | `lockscreen.image-path` | 文本输入 | 未实现 | — |
| Lock image: Window or control size (size) | `lockscreen.image-size` | 文本输入 | 未实现 | — |
| Lock image: Corner radius (rounding) | `lockscreen.image-rounding` | 文本输入 | 未实现 | — |
| Lock image: Window border width (border_size) | `lockscreen.image-border-size` | 文本输入 | 未实现 | — |
| Lock image: Window border gradient overlay (border_color) | `lockscreen.image-border-color` | 文本输入 | 未实现 | — |
| Lock image: rotate (rotate) | `lockscreen.image-rotate` | 文本输入 | 未实现 | — |
| Lock image: reload time (reload_time) | `lockscreen.image-reload-time` | 文本输入 | 未实现 | — |
| Lock image: reload cmd (reload_cmd) | `lockscreen.image-reload-cmd` | 文本输入 | 未实现 | — |
| Lock image: Virtual desktop position (position) | `lockscreen.image-position` | 文本输入 | 未实现 | — |
| Lock image: Horizontal alignment (halign) | `lockscreen.image-halign` | 文本输入 | 未实现 | — |
| Lock image: Vertical alignment (valign) | `lockscreen.image-valign` | 文本输入 | 未实现 | — |
| Lock image: zindex (zindex) | `lockscreen.image-zindex` | 文本输入 | 未实现 | — |
| Lock shape: Monitor matching (monitor) | `lockscreen.shape-monitor` | 文本输入 | 未实现 | — |
| Lock shape: Window or control size (size) | `lockscreen.shape-size` | 文本输入 | 未实现 | — |
| Lock shape: color (color) | `lockscreen.shape-color` | 文本输入 | 未实现 | — |
| Lock shape: Corner radius (rounding) | `lockscreen.shape-rounding` | 文本输入 | 未实现 | — |
| Lock shape: rotate (rotate) | `lockscreen.shape-rotate` | 文本输入 | 未实现 | — |
| Lock shape: Window border width (border_size) | `lockscreen.shape-border-size` | 文本输入 | 未实现 | — |
| Lock shape: Window border gradient overlay (border_color) | `lockscreen.shape-border-color` | 文本输入 | 未实现 | — |
| Lock shape: Penetration effect (xray) | `lockscreen.shape-xray` | 开关 | 未实现 | — |
| Lock shape: Virtual desktop position (position) | `lockscreen.shape-position` | 文本输入 | 未实现 | — |
| Lock shape: Horizontal alignment (halign) | `lockscreen.shape-halign` | 文本输入 | 未实现 | — |
| Lock shape: Vertical alignment (valign) | `lockscreen.shape-valign` | 文本输入 | 未实现 | — |
| Lock shape: zindex (zindex) | `lockscreen.shape-zindex` | 文本输入 | 未实现 | — |
| Lock password field: Monitor matching (monitor) | `lockscreen.input-monitor` | 文本输入 | 未实现 | — |
| Lock password field: Window or control size (size) | `lockscreen.input-size` | 文本输入 | 未实现 | — |
| Lock password field: outline thickness (outline_thickness) | `lockscreen.input-outline-thickness` | 文本输入 | 未实现 | — |
| Lock password field: Password dot size (dots_size) | `lockscreen.input-dots-size` | 文本输入 | 未实现 | — |
| Lock password field: Password dot spacing (dots_spacing) | `lockscreen.input-dots-spacing` | 文本输入 | 未实现 | — |
| Lock password field: dots center (dots_center) | `lockscreen.input-dots-center` | 开关 | 未实现 | — |
| Lock password field: dots rounding (dots_rounding) | `lockscreen.input-dots-rounding` | 文本输入 | 未实现 | — |
| Lock password field: dots text format (dots_text_format) | `lockscreen.input-dots-text-format` | 文本输入 | 未实现 | — |
| Lock password field: outer color (outer_color) | `lockscreen.input-outer-color` | 文本输入 | 未实现 | — |
| Lock password field: inner color (inner_color) | `lockscreen.input-inner-color` | 文本输入 | 未实现 | — |
| Lock password field: font color (font_color) | `lockscreen.input-font-color` | 文本输入 | 未实现 | — |
| Lock password field: Font family (font_family) | `lockscreen.input-font-family` | 文本输入 | 未实现 | — |
| Lock password field: Empty input fades out (fade_on_empty) | `lockscreen.input-fade-on-empty` | 开关 | 未实现 | — |
| Lock password field: fade timeout (fade_timeout) | `lockscreen.input-fade-timeout` | 文本输入 | 未实现 | — |
| Lock password field: Password input placeholder text (placeholder_text) | `lockscreen.input-placeholder-text` | 文本输入 | 未实现 | — |
| Lock password field: Hide input content (hide_input) | `lockscreen.input-hide-input` | 开关 | 未实现 | — |
| Lock password field: hide input base color (hide_input_base_color) | `lockscreen.input-hide-input-base-color` | 文本输入 | 未实现 | — |
| Lock password field: Corner radius (rounding) | `lockscreen.input-rounding` | 文本输入 | 未实现 | — |
| Lock password field: check color (check_color) | `lockscreen.input-check-color` | 文本输入 | 未实现 | — |
| Lock password field: check text (check_text) | `lockscreen.input-check-text` | 文本输入 | 未实现 | — |
| Lock password field: fail color (fail_color) | `lockscreen.input-fail-color` | 文本输入 | 未实现 | — |
| Lock password field: Verification failure text (fail_text) | `lockscreen.input-fail-text` | 文本输入 | 未实现 | — |
| Lock password field: capslock color (capslock_color) | `lockscreen.input-capslock-color` | 文本输入 | 未实现 | — |
| Lock password field: numlock color (numlock_color) | `lockscreen.input-numlock-color` | 文本输入 | 未实现 | — |
| Lock password field: bothlock color (bothlock_color) | `lockscreen.input-bothlock-color` | 文本输入 | 未实现 | — |
| Lock password field: invert numlock (invert_numlock) | `lockscreen.input-invert-numlock` | 开关 | 未实现 | — |
| Lock password field: swap font color (swap_font_color) | `lockscreen.input-swap-font-color` | 开关 | 未实现 | — |
| Lock password field: Virtual desktop position (position) | `lockscreen.input-position` | 文本输入 | 未实现 | — |
| Lock password field: Horizontal alignment (halign) | `lockscreen.input-halign` | 文本输入 | 未实现 | — |
| Lock password field: Vertical alignment (valign) | `lockscreen.input-valign` | 文本输入 | 未实现 | — |
| Lock password field: zindex (zindex) | `lockscreen.input-zindex` | 文本输入 | 未实现 | — |
| Lock label: Monitor matching (monitor) | `lockscreen.label-monitor` | 文本输入 | 未实现 | — |
| Lock label: Text content (text) | `lockscreen.label-text` | 文本输入 | 未实现 | — |
| Lock label: text align (text_align) | `lockscreen.label-text-align` | 文本输入 | 未实现 | — |
| Lock label: color (color) | `lockscreen.label-color` | 文本输入 | 未实现 | — |
| Lock label: Font size (font_size) | `lockscreen.label-font-size` | 文本输入 | 未实现 | — |
| Lock label: Font family (font_family) | `lockscreen.label-font-family` | 文本输入 | 未实现 | — |
| Lock label: rotate (rotate) | `lockscreen.label-rotate` | 文本输入 | 未实现 | — |
| Lock label: Virtual desktop position (position) | `lockscreen.label-position` | 文本输入 | 未实现 | — |
| Lock label: Horizontal alignment (halign) | `lockscreen.label-halign` | 文本输入 | 未实现 | — |
| Lock label: Vertical alignment (valign) | `lockscreen.label-valign` | 文本输入 | 未实现 | — |

### Fonts — `fonts`

浏览、预览、安装与卸载字体

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

原因：Reads the fontconfig font list, installs and removes font files in your user font directory, and sets the Hyprland compositor font.

Windows 参考入口：`ms-settings:fonts`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Search fonts | `fonts.65a8477b` | 文本输入 | 已实现 | 见下文“Background, accent and fonts” |
| Install fonts | `fonts.158ba0bb` | 操作 | 已实现 | 见下文“Background, accent and fonts” |
| Font details | `fonts.fc3969c7` | 操作 | 已实现 | 见下文“Background, accent and fonts” |
| Uninstall fonts | `fonts.f869cae5` | 操作 | 已实现 | 见下文“Background, accent and fonts” |

#### Advanced

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Compositor font family (font_family) | `fonts.compositor-family` | 文本输入 | 已实现 | Rust input/desktop 测试；`test/fonts_test.dart`；`test/desktop_smoke.py`（嵌套 Hyprland 0.57） |

### Dynamic light effects — `lighting`

兼容设备的灯光与效果

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:personalization-lighting`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Use dynamic lighting effects | `lighting.c311d486` | 开关 | 未实现 | — |
| Compatible app to control lights | `lighting.53e0654b` | 开关 | 未实现 | — |
| Brightness | `lighting.5d419889` | 滑块 | 未实现 | — |
| Effect | `lighting.151ddd4f` | 选择 | 未实现 | — |
| Light color | `lighting.bf0bca1e` | 颜色 | 未实现 | — |
| Match with accent colors | `lighting.869e06ec` | 开关 | 未实现 | — |

<a id="category-ai"></a>

### AI Providers — `ai-providers`

| 设置项 | ID | 类型 | 状态 | 说明 |
| --- | --- | --- | --- | --- |
| AI providers | `ai.providers` | 信息 | 已实现 | 服务通过 CodexBar 用量探测（内存缓存 5 分钟）列出可见来源与可添加目录，追踪开关、数据来源与凭据（`ai.credential`，仅经 stdin 传递）写入 CodexBar 配置并回读；自定义端点（`ai.custom`）存于 `remya-ai.toml`，API 密钥存于 Secret Service；models.dev 元数据缓存 24 小时；去除账户邮箱；Rust 单元测试覆盖状态分类、邮箱剥离、校验、TOML 往返与缓存选择，接口冒烟测试覆盖 CLI/D-Bus Get 对等 |

### AI Usage — `ai-usage`

| 设置项 | ID | 类型 | 状态 | 说明 |
| --- | --- | --- | --- | --- |
| Bar quota pill | `ai.bar` | 信息 | 已实现 | 最多固定 3 个当前可见来源、低额度阈值 1–100 %，原子写入 `remya-ai.toml`；CLI/D-Bus Set 往返冒烟测试 |

### Remy'a Bar — `remya-bar`

| 设置项 | 控件 ID | 类型 | 状态 | 实现依据 |
| --- | --- | --- | --- | --- |
| Pill layout | `remya-bar.layout` | 操作 | 已实现 | Settings 服务校验并原子持久化分组、排序、显隐与 pill 选项（含默认关闭的媒体标题跑马灯），CLI/D-Bus 对等测试，Bar 实时应用 |
| Show seconds | `remya-bar.clock-seconds` | 开关 | 已实现 | Settings 服务持久化，CLI/D-Bus 对等测试，安装版开关联动三个 Hyprland 输出 |
| Folded apps | `remya-bar.folded-apps` | 操作 | 已实现 | Settings 持久化托盘折叠状态，支持从设置页恢复固定。 |
| Show touch key previews | `remya-bar.keyboard-preview` | 开关 | 已实现 | Settings persists the preference and exposes it through CLI and D-Bus. |
| Volume step size | `remya-bar.volume-step` | 滑块 | 已实现 | Settings 服务校验 1–25% 并原子持久化到 `remya-bar-osd.toml`，CLI/D-Bus 对等测试，Bar OSD 快捷键步进实时消费 |
| Maximum volume | `remya-bar.volume-max` | 滑块 | 已实现 | Settings 服务校验 100–150% 并原子持久化到 `remya-bar-osd.toml`，CLI/D-Bus 对等测试，Bar OSD 快捷键与侧栏输出音量滑块实时消费 |
| Brightness step size | `remya-bar.brightness-step` | 滑块 | 已实现 | Settings 服务校验 1–25% 并原子持久化到 `remya-bar-osd.toml`，CLI/D-Bus 对等测试，Bar OSD 亮度/Gamma 步进实时消费 |
| Minimum gamma | `remya-bar.gamma-min` | 滑块 | 已实现 | Settings 服务校验 10–90% 并原子持久化到 `remya-bar-osd.toml`，CLI/D-Bus 对等测试，Bar OSD Gamma 下限实时消费 |

### More — `appearance-more`

打开实际已安装的外部设置应用。未安装的入口自动隐藏。

页面状态：**已实现**；条目：4；已实现 4 / 未实现 0 / 不适用 0。

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Qt 6 Settings | `appearance-more.qt6ct` | 操作 | 已实现 | Rust 检测测试、CLI/D-Bus 对等与实机打开验证 |
| Kvantum Manager | `appearance-more.kvantum` | 操作 | 已实现 | Rust 检测测试、CLI/D-Bus 对等与实机打开验证 |
| GTK Settings | `appearance-more.gtk` | 操作 | 已实现 | 未安装时隐藏与拒绝启动的检测测试；本机未安装 nwg-look，未验证其窗口 |
| GNOME Tweaks | `appearance-more.gnome-tweaks` | 操作 | 已实现 | Rust 检测测试、CLI/D-Bus 对等与实机打开验证 |

<a id="category-apps"></a>

## 应用

应用管理、默认应用与启动项

### Installed apps — `installed`

应用目录、真实包信息、搜索排序与包管理器卸载

页面状态：**已实现**；条目：5；已实现 5 / 未实现 0 / 不适用 0。

原因：Rust 读取 GIO 应用目录与 ALPM/Flatpak 元数据；详情显示真实版本、大小与安装日期；卸载交由包管理器并回读确认。

Windows 参考入口：`ms-settings:appsfeatures`。

相关页面 ID：`app-properties`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Search installed apps | `installed.15735a25` | 文本输入 | 已实现 | Rust ALPM 解析测试、`test/service_controllers_test.dart`、隔离 Flatpak 实际卸载与数据保留验证；原生包实机读取及未授权拒绝验证（未执行本机原生包卸载） |
| Sort by | `installed.3bf3689a` | 选择 | 已实现 | Rust ALPM 解析测试、`test/service_controllers_test.dart`、隔离 Flatpak 实际卸载与数据保留验证；原生包实机读取及未授权拒绝验证（未执行本机原生包卸载） |
| Filter source | `installed.765cf6c3` | 选择 | 已实现 | Rust ALPM 解析测试、`test/service_controllers_test.dart`、隔离 Flatpak 实际卸载与数据保留验证；原生包实机读取及未授权拒绝验证（未执行本机原生包卸载） |
| Application details | `installed.32098ab2` | 操作 | 已实现 | Rust ALPM 解析测试、`test/service_controllers_test.dart`、隔离 Flatpak 实际卸载与数据保留验证；原生包实机读取及未授权拒绝验证（未执行本机原生包卸载） |
| Uninstall apps | `installed.c3c4a29c` | 操作 | 已实现 | Rust ALPM 解析测试、`test/service_controllers_test.dart`、隔离 Flatpak 实际卸载与数据保留验证；原生包实机读取及未授权拒绝验证（未执行本机原生包卸载） |

### AppImages — `appimages`

AppImage 集中目录、安装、更新源与实时更新进度

页面状态：**已实现**；条目：10；已实现 10 / 未实现 0 / 不适用 0。

原因：Rust 服务管理 `~/AppImages`；用 `appimage` crate 读取元数据（不执行镜像），用 `zsync-rs` 增量更新，校验后才替换文件。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Install AppImage | `appimages.install` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Open | `appimages.open` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Add to launcher | `appimages.integrate` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Move to Trash | `appimages.uninstall` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Check for updates | `appimages.check` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Update | `appimages.update` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Cancel update | `appimages.cancel` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Update source | `appimages.source` | 文本输入 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Check automatically | `appimages.auto-check` | 开关 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |
| Install updates automatically | `appimages.auto-update` | 开关 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、`test/appimages_smoke.py`、本机接管实机验证 |

### Advanced app options — `app-properties`

应用详情与维护

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:appsfeatures-app`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Application version | `app-properties.e8427b83` | 信息展示 | 未实现 | — |
| Terminate the application | `app-properties.6a3d60ab` | 操作 | 未实现 | — |
| Repair application | `app-properties.dba04b1b` | 操作 | 未实现 | — |
| Reset application | `app-properties.2888e689` | 操作 | 未实现 | — |
| Uninstall apps | `app-properties.c3c4a29c` | 操作 | 未实现 | — |

### Default apps — `defaults`

文件类型、协议与应用默认值，详见 [Default apps 实现说明](default-apps.md)。

页面状态：**已实现**；条目：11；已实现 11 / 未实现 0 / 不适用 0。

原因：普通用户 Rust 服务管理 XDG 关联并通过 GIO 回读。首次采用系统配置，冲突支持双向解决。重置清除用户通用和当前桌面专用的默认覆盖，并保存回读结果。

Windows 参考入口：`ms-settings:defaultapps`、`ms-settings:defaultbrowsersettings`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Search for file type or link type | `defaults.b131ac5a` | 文本输入 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Search applications | `defaults.897fdfef` | 文本输入 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Default browser | `defaults.ccac113f` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Default Mail App | `defaults.3adc9929` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Default Photos App | `defaults.c0b97974` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Default video app | `defaults.e7fe6be6` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Audio | `defaults.audio` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Text editor | `defaults.text` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| PDF | `defaults.pdf` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| File manager | `defaults.file-manager` | 操作 | 已实现 | Rust 单元测试、`test/service_controllers_test.dart`、隔离 XDG `test/interface_smoke.py` 实际读写及 CLI/D-Bus 对等验证 |
| Reset all default apps | `defaults.ff4c4bec` | 操作 | 已实现 | 隔离 XDG `test/interface_smoke.py` 验证系统默认回读、保留其他关联和 CLI/D-Bus 对等 |

### Startup apps — `startup`

Apps and commands that start when you sign in

页面状态：**已实现**；条目：4；已实现 4 / 未实现 0 / 不适用 0。

原因：Uses XDG autostart entries started by UWSM. Changes apply at the next sign-in.

Windows 参考入口：`ms-settings:startupapps`。

Implementation and boundaries: [Startup apps](startup.md). Verification uses temporary XDG roots, fake systemd observations, Flutter widget tests and the normal CLI/D-Bus smoke flow (run by the architect after installation); actual UWSM sign-in remains untested.

#### Settings

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Apps that start when you sign in | `startup.apps` | 开关 | 已实现 | `cargo test -p remya_settings_startup -p remya_settings_service`; `test/startup_page_test.dart`; `test/interface_smoke.py` normal installed flow: toggle/readback, conflicts; Rust tests also cover minimal disabling stubs and status fakes |
| Add an app | `startup.add-app` | 操作 | 已实现 | Rust GIO file-copy boundary tests; `test/startup_page_test.dart`; isolated candidate and add-app CLI/D-Bus checks |
| Remove a startup entry | `startup.remove` | 操作 | 已实现 | Rust removable-only/readback tests; `test/startup_page_test.dart` confirmation; isolated CLI/D-Bus remove/readback |

#### Advanced（默认折叠）

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Add a custom command | `startup.add-command` | 操作 | 已实现 | Rust argv/Exec quoting, collisions and validation tests; `test/startup_page_test.dart` inline errors; isolated CLI/D-Bus add-command |

<a id="category-accounts"></a>

### Window rules — `window-rules`

How chosen apps' windows open and look: floating, size, workspace, opacity and more

页面状态：**已实现**；条目：2；已实现 2 / 未实现 0 / 不适用 0。

原因：Writes window rules to the Settings-owned desktop configuration; Hyprland checks each rule first.

`hl.window_rule` 规则（应用类名精确匹配、标题包含文本；浮动、居中、尺寸、工作区、所有工作区显示、最大化/全屏、不抢焦点、不透明度、无模糊、无阴影、保持比例、防止息屏）写入 Settings 自有的 `desktop.lua`；写入前以禁用状态交给 Hyprland 校验，重载后检查 `hyprctl configerrors`。替代原三个窗口规则预览页。

#### Window rules

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Your window rules | `window-rules.set` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |
| Remove a window rule | `window-rules.remove` | 操作 | 已实现 | 见下文“Window rules, environment variables and printers (2026-11-12)” |

## 账户

个人信息与登录

### Account information — `your-info`

头像与身份信息

页面状态：**未实现**；条目：4；已实现 2 / 未实现 2 / 不适用 0。

原因：用户名和 Settings 自有头像已实现；账户管理与登录仍为禁用预览。

Windows 参考入口：`ms-settings:yourinfo`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Username | `your-info.a1aaf352` | 信息展示 | 已实现 | `test/account_test.dart`；Rust account 裁剪/持久化/失败保留测试；CLI/D-Bus 契约 |
| Change avatar | `your-info.58484bbb` | 操作 | 已实现 | `test/account_test.dart`：双向滚轮、双指缩放、滑杆同步、拖动、1–8× 边界与取消、缩放后实际栅格绘制不越界；Rust 裁剪/原图不变/原子保存失败保留；CLI/D-Bus 契约 |
| Manage Account | `your-info.7e0e3d0b` | 操作 | 未实现 | — |
| Login options | `your-info.398b2d99` | 操作 | 未实现 | — |

### Sign-in options — `signin`

验证方式、自动锁定与登录要求

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions`。

相关页面 ID：`dynamic-lock`、`hello-face`、`hello-fingerprint`、`security-key`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Facial recognition | `signin.090cb65e` | 操作 | 未实现 | — |
| Fingerprint recognition | `signin.e3ce550b` | 操作 | 未实现 | — |
| PIN | `signin.3adadd31` | 操作 | 未实现 | — |
| Security Key | `signin.86a2121e` | 操作 | 未实现 | — |
| Password | `signin.c839a8ff` | 操作 | 未实现 | — |
| Picture Password | `signin.82e24adb` | 操作 | 未实现 | — |
| Re-login requirement after leaving | `signin.572a16a1` | 选择 | 未实现 | — |
| Dynamic lock | `signin.ad39c1be` | 开关 | 未实现 | — |
| Complete setup using login information after update | `signin.3e47dee1` | 开关 | 未实现 | — |

### Dynamic lock — `dynamic-lock`

蓝牙离开自动锁定

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions-dynamiclock`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Automatically lock your device when you leave | `dynamic-lock.62b4ddbf` | 开关 | 未实现 | — |
| Pair your phone | `dynamic-lock.fd140857` | 操作 | 未实现 | — |
| Paired device | `dynamic-lock.222005b0` | 信息展示 | 未实现 | — |

### Facial recognition — `hello-face`

生物识别注册流程参考（参考 Windows Hello 设计）

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：仅为参考来源系统专属或旧版特性，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:signinoptions-launchfaceenrollment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Set up facial recognition | `hello-face.f9b4646d` | 操作 | 不适用 | — |
| Improve recognition | `hello-face.83f9098f` | 操作 | 不适用 | — |
| Remove facial recognition | `hello-face.df6cef60` | 操作 | 不适用 | — |

### Fingerprint recognition — `hello-fingerprint`

生物识别注册参考

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions-launchfingerprintenrollment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Add fingerprint | `hello-fingerprint.3e0d66e1` | 操作 | 未实现 | — |
| Add other fingers | `hello-fingerprint.b640fea8` | 操作 | 未实现 | — |
| Remove fingerprints | `hello-fingerprint.e8f4c9a5` | 操作 | 未实现 | — |

### Security Key — `security-key`

密钥注册、PIN 与重置

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:signinoptions-launchsecuritykeyenrollment`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Manage security keys | `security-key.2c16e903` | 操作 | 未实现 | — |
| Set key PIN | `security-key.ef14bdad` | 操作 | 未实现 | — |
| Reset security keys | `security-key.9d94adb9` | 操作 | 未实现 | — |

### System backup — `backup`

应用、偏好与同步参考

页面状态：**未实现**；条目：20；已实现 0 / 未实现 20 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:sync`、`ms-settings:backup`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Remember My App | `backup.cecf4caf` | 开关 | 未实现 | — |
| Remember my preferences | `backup.66503cb5` | 开关 | 未实现 | — |
| Accessibility Preferences | `backup.d018d14b` | 开关 | 未实现 | — |
| Accounts and Wi-Fi Networks | `backup.af22a256` | 开关 | 未实现 | — |
| Personalized preferences | `backup.bcd1955e` | 开关 | 未实现 | — |
| Language preference | `backup.5d5065a9` | 开关 | 未实现 | — |
| Other system settings | `backup.3f79292e` | 开关 | 未实现 | — |
| Manage synced content | `backup.1b959d02` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Remember my apps | `backup.reference.04edcf6f` | 开关 | 未实现 | — |
| Accessibility | `backup.reference.52e80604` | 开关 | 未实现 | — |
| Accounts, WiFi networks and passwords | `backup.reference.33a8643d` | 开关 | 未实现 | — |
| Personalization | `backup.reference.60ff3096` | 开关 | 未实现 | — |
| Language preferences and dictionary | `backup.reference.b695b07e` | 开关 | 未实现 | — |
| Other Windows settings | `backup.reference.802b32da` | 开关 | 未实现 | — |

#### Advanced: compositor previews

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Configuration backup: Backup file range | `backup.configuration-scope` | 文本输入 | 未实现 | — |
| Configuration backup: Create a configuration backup | `backup.configuration-create` | 操作 | 未实现 | — |
| Configuration backup: Restore backup | `backup.configuration-restore` | 操作 | 未实现 | — |
| Configuration backup: Import configuration archive | `backup.configuration-import` | 操作 | 未实现 | — |
| Configuration backup: Export configuration archive | `backup.configuration-export` | 操作 | 未实现 | — |
| Configuration backup: View differences before restoring | `backup.configuration-preview` | 操作 | 未实现 | — |

### Kiosk — `kiosk`

专用会话与单应用限制

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:assignedaccess`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Start setup | `kiosk.279497bb` | 操作 | 未实现 | — |
| Session name | `kiosk.864aff36` | 文本输入 | 未实现 | — |
| Select application | `kiosk.9ec480c1` | 操作 | 未实现 | — |

### Passkeys — `passkeys`

设备上的凭据与提供程序

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

相关页面 ID：`passkeys-advanced`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Search for a pass key | `passkeys.8fbaa646` | 文本输入 | 未实现 | — |
| Saved pass keys | `passkeys.6e953913` | 信息展示 | 未实现 | — |
| Delete the passkey | `passkeys.53d248e4` | 操作 | 未实现 | — |
| Advanced passkey options | `passkeys.93d889c1` | 操作 | 未实现 | — |

### Passkey advanced options — `passkeys-advanced`

本地保存与第三方密钥服务

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Save the passkey on this device | `passkeys-advanced.71fe6bdc` | 开关 | 未实现 | — |
| Third-party pass key providers | `passkeys-advanced.973ee8b8` | 开关 | 未实现 | — |
| Configure Key Service | `passkeys-advanced.786de3b4` | 操作 | 未实现 | — |

### Cloud storage — `cloud-storage`

首页云存储卡片参考（受现代桌面系统常见云存储卡片启发）

页面状态：**不适用**；条目：3；已实现 0 / 未实现 0 / 不适用 3。

原因：仅为参考来源系统专属或旧版特性，尚无 Hyprland 对应实现。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Cloud storage usage | `cloud-storage.718afb24` | 信息展示 | 不适用 | — |
| Manage cloud storage | `cloud-storage.1cc744fa` | 操作 | 不适用 | — |
| Upgrade cloud storage | `cloud-storage.9d773e3a` | 操作 | 不适用 | — |

<a id="category-time"></a>

## 时间和语言

日期、地区与输入语言

### Date and time — `date-time`

时间同步与时区；区域格式由 Language and Region 页负责

页面状态：**未实现**；条目：6；已实现 5 / 未实现 1 / 不适用 0。

原因：自动时区检测仍为预览；其他选项通过系统服务读取和修改。

Windows 参考入口：`ms-settings:dateandtime`。

#### Time synchronization

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Automatically set time | `date-time.db451de3` | 开关 | 已实现 | Rust D-Bus regression tests; date_time_test.dart; interface_smoke.py; resident Rust service and private-pipe authorization. |
| Time server | `date-time.7e33a213` | 文本输入 | 已实现 | Rust D-Bus regression tests; date_time_test.dart; interface_smoke.py; resident Rust service and private-pipe authorization. |
| Sync now | `date-time.098d06ec` | 操作 | 已实现 | Rust D-Bus regression tests; date_time_test.dart; interface_smoke.py; resident Rust service and private-pipe authorization. |
| Set date and time manually | `date-time.6422d209` | 操作 | 已实现 | Rust D-Bus regression tests; date_time_test.dart; interface_smoke.py; resident Rust service and private-pipe authorization. |

#### Time zone

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Time zone | `date-time.fb2a23dc` | 选择 | 已实现 | Rust D-Bus regression tests; date_time_test.dart; interface_smoke.py; resident Rust service and private-pipe authorization. |
| Automatically set time zone | `date-time.2af5dabe` | 开关 | 未实现 | — |

### Language and Region — `language`

显示语言、区域格式与键盘布局

页面状态：**已实现**；条目：4；已实现 4 / 未实现 0 / 不适用 0。

原因：Uses systemd-localed for the language and formats, and Hyprland input options for keyboard layouts.

Windows 参考入口：`ms-settings:regionlanguage`、`ms-settings:regionformatting`。

显示语言写入 localed `LANG`，区域格式一次写入 `LC_TIME`、`LC_NUMERIC`、`LC_MONETARY`、`LC_PAPER`、`LC_MEASUREMENT`（与显示语言相同时由 localed 去除），仅列出已生成的 locale；新程序在重新登录后使用。区域格式卡片以真实 locale 预览日期、时间、数字、货币、单位与纸张。键盘布局按顺序写入 Settings 自有 `input.lua` 的同一 `hl.config` 调用（`kb_layout` 与 `kb_variant`），切换快捷键只替换 `kb_options` 中的 `grp:` 项。旧的首选语言、国家或地区、语言选项预览，以及 `kb_file`、`kb_model`、`kb_rules` 预览已移除；Date and time 页的 `date-time.format` 合并到区域格式。见[公开接口](public-api.md#language-and-region)。

#### Language

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Display language | `language.display` | 选择 | 已实现 | Rust language tests (fake localed: first-use adoption, conflicts and both resolutions, failure and readback retention, privileged allow-list) and localed SetLocale on an isolated D-Bus; real-locale preview tests; test/language_page_test.dart; read-only CLI/D-Bus Get against the installed locales. Real localed write and sign-in not exercised. |

#### Region

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Regional format | `language.format` | 选择 | 已实现 | Rust language tests (fake localed: first-use adoption, conflicts and both resolutions, failure and readback retention, privileged allow-list) and localed SetLocale on an isolated D-Bus; real-locale preview tests; test/language_page_test.dart; read-only CLI/D-Bus Get against the installed locales. Real localed write and sign-in not exercised. |

#### Keyboard

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Keyboard layouts | `language.keyboard-layouts` | 操作 | 已实现 | Rust input and xkb tests (validation against evdev.lst, kb_layout and kb_variant written together, readback, reload); probed on a nested Hyprland 0.57 (single hl.config call applies both; an invalid pair falls back to us); test/language_page_test.dart. |
| Switch layouts with | `language.keyboard-options` | 选择 | 已实现 | Rust input and xkb tests (validation against evdev.lst, kb_layout and kb_variant written together, readback, reload); probed on a nested Hyprland 0.57 (single hl.config call applies both; an invalid pair falls back to us); test/language_page_test.dart. |

### More — `time-more`

打开实际已安装的输入法配置工具；不接管或修改外部输入法配置。未安装的入口自动隐藏。

页面状态：**已实现**；条目：2；已实现 2 / 未实现 0 / 不适用 0。

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Fcitx 5 Configuration | `time-more.fcitx5` | 操作 | 已实现 | Rust 检测测试、CLI/D-Bus 检查与实机启动验证 |
| IBus Preferences | `time-more.ibus` | 操作 | 已实现 | Rust 检测测试、CLI/D-Bus 检查与实机启动验证 |

### Speech — `speech`

识别语言、声音与麦克风

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:speech`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Phonetic language | `speech.48cd0efa` | 选择 | 未实现 | — |
| Identify non-native accents | `speech.2ef677a1` | 开关 | 未实现 | — |
| Voice | `speech.7a73e125` | 选择 | 未实现 | — |
| Speaking speed | `speech.74737477` | 滑块 | 未实现 | — |
| Preview sounds | `speech.3e0d83e2` | 操作 | 未实现 | — |
| Add voice | `speech.c47063f5` | 操作 | 未实现 | — |
| Set up the microphone | `speech.56f17992` | 操作 | 未实现 | — |

<a id="category-accessibility"></a>

## 辅助功能

视觉、听觉与交互

### Text size — `text-size`

Make text larger in GTK and Flutter apps

页面状态：**已实现**；条目：1；已实现 1 / 未实现 0 / 不适用 0。

原因：Uses the GNOME interface text-scaling-factor through the Settings service.

Windows 参考入口：`ms-settings:easeofaccess-display`。

文字大小写入 GNOME 接口设置 `org.gnome.desktop.interface text-scaling-factor`（0.5–3.0；页面滑块 50%–300%，步进 5%），松开滑块即应用并回读；GTK 3/4 与 Flutter 应用跟随该键，Qt/KDE 等其他工具包不更改。Settings 副本保存在 `text-size.toml`，按系统配置同步规则处理首次采用与冲突。原“Apply text size”操作与 Windows 参考细项已删除。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Text size | `text-size.scale` | 滑块 | 已实现 | 见下文“Text size (2026-11-09)” |

### Visual effects — `visual-effects`

动画、透明度与通知时长

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-visualeffects`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Always show scrollbars | `visual-effects.fe13858e` | 开关 | 未实现 | — |
| Notification display duration | `visual-effects.db944e6b` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Always show scrollbars | `visual-effects.reference.22476e4b` | 开关 | 未实现 | — |
| Dismiss notifications after preferred amount of time | `visual-effects.reference.5b6b06b4` | 选择 | 未实现 | — |

### Magnifier — `magnifier`

缩放、视图与跟随行为

页面状态：**未实现**；条目：30；已实现 0 / 未实现 30 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-magnifier`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Magnifying glass | `magnifier.0398d9d8` | 开关 | 未实现 | — |
| Start before login | `magnifier.21f929d8` | 开关 | 未实现 | — |
| Start after login | `magnifier.c42bf921` | 开关 | 未实现 | — |
| Zoom level | `magnifier.618e6091` | 滑块 | 未实现 | — |
| Zoom increment | `magnifier.b9f2d9f8` | 选择 | 未实现 | — |
| View | `magnifier.cebbb470` | 选择 | 未实现 | — |
| Follow the mouse pointer | `magnifier.b5377eb2` | 开关 | 未实现 | — |
| Follow keyboard focus | `magnifier.e54d3c2b` | 开关 | 未实现 | — |
| Follow text cursor | `magnifier.5cffca3c` | 开关 | 未实现 | — |
| Follow Narrator cursor | `magnifier.7fea4dd7` | 开关 | 未实现 | — |
| Lens width | `magnifier.eb3a7a29` | 滑块 | 未实现 | — |
| Lens height | `magnifier.2750621a` | 滑块 | 未实现 | — |
| Reverse color | `magnifier.f7ddef87` | 开关 | 未实现 | — |
| Smooth images and text | `magnifier.edc4f6f3` | 开关 | 未实现 | — |
| Read aloud shortcut keys | `magnifier.af7b8808` | 文本输入 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Start Magnifier before sign-in | `magnifier.reference.54348147` | 开关 | 未实现 | — |
| Start Magnifier after sign-in | `magnifier.reference.0a370c37` | 开关 | 未实现 | — |
| Zoom level | `magnifier.reference.05c8bf1b` | 滑块 | 未实现 | — |
| Zoom increment | `magnifier.reference.027b1d5b` | 滑块 | 未实现 | — |
| View preference | `magnifier.reference.f46dfa93` | 选择 | 未实现 | — |
| Mouse pointer | `magnifier.reference.353f0bce` | 开关 | 未实现 | — |
| Keyboard focus | `magnifier.reference.3b4676ec` | 开关 | 未实现 | — |
| Text cursor | `magnifier.reference.709e0120` | 开关 | 未实现 | — |
| Narrator cursor | `magnifier.reference.38c4b18b` | 开关 | 未实现 | — |
| Height / Width sliders | `magnifier.reference.7dec5770` | 滑块 | 未实现 | — |
| Keep the mouse pointer location (when selected Full Screen View) | `magnifier.reference.16d01cce` | 开关 | 未实现 | — |
| Keep the text cursor location (when selected Full Screen View) | `magnifier.reference.3b25fbba` | 开关 | 未实现 | — |
| Invert Colors | `magnifier.reference.54f55938` | 选择 | 未实现 | — |
| Smooth edges of images and text | `magnifier.reference.16440b75` | 开关 | 未实现 | — |
| Reading shortcut | `magnifier.reference.164500de` | 选择 | 未实现 | — |

### Color filters — `color-filters`

色觉辅助与快捷键

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-colorfilter`、`ms-settings:easeofaccess-colorfilter-adaptivecolorlink`、`ms-settings:easeofaccess-colorfilter-bluelightlink`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Color filter | `color-filters.e71f8ff5` | 开关 | 未实现 | — |
| Filter | `color-filters.1242069d` | 选择 | 未实现 | — |
| Filter keyboard shortcuts | `color-filters.c95fb3d5` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Color filters | `color-filters.reference.93c3c16a` | 选择 | 未实现 | — |
| Preferred color filter selection | `color-filters.reference.d1a1684b` | 选择 | 未实现 | — |
| Keyboard shortcut for color filters | `color-filters.reference.3a55c85c` | 选择 | 未实现 | — |

### Contrast themes — `contrast`

高对比度主题和自定义色彩

页面状态：**未实现**；条目：16；已实现 0 / 未实现 16 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-highcontrast`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Topic | `contrast.e848ddd4` | 选择 | 未实现 | — |
| Background color | `contrast.4a2d8a28` | 颜色 | 未实现 | — |
| Text color | `contrast.07f568da` | 颜色 | 未实现 | — |
| Hyperlink color | `contrast.58aecbd7` | 颜色 | 未实现 | — |
| Disable text color | `contrast.9d947f02` | 颜色 | 未实现 | — |
| Select text color | `contrast.450ad5bc` | 颜色 | 未实现 | — |
| Button text color | `contrast.e0124b6b` | 颜色 | 未实现 | — |
| Apply a contrast theme | `contrast.88185761` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Contrast Themes | `contrast.reference.08c75109` | 选择 | 未实现 | — |
| Choose a theme | `contrast.reference.2f32f7fc` | 选择 | 未实现 | — |
| Text | `contrast.reference.4ef5eef9` | 开关 | 未实现 | — |
| Hyperlinks | `contrast.reference.01e89338` | 开关 | 未实现 | — |
| Disabled Text | `contrast.reference.15794103` | 开关 | 未实现 | — |
| Selected Text | `contrast.reference.d200a697` | 开关 | 未实现 | — |
| Button Text | `contrast.reference.ea31e5bf` | 开关 | 未实现 | — |
| Background | `contrast.reference.3fb30d73` | 开关 | 未实现 | — |

### Narrator — `narrator`

语音、详细程度与光标

页面状态：**未实现**；条目：65；已实现 0 / 未实现 65 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-narrator`、`ms-settings:easeofaccess-narrator-isautostartenabled`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Narrator | `narrator.7de905aa` | 开关 | 未实现 | — |
| Start before login | `narrator.21f929d8` | 开关 | 未实现 | — |
| Start after login | `narrator.c42bf921` | 开关 | 未实现 | — |
| Keyboard shortcuts | `narrator.021cf99c` | 开关 | 未实现 | — |
| Show home page on startup | `narrator.711fb05d` | 开关 | 未实现 | — |
| Sound | `narrator.ab9ff81d` | 选择 | 未实现 | — |
| Speaking speed | `narrator.74737477` | 滑块 | 未实现 | — |
| Tone | `narrator.bf36f9d8` | 滑块 | 未实现 | — |
| Volume | `narrator.1aa999a5` | 滑块 | 未实现 | — |
| Reduce the volume of other applications when reading aloud | `narrator.ec0a8ee8` | 开关 | 未实现 | — |
| Level of detail | `narrator.cf87e928` | 选择 | 未实现 | — |
| Changes in reading format | `narrator.40c0b763` | 开关 | 未实现 | — |
| Use phonetic spelling when reading by character | `narrator.51f65979` | 开关 | 未实现 | — |
| Pause at punctuation points | `narrator.d84ce611` | 开关 | 未实现 | — |
| Read the help of advanced controls aloud | `narrator.492635a8` | 开关 | 未实现 | — |
| How to read uppercase text aloud | `narrator.eaf16e86` | 选择 | 未实现 | — |
| Control context level | `narrator.39056697` | 选择 | 未实现 | — |
| Read interactive prompts aloud | `narrator.94e0cadb` | 开关 | 未实现 | — |
| Explanation of unexecutable operations | `narrator.b5086345` | 开关 | 未实现 | — |
| Sound replaces commonly used broadcasts | `narrator.fd4018ae` | 开关 | 未实现 | — |
| Read control details aloud | `narrator.aa9912c5` | 开关 | 未实现 | — |
| Read the input characters aloud | `narrator.2db63053` | 开关 | 未实现 | — |
| Read the input words aloud | `narrator.73386aca` | 开关 | 未实现 | — |
| Read function keys aloud | `narrator.eea5ecd2` | 开关 | 未实现 | — |
| Read the navigation keys aloud | `narrator.d5d97fcb` | 开关 | 未实现 | — |
| Speak the lock key | `narrator.6d524a17` | 开关 | 未实现 | — |
| Speak modifier keys aloud | `narrator.e9b26889` | 开关 | 未实现 | — |
| Narrator key | `narrator.d43e692e` | 选择 | 未实现 | — |
| Activate touch keys when raising your hand | `narrator.15a20ebd` | 开关 | 未实现 | — |
| Mouse reading screen | `narrator.94935b9e` | 开关 | 未实现 | — |
| Cursor follows mouse | `narrator.d26dc234` | 开关 | 未实现 | — |
| Show Narrator cursor | `narrator.ec048ee8` | 开关 | 未实现 | — |
| Synchronize text cursor | `narrator.e1afa623` | 开关 | 未实现 | — |
| Synchronize system focus | `narrator.46d9f44c` | 开关 | 未实现 | — |
| Narrator extension | `narrator.7f4b6188` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Start Narrator before sign-in | `narrator.reference.eda89fb6` | 开关 | 未实现 | — |
| Start Narrator after sign-in | `narrator.reference.385fc6f8` | 开关 | 未实现 | — |
| Keyboard shortcut for Narrator | `narrator.reference.257eaf83` | 选择 | 未实现 | — |
| Show Narrator Home when Narrator starts | `narrator.reference.5d68306a` | 开关 | 未实现 | — |
| Speed | `narrator.reference.292ae141` | 滑块 | 未实现 | — |
| Pitch | `narrator.reference.10c29e0c` | 滑块 | 未实现 | — |
| Volume | `narrator.reference.36f3b8e5` | 滑块 | 未实现 | — |
| Lower the volume of other apps when Narrator is speaking | `narrator.reference.05dc20b9` | 滑块 | 未实现 | — |
| Emphasize formatted text | `narrator.reference.db00112d` | 选择 | 未实现 | — |
| Read phonetically when reading by character | `narrator.reference.8b69d44f` | 开关 | 未实现 | — |
| Pause slightly when reading punctuation | `narrator.reference.104339a2` | 开关 | 未实现 | — |
| Read advanced details like help text on buttons and other controls | `narrator.reference.57fc18dc` | 开关 | 未实现 | — |
| Change how capitalized text is read | `narrator.reference.4f442eb5` | 开关 | 未实现 | — |
| Read hints on how to interact with buttons and other controls | `narrator.reference.cbb531ac` | 开关 | 未实现 | — |
| Tell me why actions can't be performed | `narrator.reference.29167366` | 开关 | 未实现 | — |
| Play sounds instead of announcements for common actions | `narrator.reference.a3b181a7` | 开关 | 未实现 | — |
| Tell me details about buttons and other controls | `narrator.reference.203122a4` | 开关 | 未实现 | — |
| Letters, numbers, and punctuation | `narrator.reference.4af62bdf` | 开关 | 未实现 | — |
| Words | `narrator.reference.90a5b7a3` | 开关 | 未实现 | — |
| Function keys | `narrator.reference.d8b45f58` | 开关 | 未实现 | — |
| Arrow, Tab, and other navigation keys | `narrator.reference.912b4b1e` | 开关 | 未实现 | — |
| Toggle keys, like Caps lock and Num lock | `narrator.reference.7c37961a` | 开关 | 未实现 | — |
| Shift, Alt, and other modifier keys | `narrator.reference.4c9af18e` | 开关 | 未实现 | — |
| Narrator key | `narrator.reference.d4ef110b` | 选择 | 未实现 | — |
| On touch keyboards, activate keys when I lift my finger | `narrator.reference.e8183e12` | 开关 | 未实现 | — |
| Have the Narrator cursor follow my mouse | `narrator.reference.27190ac0` | 开关 | 未实现 | — |
| Show the Narrator cursor | `narrator.reference.e91a6959` | 开关 | 未实现 | — |
| Move my text cursor with the Narrator cursor as Narrator reads text | `narrator.reference.bf4148da` | 开关 | 未实现 | — |
| Sync the Narrator cursor and system focus | `narrator.reference.e90861de` | 开关 | 未实现 | — |
| Enable Narrator Extensions | `narrator.reference.14f46908` | 开关 | 未实现 | — |

### Audio assistance — `accessibility-audio`

单声道与声音视觉提示

页面状态：**未实现**；条目：4；已实现 0 / 未实现 4 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-audio`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mono audio | `accessibility-audio.1a90a9eb` | 开关 | 未实现 | — |
| Audio notification flashing | `accessibility-audio.49a25e92` | 选择 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mono Audio | `accessibility-audio.reference.0d993fdd` | 开关 | 未实现 | — |
| Flash my screen during audio notifications | `accessibility-audio.reference.380697ec` | 开关 | 未实现 | — |

### Captions — `captions`

实时字幕、位置与外观

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-closedcaptioning`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Live subtitles | `captions.ac8a8db0` | 开关 | 未实现 | — |
| Filter indecent content | `captions.ddbbae5a` | 开关 | 未实现 | — |
| Subtitle position | `captions.d31e8823` | 选择 | 未实现 | — |
| Subtitle style | `captions.41085f11` | 选择 | 未实现 | — |
| Edit subtitle style | `captions.9fe387bc` | 操作 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Filter Profanity | `captions.reference.b233720a` | 开关 | 未实现 | — |
| Position | `captions.reference.07051098` | 选择 | 未实现 | — |
| Caption Style | `captions.reference.0472a68c` | 选择 | 未实现 | — |

### Keyboard assistance — `accessibility-keyboard`

粘滞键、筛选键与屏幕键盘

页面状态：**未实现**；条目：46；已实现 0 / 未实现 46 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-keyboard`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Sticky Keys | `accessibility-keyboard.68b234ce` | 开关 | 未实现 | — |
| Sticky Keys Shortcuts | `accessibility-keyboard.841c4322` | 开关 | 未实现 | — |
| Show sticky keys icon | `accessibility-keyboard.715c940f` | 开关 | 未实现 | — |
| Press the lock modifier key twice in succession | `accessibility-keyboard.fb47ad4a` | 开关 | 未实现 | — |
| Close when two keys are pressed simultaneously | `accessibility-keyboard.14c24f2f` | 开关 | 未实现 | — |
| Play a sound when a shortcut key is pressed and released | `accessibility-keyboard.97f39b35` | 开关 | 未实现 | — |

#### 筛选键

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Filter keys | `accessibility-keyboard.97ddab93` | 开关 | 未实现 | — |
| Filter key shortcuts | `accessibility-keyboard.92ad3aa0` | 开关 | 未实现 | — |
| Show filter key icon | `accessibility-keyboard.5d234460` | 开关 | 未实现 | — |
| Prompt sound when pressing the key | `accessibility-keyboard.5b712c8f` | 开关 | 未实现 | — |
| Ignore fast keystrokes | `accessibility-keyboard.643a1e0a` | 开关 | 未实现 | — |
| Wait before accepting keystrokes | `accessibility-keyboard.1ce6181f` | 选择 | 未实现 | — |
| Ignore accidental repeated keystrokes | `accessibility-keyboard.d556de2d` | 开关 | 未实现 | — |
| Wait for repeated keystrokes | `accessibility-keyboard.bc491238` | 选择 | 未实现 | — |
| Ignore repeated keystrokes | `accessibility-keyboard.a272bfd3` | 开关 | 未实现 | — |
| First repeat wait | `accessibility-keyboard.676ac6a7` | 选择 | 未实现 | — |
| Subsequent repeated waiting | `accessibility-keyboard.a0212e71` | 选择 | 未实现 | — |

#### 其他

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Switch key | `accessibility-keyboard.9667278b` | 开关 | 未实现 | — |
| Auxiliary key notification | `accessibility-keyboard.84b1c363` | 开关 | 未实现 | — |
| Play sound when switching auxiliary keys on and off | `accessibility-keyboard.0c6593c1` | 开关 | 未实现 | — |
| Underline access keys | `accessibility-keyboard.791e84ff` | 开关 | 未实现 | — |
| Print Screen opens the screenshot | `accessibility-keyboard.cc8561a8` | 开关 | 未实现 | — |
| On-screen keyboard | `accessibility-keyboard.8654a9c6` | 开关 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Keyboard shortcut for Sticky keys | `accessibility-keyboard.reference.1766f98b` | 选择 | 未实现 | — |
| Show the sticky keys icon on the taskbar | `accessibility-keyboard.reference.cb1dbaf2` | 开关 | 未实现 | — |
| Lock shortcut keys when pressed twice in a row | `accessibility-keyboard.reference.c06b6443` | 选择 | 未实现 | — |
| Play a sound when shortcut keys are pressed and released | `accessibility-keyboard.reference.59e11b79` | 选择 | 未实现 | — |
| Filter keys (main toggle) | `accessibility-keyboard.reference.8fdb2ef9` | 开关 | 未实现 | — |
| Keyboard shortcut for Filter keys | `accessibility-keyboard.reference.61d353a2` | 选择 | 未实现 | — |
| Show the Filter keys icon on the taskbar | `accessibility-keyboard.reference.e15cf0d4` | 开关 | 未实现 | — |
| Beep when keys are pressed | `accessibility-keyboard.reference.78978487` | 开关 | 未实现 | — |
| Wait before accepting a keystroke | `accessibility-keyboard.reference.4440fbf5` | 开关 | 未实现 | — |
| Wait before accepting repeated keystrokes | `accessibility-keyboard.reference.bf8c6dd7` | 开关 | 未实现 | — |
| Wait before accepting the first repeated keystroke | `accessibility-keyboard.reference.28c292fb` | 开关 | 未实现 | — |
| Wait before accepting subsequent repeated keystrokes | `accessibility-keyboard.reference.bb32e872` | 开关 | 未实现 | — |
| Toggle keys | `accessibility-keyboard.reference.dd8bff2c` | 开关 | 未实现 | — |
| Notify me when I turn on Sticky, Filter, or Toggle keys from the keyboard | `accessibility-keyboard.reference.fa916f67` | 开关 | 未实现 | — |
| Play a sound when I turn Sticky, Filter, or Toggle keys on or off from the keyboard | `accessibility-keyboard.reference.8754adfd` | 开关 | 未实现 | — |
| Underline acess keys | `accessibility-keyboard.reference.4a5a5e4c` | 开关 | 未实现 | — |
| Use the print screen to open screen capture | `accessibility-keyboard.reference.6f3d637b` | 开关 | 未实现 | — |

#### Advanced: compositor previews

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Keyboard: Enable Num Lock by default (numlock_by_default) | `accessibility-keyboard.compositor-numlock-by-default` | 开关 | 未实现 | — |
| Keyboard: Key repeat delay (repeat_delay) | `accessibility-keyboard.compositor-repeat-delay` | 滑块 | 未实现 | — |
| Keyboard: Key repetition frequency (repeat_rate) | `accessibility-keyboard.compositor-repeat-rate` | 滑块 | 未实现 | — |
| Keyboard: Resolve shortcut keys according to the current layout (resolve_binds_by_sym) | `accessibility-keyboard.compositor-resolve-binds-by-sym` | 开关 | 未实现 | — |
| Virtual keyboard: release pressed on close (release_pressed_on_close) | `accessibility-keyboard.virtual-release-pressed-on-close` | 开关 | 未实现 | — |
| Virtual keyboard: share states (share_states) | `accessibility-keyboard.virtual-share-states` | 滑块 | 未实现 | — |

### Mouse keys — `mouse-keys`

使用数字键盘移动指针

页面状态：**未实现**；条目：12；已实现 0 / 未实现 12 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:easeofaccess-mouse`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mouse keys | `mouse-keys.af8ff2e3` | 开关 | 未实现 | — |
| Only used when Num Lock is on | `mouse-keys.2625b861` | 开关 | 未实现 | — |
| Show mouse button icon | `mouse-keys.21f5aea4` | 开关 | 未实现 | — |
| Ctrl accelerates and Shift decelerates | `mouse-keys.28c033e9` | 开关 | 未实现 | — |
| Mouse key speed | `mouse-keys.7754307e` | 滑块 | 未实现 | — |
| Mouse key acceleration | `mouse-keys.06700d63` | 滑块 | 未实现 | — |

#### Windows 参考细项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Mouse keys | `mouse-keys.reference.da0c9570` | 开关 | 未实现 | — |
| Only use mouse keys when Num lock is on | `mouse-keys.reference.bdf1cbf2` | 开关 | 未实现 | — |
| Show the mouse keys icon on the taskbar | `mouse-keys.reference.f113b78d` | 开关 | 未实现 | — |
| Hold the Ctrl key to speed up and the Shift key to slow down | `mouse-keys.reference.4f1675d1` | 滑块 | 未实现 | — |
| Mouse keys speed | `mouse-keys.reference.fe021cfe` | 滑块 | 未实现 | — |
| Mouse keys acceleration | `mouse-keys.reference.df0cfb8c` | 滑块 | 未实现 | — |

<a id="category-privacy"></a>

## 隐私和安全性

设备安全与应用权限

### Device encryption — `encryption`

设备加密与恢复密钥

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:deviceencryption`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Device encryption | `encryption.47011073` | 开关 | 未实现 | — |
| Back up the recovery key | `encryption.850ab6af` | 操作 | 未实现 | — |
| Encryption status | `encryption.45dd31ac` | 信息展示 | 未实现 | — |

### Find my device — `find-device`

设备位置与远程查找参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：仅为参考来源系统专属或旧版特性，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:findmydevice`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Find my device | `find-device.9436d046` | 开关 | 不适用 | — |
| View associated devices | `find-device.a33ef3cc` | 操作 | 不适用 | — |

### Online speech recognition — `online-speech`

云端语音处理参考

页面状态：**不适用**；条目：2；已实现 0 / 未实现 0 / 不适用 2。

原因：仅为参考来源系统专属或旧版特性，尚无 Hyprland 对应实现。

Windows 参考入口：`ms-settings:privacy-speech`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Online speech recognition | `online-speech.0a66701f` | 开关 | 不适用 | — |
| Manage voice data in the cloud | `online-speech.20caf0a6` | 操作 | 不适用 | — |

### Search and indexing — `search-index`

索引范围、排除目录与诊断

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；这里只展示界面，不会读取或更改系统设置。

Windows 参考入口：`ms-settings:search`、`ms-settings:search-moredetails`。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Find files | `search-index.acf33b0f` | 选择 | 未实现 | — |
| Respect power settings when indexing | `search-index.5fc76958` | 开关 | 未实现 | — |
| Add excluded folders | `search-index.cd42d36e` | 操作 | 未实现 | — |
| Advanced indexing options | `search-index.0690cd83` | 操作 | 未实现 | — |
| Index troubleshooting | `search-index.d4c992e9` | 操作 | 未实现 | — |
| Index status | `search-index.5a5afb60` | 信息展示 | 未实现 | — |

### Hyprland · Input capture boundaries — `hypr-input-capture`

合成器高级设置：input-capture · Hyprland

页面状态：**未实现**；条目：2；已实现 0 / 未实现 2 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 输入捕获边界

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| capture modifiers · capture_modifiers | `hypr-input-capture.capture-modifiers` | 开关 | 未实现 | — |
| enforce barriers · enforce_barriers | `hypr-input-capture.enforce-barriers` | 开关 | 未实现 | — |

### Compositor permission rules — `hypr-compositor-permissions`

截图、插件、键盘、光标位置与输入捕获 · Hyprland

页面状态：**未实现**；条目：6；已实现 0 / 未实现 6 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

相关页面 ID：`hypr-input-capture`。

参考资料：[hypr-permissions](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/advanced-configuration/permissions.md)。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Enable Hyprland permission checking | `hypr-compositor-permissions.enforce` | 开关 | 未实现 | — |
| Apply path or device matching expressions | `hypr-compositor-permissions.binary` | 文本输入 | 未实现 | — |
| Permission types | `hypr-compositor-permissions.type` | 选择 | 未实现 | — |
| Authorization strategy | `hypr-compositor-permissions.policy` | 选择 | 未实现 | — |
| Permission rules restart to take effect | `hypr-compositor-permissions.restart` | 信息展示 | 未实现 | — |
| Add new permission rules | `hypr-compositor-permissions.add` | 操作 | 未实现 | — |

## 系统更新

更新历史、维护与预览计划

### System updates — `updates`

仓库更新检查与升级、AUR 更新列表、会话级保留包与重试选项、在非活动时间运行的自动更新。

页面状态：**已实现**；条目：7；已实现 7 / 未实现 0 / 不适用 0。

原因：旧草稿通过 yay `--sudo` 桥接反向解析 pacman 参数，实机报 ` -> invalid option 'nosudoloop'` 后被暂停。重新设计后仓库升级只走固定 root 更新器（`upgrade [--include-held]`），由 `tool/install_system_updater.py` 安装的 polkit 规则免密授权；AUR 只列出不安装；常驻服务由 systemd 用户单元随会话启动并负责自动更新，自动更新在 Active hours 之外运行。

Windows 参考入口：`ms-settings:windowsupdate`、`ms-settings:windowsupdate-action`、`ms-settings:windowsupdate-seekerondemand`、`ms-settings:windowsupdate-options`。

#### Package updates

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Check for updates | `updates.check` | 操作 | 已实现 | updates crate 假后端异步检查、仓库/AUR 分组与保留标记测试；`test/updates_test.dart`；2026-11-04 本机安装版实际检查（17 个仓库更新，均正确标为保留） |
| Update now | `updates.upgrade` | 操作 | 已实现 | root 更新器参数白名单与 pacman 参数测试、pkexec 126/127 不重试测试；2026-11-04 本机安装版经 pkexec → systemd-run 实际执行 `pacman -Syu`，26 个保留包全部忽略，无可安装更新（nothing to do），状态 completed |
| Include held packages | `updates.include-held` | 开关 | 已实现 | up.fish 保留策略、NVIDIA 与全量模式测试；仅仓库包受影响测试 |
| Retry after failure | `updates.retry` | 开关 | 已实现 | 退避上限、关闭后停止、授权拒绝不重试测试 |
| Update status | `updates.status` | 信息展示 | 已实现 | 异步忙碌状态、错误保留及 `test/updates_test.dart` |
| Update output | `updates.output` | 信息展示 | 已实现 | 有界日志、ANSI/回车处理及 `test/updates_test.dart` |

| Automatic updates | `updates.automatic` | 开关 | 已实现 | 默认关闭、每个非活动时段一次、错过时段在活动时间补跑、活动时间内开启不视为错过、忙碌等待、更新器缺失提示测试；`test/updates_smoke.py` |

### Active hours — `active-hours`

自动更新等待的活动时段，保存在 `updates.json`；可跨午夜，开始与结束不能相同。不执行 Windows 重启行为。

页面状态：**已实现**；条目：2；已实现 2 / 未实现 0 / 不适用 0。

原因：Rust 常驻服务保存并按活动时段调度自动更新。Windows 的按活动自动调整（Adjust active hours）在 Linux 无对应数据来源，已移除。

Windows 参考入口：`ms-settings:windowsupdate-activehours`。

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Start time | `active-hours.e8868af6` | 文本输入 | 已实现 | HH:mm 校验、跨午夜窗口、开始结束相同拒绝、持久化测试；`test/updates_smoke.py`、`test/updates_test.dart` |
| End time | `active-hours.a0bb9f49` | 文本输入 | 已实现 | 同上；夏令时日期计算测试 |

<a id="category-hyprland"></a>

## 窗口与工作区

平铺布局、工作区、窗口组、规则与快捷键

### Hyprland · Window group behavior — `hypr-group`

合成器高级设置：group · Hyprland

页面状态：**未实现**；条目：14；已实现 0 / 未实现 14 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 窗口组行为

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| auto group · auto_group | `hypr-group.auto-group` | 开关 | 未实现 | — |
| drag into group · drag_into_group | `hypr-group.drag-into-group` | 滑块 | 未实现 | — |
| focus removed window · focus_removed_window | `hypr-group.focus-removed-window` | 开关 | 未实现 | — |
| group on movetoworkspace · group_on_movetoworkspace | `hypr-group.group-on-movetoworkspace` | 开关 | 未实现 | — |
| insert after current · insert_after_current | `hypr-group.insert-after-current` | 开关 | 未实现 | — |
| merge floated into tiled on groupbar · merge_floated_into_tiled_on_groupbar | `hypr-group.merge-floated-into-tiled-on-groupbar` | 开关 | 未实现 | — |
| merge groups on drag · merge_groups_on_drag | `hypr-group.merge-groups-on-drag` | 开关 | 未实现 | — |
| merge groups on groupbar · merge_groups_on_groupbar | `hypr-group.merge-groups-on-groupbar` | 开关 | 未实现 | — |

#### Group borders

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Active group border color | `hypr-group.border-active` | 文本输入 | 未实现 | — |
| Inactive group border color | `hypr-group.border-inactive` | 文本输入 | 未实现 | — |
| Active locked group border color | `hypr-group.border-locked-active` | 文本输入 | 未实现 | — |
| Inactive locked group border color | `hypr-group.border-locked-inactive` | 文本输入 | 未实现 | — |
| Border of windows that refuse groups | `hypr-group.nogroup-border` | 文本输入 | 未实现 | — |
| Active border of windows that refuse groups | `hypr-group.nogroup-border-active` | 文本输入 | 未实现 | — |

### Hyprland · Window group tab bar — `hypr-group-groupbar`

合成器高级设置：group.groupbar · Hyprland

页面状态：**未实现**；条目：35；已实现 0 / 未实现 35 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 窗口组标签栏

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| enabled · enabled | `hypr-group-groupbar.enabled` | 开关 | 未实现 | — |
| Layer background blur · blur | `hypr-group-groupbar.blur` | 开关 | 未实现 | — |
| disable when only · disable_when_only | `hypr-group-groupbar.disable-when-only` | 开关 | 未实现 | — |
| Font family · font_family | `hypr-group-groupbar.font-family` | 文本输入 | 未实现 | — |
| Font size · font_size | `hypr-group-groupbar.font-size` | 滑块 | 未实现 | — |
| font weight active · font_weight_active | `hypr-group-groupbar.font-weight-active` | 文本输入 | 未实现 | — |
| font weight inactive · font_weight_inactive | `hypr-group-groupbar.font-weight-inactive` | 文本输入 | 未实现 | — |
| Gaps within the window · gaps_in | `hypr-group-groupbar.gaps-in` | 滑块 | 未实现 | — |
| Screen margins · gaps_out | `hypr-group-groupbar.gaps-out` | 滑块 | 未实现 | — |
| gradients · gradients | `hypr-group-groupbar.gradients` | 开关 | 未实现 | — |
| gradient round only edges · gradient_round_only_edges | `hypr-group-groupbar.gradient-round-only-edges` | 开关 | 未实现 | — |
| gradient rounding · gradient_rounding | `hypr-group-groupbar.gradient-rounding` | 滑块 | 未实现 | — |
| gradient rounding power · gradient_rounding_power | `hypr-group-groupbar.gradient-rounding-power` | 滑块 | 未实现 | — |
| height · height | `hypr-group-groupbar.height` | 滑块 | 未实现 | — |
| indicator gap · indicator_gap | `hypr-group-groupbar.indicator-gap` | 滑块 | 未实现 | — |
| indicator height · indicator_height | `hypr-group-groupbar.indicator-height` | 滑块 | 未实现 | — |
| keep upper gap · keep_upper_gap | `hypr-group-groupbar.keep-upper-gap` | 开关 | 未实现 | — |
| middle click close · middle_click_close | `hypr-group-groupbar.middle-click-close` | 开关 | 未实现 | — |
| priority · priority | `hypr-group-groupbar.priority` | 滑块 | 未实现 | — |
| render titles · render_titles | `hypr-group-groupbar.render-titles` | 开关 | 未实现 | — |
| round only edges · round_only_edges | `hypr-group-groupbar.round-only-edges` | 开关 | 未实现 | — |
| Corner radius · rounding | `hypr-group-groupbar.rounding` | 滑块 | 未实现 | — |
| Rounding curvature · rounding_power | `hypr-group-groupbar.rounding-power` | 滑块 | 未实现 | — |
| scrolling · scrolling | `hypr-group-groupbar.scrolling` | 开关 | 未实现 | — |
| stacked · stacked | `hypr-group-groupbar.stacked` | 开关 | 未实现 | — |
| text color · text_color | `hypr-group-groupbar.text-color` | 颜色 | 未实现 | — |
| text color inactive · text_color_inactive | `hypr-group-groupbar.text-color-inactive` | 文本输入 | 未实现 | — |
| text color locked active · text_color_locked_active | `hypr-group-groupbar.text-color-locked-active` | 文本输入 | 未实现 | — |
| text color locked inactive · text_color_locked_inactive | `hypr-group-groupbar.text-color-locked-inactive` | 文本输入 | 未实现 | — |
| text offset · text_offset | `hypr-group-groupbar.text-offset` | 滑块 | 未实现 | — |
| text padding · text_padding | `hypr-group-groupbar.text-padding` | 滑块 | 未实现 | — |

#### Tab colors

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Active tab color | `hypr-group-groupbar.col-active` | 文本输入 | 未实现 | — |
| Inactive tab color | `hypr-group-groupbar.col-inactive` | 文本输入 | 未实现 | — |
| Active locked tab color | `hypr-group-groupbar.col-locked-active` | 文本输入 | 未实现 | — |
| Inactive locked tab color | `hypr-group-groupbar.col-locked-inactive` | 文本输入 | 未实现 | — |

### Hyprland · Layout global strategy — `hypr-layout`

合成器高级设置：layout · Hyprland

页面状态：**未实现**；条目：2；已实现 0 / 未实现 2 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 布局全局策略

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Single window aspect ratio · single_window_aspect_ratio | `hypr-layout.single-window-aspect-ratio` | 文本输入 | 未实现 | — |
| Single window aspect ratio tolerance · single_window_aspect_ratio_tolerance | `hypr-layout.single-window-aspect-ratio-tolerance` | 滑块 | 未实现 | — |

### Master layout — `hypr-layout-master`

布局参数与按工作区覆盖 · Hyprland

页面状态：**未实现**；条目：13；已实现 0 / 未实现 13 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-master](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/layouts/master-layout.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### master

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Allow smaller main area · allow_small_split | `hypr-layout-master.allow-small-split` | 开关 | 未实现 | — |
| Special workspace scaling · special_scale_factor | `hypr-layout-master.special-scale-factor` | 滑块 | 未实现 | — |
| Main area ratio · mfact | `hypr-layout-master.mfact` | 滑块 | 未实现 | — |
| New window master-slave strategy · new_status | `hypr-layout-master.new-status` | 文本输入 | 未实现 | — |
| New window on top · new_on_top | `hypr-layout-master.new-on-top` | 开关 | 未实现 | — |
| New window follows active window · new_on_active | `hypr-layout-master.new-on-active` | 文本输入 | 未实现 | — |
| Main area orientation · orientation | `hypr-layout-master.orientation` | 选择 | 未实现 | — |
| slave count for center master · slave_count_for_center_master | `hypr-layout-master.slave-count-for-center-master` | 滑块 | 未实现 | — |
| center master fallback · center_master_fallback | `hypr-layout-master.center-master-fallback` | 文本输入 | 未实现 | — |
| Smart window scaling · smart_resizing | `hypr-layout-master.smart-resizing` | 开关 | 未实现 | — |
| drop at cursor · drop_at_cursor | `hypr-layout-master.drop-at-cursor` | 开关 | 未实现 | — |
| Keep the main window position · always_keep_position | `hypr-layout-master.always-keep-position` | 开关 | 未实现 | — |
| Focus on the main window after closing the window · focus_master_on_close | `hypr-layout-master.focus-master-on-close` | 开关 | 未实现 | — |

### Master layout workspace parameters — `hypr-layout-master-workspace`

布局参数与按工作区覆盖 · Hyprland

页面状态：**未实现**；条目：1；已实现 0 / 未实现 1 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-master](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/layouts/master-layout.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 工作区覆盖

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| orientation = [o] · orientation = [o] | `hypr-layout-master-workspace.orientation-o` | 文本输入 | 未实现 | — |

### Scrolling layout — `hypr-layout-scrolling`

布局参数与按工作区覆盖 · Hyprland

页面状态：**未实现**；条目：9；已实现 0 / 未实现 9 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-scrolling](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/layouts/scrolling-layout.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### scrolling

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Single column full screen strategy · fullscreen_on_one_column | `hypr-layout-scrolling.fullscreen-on-one-column` | 开关 | 未实现 | — |
| Column width · column_width | `hypr-layout-scrolling.column-width` | 滑块 | 未实现 | — |
| Column focus adaptation method · focus_fit_method | `hypr-layout-scrolling.focus-fit-method` | 滑块 | 未实现 | — |
| follow focus · follow_focus | `hypr-layout-scrolling.follow-focus` | 开关 | 未实现 | — |
| follow min visible · follow_min_visible | `hypr-layout-scrolling.follow-min-visible` | 滑块 | 未实现 | — |
| explicit column widths · explicit_column_widths | `hypr-layout-scrolling.explicit-column-widths` | 文本输入 | 未实现 | — |
| wrap focus · wrap_focus | `hypr-layout-scrolling.wrap-focus` | 开关 | 未实现 | — |
| wrap swapcol · wrap_swapcol | `hypr-layout-scrolling.wrap-swapcol` | 开关 | 未实现 | — |
| Gesture direction · direction | `hypr-layout-scrolling.direction` | 文本输入 | 未实现 | — |

### Scrolling layout workspace parameters — `hypr-layout-scrolling-workspace`

布局参数与按工作区覆盖 · Hyprland

页面状态：**未实现**；条目：1；已实现 0 / 未实现 1 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-scrolling](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/layouts/scrolling-layout.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 工作区覆盖

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Gesture direction · direction | `hypr-layout-scrolling-workspace.direction` | 文本输入 | 未实现 | — |

### Layer rules · Matching conditions — `hypr-layer-rule-props`

按官方文档分类的组件参数 · Hyprland

页面状态：**未实现**；条目：1；已实现 0 / 未实现 1 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-layer-rules](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/rules/layer-rules.md)。

#### 匹配条件

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Layer namespace matching · namespace | `hypr-layer-rule-props.namespace` | 文本输入 | 未实现 | — |

### Layer rules · Layer effects — `hypr-layer-rule-effects`

按官方文档分类的组件参数 · Hyprland

页面状态：**未实现**；条目：10；已实现 0 / 未实现 10 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-layer-rules](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/rules/layer-rules.md)。

#### 图层效果

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Lock screen upper display mode · above_lock | `hypr-layer-rule-effects.above-lock` | 文本输入 | 未实现 | — |
| Animation style · animation | `hypr-layer-rule-effects.animation` | 文本输入 | 未实现 | — |
| Layer background blur · blur | `hypr-layer-rule-effects.blur` | 开关 | 未实现 | — |
| Blurred layer pop-ups · blur_popups | `hypr-layer-rule-effects.blur-popups` | 开关 | 未实现 | — |
| Darkening degree of surrounding area · dim_around | `hypr-layer-rule-effects.dim-around` | 开关 | 未实现 | — |
| Blur transparency threshold · ignore_alpha | `hypr-layer-rule-effects.ignore-alpha` | 滑块 | 未实现 | — |
| Disable animation · no_anim | `hypr-layer-rule-effects.no-anim` | 开关 | 未实现 | — |
| Disable screen share capture · no_screen_share | `hypr-layer-rule-effects.no-screen-share` | 开关 | 未实现 | — |
| Space reservation priority · order | `hypr-layer-rule-effects.order` | 文本输入 | 未实现 | — |
| Penetration effect · xray | `hypr-layer-rule-effects.xray` | 开关 | 未实现 | — |

### Monocle single window layout — `hypr-layout-monocle`

窗口轮换与布局全屏 · Hyprland

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-monocle](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/layouts/monocle-layout.md)。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Next window | `hypr-layout-monocle.next` | 操作 | 未实现 | — |
| Previous window | `hypr-layout-monocle.previous` | 操作 | 未实现 | — |
| A single window fills up the workspace | `hypr-layout-monocle.maximize` | 操作 | 未实现 | — |

<a id="category-session"></a>

## 会话与配置

Hyprland 会话、配置文件、启动与诊断

### Hyprland · Compositor behavior — `hypr-misc`

合成器高级设置：misc · Hyprland

页面状态：**未实现**；条目：20；已实现 0 / 未实现 20 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 合成器行为与启动外观

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| anr missed pings · anr_missed_pings | `hypr-misc.anr-missed-pings` | 滑块 | 未实现 | — |
| disable autoreload · disable_autoreload | `hypr-misc.disable-autoreload` | 开关 | 未实现 | — |
| disable hyprland guiutils check · disable_hyprland_guiutils_check | `hypr-misc.disable-hyprland-guiutils-check` | 开关 | 未实现 | — |
| disable scale notification · disable_scale_notification | `hypr-misc.disable-scale-notification` | 开关 | 未实现 | — |
| disable watchdog warning · disable_watchdog_warning | `hypr-misc.disable-watchdog-warning` | 开关 | 未实现 | — |
| disable xdg env checks · disable_xdg_env_checks | `hypr-misc.disable-xdg-env-checks` | 开关 | 未实现 | — |
| enable anr dialog · enable_anr_dialog | `hypr-misc.enable-anr-dialog` | 开关 | 未实现 | — |
| enable swallow · enable_swallow | `hypr-misc.enable-swallow` | 开关 | 未实现 | — |
| exit window retains fullscreen · exit_window_retains_fullscreen | `hypr-misc.exit-window-retains-fullscreen` | 滑块 | 未实现 | — |
| float force onscreen · float_force_onscreen | `hypr-misc.float-force-onscreen` | 滑块 | 未实现 | — |
| new float force onscreen · new_float_force_onscreen | `hypr-misc.new-float-force-onscreen` | 滑块 | 未实现 | — |
| Focus on application activation · focus_on_activate | `hypr-misc.focus-on-activate` | 开关 | 未实现 | — |
| initial workspace token timeout · initial_workspace_token_timeout | `hypr-misc.initial-workspace-token-timeout` | 滑块 | 未实现 | — |
| layers hog keyboard focus · layers_hog_keyboard_focus | `hypr-misc.layers-hog-keyboard-focus` | 开关 | 未实现 | — |
| name vk after proc · name_vk_after_proc | `hypr-misc.name-vk-after-proc` | 开关 | 未实现 | — |
| on focus under fullscreen · on_focus_under_fullscreen | `hypr-misc.on-focus-under-fullscreen` | 滑块 | 未实现 | — |
| screencopy force 8b · screencopy_force_8b | `hypr-misc.screencopy-force-8b` | 开关 | 未实现 | — |
| size limits tiled · size_limits_tiled | `hypr-misc.size-limits-tiled` | 开关 | 未实现 | — |
| swallow exception regex · swallow_exception_regex | `hypr-misc.swallow-exception-regex` | 文本输入 | 未实现 | — |
| swallow regex · swallow_regex | `hypr-misc.swallow-regex` | 文本输入 | 未实现 | — |

### Hyprland · Ecosystem options — `hypr-ecosystem`

合成器高级设置：ecosystem · Hyprland

页面状态：**未实现**；条目：3；已实现 0 / 未实现 3 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### Hyprland 生态选项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Enable compositor permissions · enforce_permissions | `hypr-ecosystem.enforce-permissions` | 开关 | 未实现 | — |
| Disable donation prompt · no_donation_nag | `hypr-ecosystem.no-donation-nag` | 开关 | 未实现 | — |
| Disable update news · no_update_news | `hypr-ecosystem.no-update-news` | 开关 | 未实现 | — |

### Hyprland · Compositor diagnostic options — `hypr-debug`

合成器高级设置：debug · Hyprland

页面状态：**未实现**；条目：22；已实现 0 / 未实现 22 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 合成器诊断选项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| colored stdout logs · colored_stdout_logs | `hypr-debug.colored-stdout-logs` | 开关 | 未实现 | — |
| damage blink · damage_blink | `hypr-debug.damage-blink` | 开关 | 未实现 | — |
| damage tracking · damage_tracking | `hypr-debug.damage-tracking` | 滑块 | 未实现 | — |
| disable logs · disable_logs | `hypr-debug.disable-logs` | 开关 | 未实现 | — |
| disable scale checks · disable_scale_checks | `hypr-debug.disable-scale-checks` | 开关 | 未实现 | — |
| disable time · disable_time | `hypr-debug.disable-time` | 开关 | 未实现 | — |
| ds handle same buffer · ds_handle_same_buffer | `hypr-debug.ds-handle-same-buffer` | 开关 | 未实现 | — |
| ds handle same buffer fifo · ds_handle_same_buffer_fifo | `hypr-debug.ds-handle-same-buffer-fifo` | 开关 | 未实现 | — |
| enable stdout logs · enable_stdout_logs | `hypr-debug.enable-stdout-logs` | 开关 | 未实现 | — |
| error limit · error_limit | `hypr-debug.error-limit` | 滑块 | 未实现 | — |
| error position · error_position | `hypr-debug.error-position` | 滑块 | 未实现 | — |
| fifo pending workaround · fifo_pending_workaround | `hypr-debug.fifo-pending-workaround` | 开关 | 未实现 | — |
| full cm proto · full_cm_proto | `hypr-debug.full-cm-proto` | 开关 | 未实现 | — |
| gl debugging · gl_debugging | `hypr-debug.gl-debugging` | 开关 | 未实现 | — |
| invalidate buffers · invalidate_buffers | `hypr-debug.invalidate-buffers` | 滑块 | 未实现 | — |
| log damage · log_damage | `hypr-debug.log-damage` | 开关 | 未实现 | — |
| manual crash · manual_crash | `hypr-debug.manual-crash` | 滑块 | 未实现 | — |
| overlay · overlay | `hypr-debug.overlay` | 开关 | 未实现 | — |
| pass · pass | `hypr-debug.pass` | 开关 | 未实现 | — |
| render solitary wo damage · render_solitary_wo_damage | `hypr-debug.render-solitary-wo-damage` | 开关 | 未实现 | — |
| suppress errors · suppress_errors | `hypr-debug.suppress-errors` | 开关 | 未实现 | — |
| vfr · vfr | `hypr-debug.vfr` | 开关 | 未实现 | — |

### Hyprland · Experimental options — `hypr-experimental`

合成器高级设置：experimental · Hyprland

页面状态：**未实现**；条目：1；已实现 0 / 未实现 1 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-options](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/core/config-options.md)、[hyprviz-project](https://github.com/timasoft/hyprviz/blob/83e4dfcde1eeae157b10c799e46fda1fae630269/src/gui.rs)。

#### 实验性选项

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| wp cm 1 2 · wp_cm_1_2 | `hypr-experimental.wp-cm-1-2` | 开关 | 未实现 | — |

### Configuration files and modules — `hypr-config-files`

Lua / legacy 配置、包含关系与注释保留 · Hyprland

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hyprsettings-project](https://github.com/acropolis914/hyprsettings/blob/2343820372012eb436d7d24fe645f7948651d37b/README.md)。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Configure entry path | `hypr-config-files.entry` | 文本输入 | 未实现 | — |
| Configure syntax version | `hypr-config-files.format` | 选择 | 未实现 | — |
| Included files and module relationships | `hypr-config-files.includes` | 操作 | 未实现 | — |
| Variables and overriding priorities | `hypr-config-files.precedence` | 操作 | 未实现 | — |
| Keep comments and file organization | `hypr-config-files.comments` | 开关 | 未实现 | — |
| View modification differences | `hypr-config-files.diff` | 操作 | 未实现 | — |
| Configure syntax checking | `hypr-config-files.validation` | 操作 | 未实现 | — |
| Reload configuration | `hypr-config-files.reload` | 操作 | 未实现 | — |

### UWSM and user services — `hypr-session-services`

会话启动方式和用户服务生命周期 · 可选组件 UWSM / systemd 用户会话

页面状态：**未实现**；条目：5；已实现 0 / 未实现 5 / 不适用 0。

原因：尚未实现；可选组件 UWSM / systemd 用户会话 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-systemd](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/configuring/extra/systemd.md)。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Session management method | `hypr-session-services.manager` | 选择 | 未实现 | — |
| Session environment import | `hypr-session-services.environment` | 文本输入 | 未实现 | — |
| Desktop User Services | `hypr-session-services.services` | 操作 | 未实现 | — |
| Graphics session target | `hypr-session-services.targets` | 信息展示 | 未实现 | — |
| Session service log | `hypr-session-services.logs` | 操作 | 未实现 | — |

### Hyprland plugin — `hypr-plugins`

插件来源、加载状态与版本兼容 · Hyprland

页面状态：**未实现**；条目：7；已实现 0 / 未实现 7 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-plugins](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/hyprland-plugins/using-plugins.md)。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Plug-in warehouse address | `hypr-plugins.repository` | 文本输入 | 未实现 | — |
| Plug-in list and status | `hypr-plugins.list` | 信息展示 | 未实现 | — |
| Enable plugins | `hypr-plugins.enable` | 开关 | 未实现 | — |
| Check for plugin updates | `hypr-plugins.update` | 操作 | 未实现 | — |
| Reload plugin | `hypr-plugins.reload` | 操作 | 未实现 | — |
| Hyprland ABI Compatibility Status | `hypr-plugins.compatibility` | 信息展示 | 未实现 | — |
| Plug-in loading permissions | `hypr-plugins.permissions` | 操作 | 未实现 | — |

### Session information and IPC diagnostics — `hypr-diagnostics`

版本、配置错误、窗口和设备诊断 · Hyprland

页面状态：**未实现**；条目：8；已实现 0 / 未实现 8 / 不适用 0。

原因：尚未实现；Hyprland 设置仅供界面预览，需在未来验证组件安装、版本与可用接口，不会读取或修改当前系统。

参考资料：[hypr-ipc](https://github.com/hyprwm/hyprland-wiki/blob/026b282bdde916bb7ce77689857f40cf1e829e82/content/ipc/_index.md)。

#### 设置

| 功能小项 | 稳定 ID | 控件 | 状态 | 跟踪 / 验证 |
| --- | --- | --- | --- | --- |
| Hyprland versions and commits | `hypr-diagnostics.version` | 信息展示 | 未实现 | — |
| Configuration error | `hypr-diagnostics.errors` | 信息展示 | 未实现 | — |
| Window and application information | `hypr-diagnostics.clients` | 信息展示 | 未实现 | — |
| Layer namespace | `hypr-diagnostics.layers` | 信息展示 | 未实现 | — |
| Monitor capabilities | `hypr-diagnostics.monitors` | 信息展示 | 未实现 | — |
| Enter device identification | `hypr-diagnostics.devices` | 信息展示 | 未实现 | — |
| IPC event viewing | `hypr-diagnostics.events` | 操作 | 未实现 | — |
| Export diagnostic summary | `hypr-diagnostics.report` | 操作 | 未实现 | — |

## English UI and sidebar navigation update

- All bundled settings labels, descriptions, availability reasons, and sample choices use English. Stable IDs, source references, counts, integration states, and existing tracking notes are preserved.
- Categories expand and collapse in the sidebar; every secondary page has an icon. Home shows category cards, and selecting a category opens its first settings page.
- Flutter draws the title bar on all routes, with drag, double-click maximize/restore, and Close. The native runner disables GTK decorations and retains its existing initial window size.
- Window controls use the MIT-licensed window_manager package. No system setting integration has been added.
- The sidebar branding block has been removed; the app identity remains in the custom title bar.
- Verification: Dart format, Flutter analyze, all 16 Flutter tests (including all 308 pages at widths 1280, 600, and 360), Linux debug build, Cargo format/clippy/tests, and git diff checks passed. Live Hyprland inspection confirmed the custom title bar, English content, and sidebar expand/collapse/navigation; the branding removal was hot-reloaded. Drag/maximize/Close requests are covered by a mocked platform-channel test; their compositor behavior was not individually exercised.

## About page cleanup

- Repository is a clickable list item that opens its fixed HTTPS URL with the Linux desktop opener and reports launch failures.
- Available items no longer show status badges; Planned and Unsupported labels remain.
- Version follows the reference app format, `0.1.0+2026-10-26`, and matches pubspec.yaml. Redundant About descriptions, the status legend, and the matching Home subtitle are removed.
- Verification: all 17 Flutter tests, format/analyze, Linux debug build, Cargo checks, and git diff checks passed. The running app was hot-reloaded. The desktop opener accepted the repository URL and opened the existing browser session; authenticated repository access was not checked.
- About branding now sits directly on the page without a surface card; repository and license list styling is unchanged.

## Header cleanup

- Removed the visible page Back button and category breadcrumb link. Page titles and compact sidebar access remain; Alt+Left still supports keyboard history navigation.
- About version is plain text without a chip border or fill. Catalog items, IDs, and integration states are unchanged.
- Verification: all 17 Flutter tests, format/analyze, Linux debug build, Cargo checks, and git diff checks passed. The running app was hot-reloaded and the Home header inspected on Hyprland; About styling is covered by widget checks.

## License layout correction

- Replaced the stock stacked license route with a license view inside the existing settings shell. The custom title bar and sidebar remain accessible, with no extra Back button.
- Package list and selected license text have separate bounded scroll areas: side by side in wide content, stacked in compact content. All LicenseRegistry entries and paragraph indentation are retained. Loading, empty, and failure states are explicit.

## Application preferences and persistent navigation

- Added the two implemented app-only Material Design controls under Themes; existing catalog IDs, sources, and tracking notes are preserved. Host settings remain unavailable previews.
- The sidebar is persistent. The native runner declares a minimum width of 1000 logical pixels without imposing window placement.
- Configuration architecture and validation evidence are documented in [app-preferences.md](app-preferences.md). Seed color configuration is intentionally omitted.

### Material appearance verification (2026-10-27)

- All 32 Flutter tests passed, including strict TOML/schema validation, all 27 style/mode round trips, atomic file writes, modes/symlinks, failed replacement cleanup, serialized edits, invalid external edits, disposal, live Material controls, Follow system brightness, error banners, and retained navigation.
- Dart format/analyze, Linux Debug and Release builds, Cargo format/clippy/tests, and git diff checks passed.
- A separate native Linux process loaded an isolated Dark + Monochrome configuration. Invoking its actual dropdown callbacks changed the complete application to Vibrant + Light and persisted both choices; restarting restored those values. Native engine screenshots confirmed both appearances and the corrected license view inside the persistent sidebar.
- Wayland protocol logs confirmed `xdg_toplevel.set_min_size(1000, 0)` before mapping. The test process used its own temporary configuration directory; personal configuration was not modified.
- No seed-color setting, automatic external-file watcher, host integration, or cross-process file locking is included. External edits require Reload configuration; avoid simultaneous editing by multiple instances.

## System appearance backend (supersedes the app-only preview above)

- Removed Follow system. Light/Dark uses Rust through flutter_rust_bridge 2.13.0; startup/Reload reads actual system preference without enforcing a stored preview value. The application follows the selected mode.
- GNOME/libadwaita uses the installed color-scheme schema key. GTK 3 uses its explicit prefer-dark flag; modern GTK 4.20+ uses gtk-interface-color-scheme and removes the obsolete GTK 4 flag. Existing GTK themes switch only to matching installed variants.
- Installed Qt 6 Quick Material/Universal modules use their documented Light/Dark environment variables. Managed blocks update only fish and the active Hyprland Lua entrypoint, with syntax validation and preserved surrounding content. Qt Widgets/qt6ct/Kvantum platform plugins and unrelated palettes are retained because they have no uniform explicit Light/Dark switch. Missing optional targets are reported and skipped.
- Backend file writes are atomic, preserve comments/permissions/symlinks, verify readback, detect conflicting edits, and roll back prior changes on failure. GSettings persistence is independently checked in a fresh process. A per-user lock serializes system updates.
- AGENTS.md now targets current Arch dependencies and fish; no old dependency compatibility layers, Bash/Zsh environment edits, or forced theme/plugin replacements. Full ownership, configuration paths, failure behavior, session boundaries, and primary documentation are in [app-preferences.md](app-preferences.md).

### System appearance verification (2026-10-27)

- All 34 Flutter tests and 13 Rust tests passed, with Dart format/analyze, Cargo fmt/clippy, and diff checks. Linux Debug and Release builds bundle the native appearance library and third-party notices.
- A native app in an isolated XDG/keyfile environment loaded Dark/Monochrome; its actual widget callbacks selected Vibrant/Light through the real Rust bridge. Independent readback confirmed GNOME prefer-light, GTK 3/4 flags, and both Qt environment variables in fish/Hyprland configuration. The process completed without a controller error and was stopped after verification.
- Real desktop Light/Dark toggles were independently verified with fresh GNOME reads, GTK 3/4 native probes, and Qt 6 Material/Universal QML probes launched by fish using the generated environment block. Existing fish/Hyprland files passed full syntax validation; evaluating only the generated Lua block confirmed the hl.env keys and values. No unrelated config content changed, and original GNOME user values and all four personal files were restored and verified afterward.
- No compositor/session restart was performed. Environment propagation to a full new Hyprland login remains untested; existing processes retain their environment and explicit per-app overrides can take precedence. No plugin/style replacement or seed color feature was added.

## Public application interfaces and Bar integration (2026-10-30)

- Added operation parity for every currently available control through CLI and
  versioned session D-Bus, using the existing application controller and Rust
  backend. Preview availability and existing control IDs are unchanged.
- Added catalog inspection/search, bounded listing, page navigation, reload,
  theme change/error observation, and application open/quit operations.
- Shared the configuration decoder and MD3E policy through the public
  `remya_settings_client` package. Remya Bar remains a separate application and
  consumes the effective theme through the Settings service.
- Standardized application IDs (`top.remya.settings`, `top.remya.bar`), XDG
  installation, user commands, and cwd-independent repository debug config.
- Interface parity/rollback tests and isolated installed CLI/D-Bus tests passed,
  including real Rust Light/Dark writes and independent readback inside a
  temporary XDG/keyfile environment. Live bar theme changes passed on all three
  connected outputs. Personal system configuration was not used for write tests.
- API details and boundaries: [public-api.md](public-api.md),
  [xdg-layout.md](xdg-layout.md), and `test/interface_smoke.py`.

- Final live verification also exercised an actual pointer click on the Bar gear,
  transparent capsule corners on all outputs, desktop-entry activation, and
  special-character XDG installation paths. The independent Rust bridge probe
  read all three monitors through socket1 and received a real `openlayer` event
  through socket2. All task-started instances were stopped and reserved space
  returned to the existing desktop baseline.

## Background, accent and fonts (2026-11-02)

- Background: images through hyprpaper configuration and IPC, videos through a managed mpvpaper user unit. Selected files are copied into the application directory and only the copy is referenced. Slideshow and solid color were removed by owner request; `hypr-wallpaper-outputs` and `hypr-paper-misc-options` now open Background.
- Color and Themes share the `themes` page. Accent follows the background through `material-colors` (Celebi and Score) or a `flex_color_picker` choice. Pattern, taskbar and title-bar accent toggles, Quick Facts, Navigation bar, Equipment usage, Copilot key and Qt application pages were removed by owner request.
- Cursor settings moved unchanged to the System Cursor page, still unimplemented; feature-specific options such as touchpad cursor speed and magnifier following stay with their features.
- Fonts: fontconfig list, search, details, install to and uninstall from the user font directory.
- Automated: Rust unit tests with fake desktop and fontconfig (initialization, conflicts, both resolutions, rollback, copy cleanup, sampling failure), Flutter widget tests, and `test/interface_smoke.py` against the installed release with a previously built Bar, proving the unchanged `theme` contract.
- Nested Hyprland with isolated XDG and D-Bus, using real hyprpaper, ffmpeg and fontconfig: first use recorded the `wallpaper[]:` form without changes; a selected image displayed, kept working after its original was deleted, and kept comments and a backup; pixel checks for cover, contain and tile passed and confirmed that hyprpaper IPC shows Fill as Cover; accent resampled on change; external edits raised a conflict that resolved. Pages were reviewed from screenshots.
- Lock screen: Quickshell's desktop layer was replaced by a lock-only `LockBackground`. In a nested session with `session_lock_xray` the lock shows the blurred Quickshell wallpaper and clock above a different hyprpaper image.
- Installed build on the real desktop: a test video ran through the managed unit above hyprpaper on all three outputs, and switching back to image stopped it; test files were then removed and configuration restored byte for byte.
- A real smoke run on 2026-11-02 renamed the workstation because a rejected `Open` still requested authorization and the rename check ran after it. `Open` now authorizes only on success, and the smoke test refuses that check while authorized.
- hyprpaper restarts automatically for splash changes and a newly chosen Fill, limited to the current Hyprland session; see public-api.md.
- Nested Hyprland with two virtual outputs and the release build: Fill and splash changes restarted hyprpaper in about 1.6 s and reduced two instances to one; pixels confirmed Fill, Cover through IPC without a restart, and a per-display image; the workstation's hyprpaper kept its PID.
- Fonts page performance: the list is lazy with no Show more. With 478 real families, opening loaded 21 font files instead of 50, and keyboard navigation scrolled through the list while loading only nearby fonts.
- Untested: a real session lock on the workstation, per-display images on physical outputs, automatic hyprpaper restart on the workstation, video across a real sign-in, the native file and color picker dialogs, and `switchwall.sh` through the wallpaper selector. Real-desktop image changes wait for the duplicate hyprpaper instance to be resolved.

电池历史后端使用 SQLite 永久保存每分钟电量样本、屏幕开关和 logind 睡眠事件；历史页面展示最近 24 小时 / 7 天电量曲线与时长统计，每应用耗电保持未实现。详见 [power.md](power.md)。

## Multitasking, cursor and icon themes (2026-11-09)

- System › Multitasking replaces the Hyprland `hypr-general` and `hypr-general-snap` pages: layout thumbnails, a preview that follows the layout, gaps and border width while sliders move, snapping and border resizing with dependent rows hidden while their parent is off. Gaps accept one value or four sides. `general:locale` was removed (Language and Region owns language).
- Appearance › Cursor (moved from System) and the Icons section of Colors and themes: theme galleries with real XCursor previews (Rust `xcursor` and `png` crates) and icons rendered by the GTK runner from each theme; the size slider stops at the theme's own sizes; theme folders follow the XDG icon path and `XCURSOR_PATH`; packs install from a folder or archive (bsdtar) into `$XDG_DATA_HOME/icons` and can be removed after confirmation. Windows-only pointer colour, text cursor indicator, reference rows, zoom and diagnostic cursor options were removed.
- Architecture: the Hyprland option engine gained a CSS gap kind and per-option first-use adoption; `Resolve … system` now also updates the Settings-owned Lua file so a reload cannot bring the old value back (previously the next write reverted the adopted value and raised the conflict again). The option controller became the feature-neutral `FeatureOptionsController` in `settings/application`, shared by input, desktop and theme packs. Appearance file, environment-block and GNOME-setting writers became value-generic so cursor and icon themes reuse Light/Dark's atomic apply and rollback.
- Automated: Rust appearance tests (discovery, precedence, hidden themes, previews, folder and archive installation, refusal cases, every apply target, rollback on compositor failure) and input tests (gaps, adoption of new options, adoption rewriting the owned file); `test/multitasking_cursor_test.dart`; all Flutter tests; `test/desktop_smoke.py` and `test/input_smoke.py` against a nested Hyprland 0.57 with isolated XDG roots, home and GNOME keyfile (layout, four-sided gaps, cursor options, cursor and icon theme selection across GNOME, GTK, XCursor default, Hyprland and fish environment, KDE through kwriteconfig6, conflict and adoption, pack install, duplicate refusal and removal).
- Installed release on the workstation: the resident service adopted the live window, cursor and theme values on first use without writing (desktop.lua and hyprland.lua unchanged, no conflict); the Multitasking, Cursor and Colors and themes pages were inspected on DP-1, including new page glyphs, Bibata previews, icon previews of Adwaita, Breeze, Papirus and Tela, folder list and pack rows.
- Colors and themes cleanup: the page keeps Color and Icons only. Window decoration previews moved to the new Appearance pages Window appearance and Animations (the Visual effects animation toggle merged into Animations), group and tab colours moved to the window group pages, and the Windows theme bundle (choose, save, background and sound links), the duplicate transparency toggles (Background › Window blur owns blur), the gradient editor, desktop component presets and the screen shader path were deleted. The moved controls remain previews.
- Untested on the real desktop: selecting a different cursor or icon theme (it would replace the existing KDE icon theme `breeze-plus-dark`; the isolated smoke test covers every write), the native folder and archive pickers, and Hyprcursor-only themes (none installed). The workstation's start-up `hyprctl setcursor` in `execs.lua` overrides the saved environment at sign-in; Settings then shows a conflict rather than editing that script.

## Window appearance, animations and dwindle (2026-11-09)

- Appearance › Window appearance and Appearance › Animations become real desktop-group options in the Settings-owned `desktop.lua`; System › Multitasking gains the dwindle layout options, shown only while Dwindle is the layout. The planned `hypr-layout-dwindle` and `hypr-layout-overview` pages were deleted (the overview duplicated the layout chooser; its other rows were shortcut actions).
- Option engine: a translucent color kind (`#rrggbbaa`, written as `rgba(rrggbbaa)`, read from Hyprland's `AARRGGBB` gradient report using its first color), a two-number offset kind, and nested Lua keys for dotted option names (`col.active_border`). The background page's color button became the shared `ColorButton` with an opacity slider for translucent colors.
- Removed instead of implemented: inactive shadow and glow colors (Hyprland reports a value even when unset, so the fallback cannot be read back), `dim_around` (only window rules use it) and the per-animation tree editor (it needs its own `hl.animation`/`hl.curve` line shapes).
- Automated: Rust config tests (round trip of translucent colors, nested keys and offsets, gradient readback, validation); `test/window_appearance_test.dart` (preview, dependent rows hidden, offset write, dwindle rows only for Dwindle); `test/desktop_smoke.py` against a nested Hyprland 0.57 with isolated XDG roots (border color, shadow offset, rounding, opacity, wobble and dwindle force split applied live, written to `desktop.lua`, kept after reload, read back without conflict, invalid values refused).

## Text size (2026-11-09)

- Accessibility › Text size writes GNOME's `org.gnome.desktop.interface text-scaling-factor` through the Rust appearance crate (`text_size.rs`), reusing the GNOME-setting apply, fresh `gsettings get` readback and rollback of Light/Dark; the service exposes `Get/Set text-size.scale`, `Resolve text-size` and `Changed("text-size")`. The slider covers GNOME's accepted 50%–300% in 5% steps, applies on release, and a sample paragraph follows the thumb. The old Apply action and the Windows reference row were removed.
- Where it applies: the Flutter 3.47.8 Linux engine library contains `changed::text-scaling-factor` and portal `SettingChanged` handling for this key, so Settings and other Flutter apps follow it live; GTK 3 and GTK 4 read the same key. Qt, KDE and other toolkits are not changed.
- Automated: Rust appearance test (first-use adoption without writing, write, range rejection, conflict retention and refused writes, both resolutions, failed detection leaving the configuration uninitialized); `test/text_size_test.dart` (sample follows the slider, 5% step rounding, conflict summary and disabled slider); `test/desktop_smoke.py` against a nested Hyprland with isolated XDG roots and the GSettings keyfile backend (first use, D-Bus write and keyfile readback, invalid value, external change conflict, refused write, both resolutions).
- Untested: the installed release on the real desktop (the workstation's GSettings were only read, value 1.0), live update of open GTK windows, and the CLI path, which dispatches through the same service.

## Workspaces (2026-11-09)

- System › Workspaces (after Multitasking) replaces the planned workspace and workspace-rule preview pages: two scratchpad options and window launch tracking move in from the compositor behavior preview, joined by scratchpad hiding on workspace change, pointer placement and scratchpad click-through, all desktop-group options in the Settings-owned `desktop.lua`. Workspace back-and-forth and cycling stay on Keyboard shortcuts in the input group.
- Workspace rules: `desktop.lua` accepts one more strict line shape, `hl.workspace_rule({ workspace, monitor, default, persistent, default_name })` in fixed order; `workspaces.rule-set` and `workspaces.rule-remove` validate the selector (number, `name:`, `special:`), connector name and one-line text, reload the configuration and wait for `hyprctl workspacerules` to report the change, restoring the files otherwise. Saved rules are reconciled with the file under the conflict ID `workspaces`. Rules from other files (for example a display tool's `workspaces.lua`) are shown read-only and never written. The page draws each live display at its layout position and logical size with its workspaces; selecting one edits or starts its rule. Removed instead of implemented: per-workspace gaps, borders, layout and animation fields (Multitasking and Window appearance already set them globally).
- Automated: Rust config test (rule round trip with escaped text, refusal of other fields, reordered or foreign Lua, and rules in `input.lua`); Rust desktop test with a fake compositor (first use adopts without writing, logical size of a rotated scaled display, validation, write and reload readback, one start workspace per display, editing in place and refused rename onto a used workspace, conflict and both resolutions, removal); `test/workspaces_test.dart` (display map chips, read-only foreign rules, prefilled editor hiding unusable fields, edit with `previous`, removal); `test/desktop_smoke.py` against a nested Hyprland 0.57 with isolated XDG roots (options applied and kept after reload, persistent rule with a default name created and read back, edit dropping the old fields, invalid rules refused, removal, a rule in the user's own `hyprland.lua` left untouched).
- Untested: the installed release on the real desktop (the workstation's `workspacerules`, monitors and workspaces were only read), `default` taking effect when a display is connected, the CLI path (it dispatches through the same service), and a rule field that another file also sets (Hyprland merges same-workspace rules, so removing it times out and is undone).

## Compositor font, compositor bell and Start/Taskbar removal (2026-11-09)

- Appearance › Fonts gains `fonts.compositor-family` (`misc:font_family`) in its Advanced section, and Sound › Output & input gains `sound.compositor-bell` (`misc:bell_sound`, supporting `"default"`, `"none"` and absolute `.wav`/`.ogg`/`.oga` audio files) in its Advanced section, both persisted as desktop-group options in the Settings-owned `desktop.lua` and `desktop.toml`.
- Removed the unimplemented `start` (Start menu), `start-folders` (Start menu folder) and `taskbar` (Taskbar) second-level pages from the catalog, Windows and Hyprland coverage mappings, and progress tracker.
- Automated: Rust `remya_settings_input` unit tests (`compositor_font_and_bell_validate_and_read_back`), `test/catalog_test.dart`, `test/fonts_test.dart`, `test/sound_test.dart`, and `test/desktop_smoke.py` against a nested Hyprland 0.57 instance with isolated XDG roots (`fonts.compositor-family` and `sound.compositor-bell` applied live, persisted to `desktop.lua`, preserved across `hyprctl reload`, switched between custom file, `"none"` and `"default"`, and invalid values rejected).

## Window rules, environment variables and printers (2026-11-12)

- Decisions: Apps › Window rules replaces the three `hypr-window-rule-*` previews with one page; System › Environment variables replaces `hypr-environment`; Bluetooth & devices › Printers becomes a CUPS page. Deleted instead of implemented: Desktop Portal and Screen Sharing (`hypr-desktop-portals`; xdg-desktop-portal-hyprland already offers its own share picker and restore token), System security (`security`; firewall support was dropped and the rest only mirrored Windows Security) and General privacy (`general-privacy`; Windows-only). Clipboard was already implemented and is unchanged.
- Window rules: one strict `hl.window_rule` line shape in `desktop.lua` with literal (regex-escaped) class and title text, keyed by class and title; each new or edited rule is first evaluated by Hyprland with `enabled = false`, so unknown fields and wrong types are refused before any file changes; the write then reloads explicitly and fails, restoring the files, if `hyprctl configerrors` names a Settings file. Saved rules are reconciled under the conflict ID `window-rules`. The editor offers open windows by app class and previews placement, size and opacity on a display outline; dependent fields (center, size, pin, background opening) are hidden while their parent is off. Rules in the user's other files are not shown.
- Environment variables: `hl.env` lines in `desktop.lua`, reconciled under `environment`; names owned by Cursor and Light/Dark, or required by the session (`PATH`, `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE` and others), are refused. Hyprland sets new values on reload for apps it starts afterwards; a removed variable disappears only after signing in again, as the page says.
- Printers: Rust crate `lib/src/rust/printers` over the CUPS tools with a fake for tests; default printer (per-user `lpoptions`), test page, pause and resume, job cancel and printer removal, each validated against a fresh listing and read back. Printers and queues are live CUPS state and are not saved or reconciled.
- Automated: Rust `remya_settings_input` tests (window rule and variable round trip, literal escaping, foreign and reordered lines refused, validation, probe refusal, configerrors rollback, edit in place, conflict and resolution, removal); `remya_settings_printers` tests; `test/printers_test.dart`; `test/window_rules_environment_test.dart`; `test/catalog_test.dart`.
- Real desktop (Hyprland 0.57.2): the rendered rule lines were accepted by `hyprctl eval` with `enabled = false`, and unknown fields and wrong types were refused. CUPS 2.4.20 with a USB HP Smart Tank 510: listing, setting the default printer (then restored) and pausing and resuming worked without a password for this user.

