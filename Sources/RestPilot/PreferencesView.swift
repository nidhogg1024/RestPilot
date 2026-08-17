import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "通用"
    case plans = "休息计划"
    case content = "提示内容"
    case appearance = "显示与声音"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .plans: return "timer"
        case .content: return "text.badge.plus"
        case .appearance: return "paintbrush"
        }
    }
}

struct PreferencesView: View {
    @State private var settings: AppSettings
    @State private var selection: SettingsSection?
    @State private var contentKind: BreakKind = .eye
    @State private var selectedContentID: UUID?
    @State private var draggedContentID: UUID?
    @State private var launchError: String?
    let onSave: (AppSettings) -> Void
    let onPreview: (BreakKind, AppSettings) -> Void

    init(
        settings: AppSettings,
        initialSelection: SettingsSection = .general,
        onSave: @escaping (AppSettings) -> Void,
        onPreview: @escaping (BreakKind, AppSettings) -> Void
    ) {
        _settings = State(initialValue: settings)
        _selection = State(initialValue: initialSelection)
        self.onSave = onSave
        self.onPreview = onPreview
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 168, idealWidth: 168, maxWidth: 168)
            .fixedSize(horizontal: true, vertical: false)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    pageContent
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 600, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .layoutPriority(1)
        }
        .frame(minWidth: 760, minHeight: 520)
        .toggleStyle(.switch)
        .tint(RestPilotTheme.active)
        .onChange(of: settings) { onSave($0) }
        .alert("无法修改开机启动", isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
            Button("好") { launchError = nil }
        } message: { Text(launchError ?? "") }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection?.rawValue ?? "设置").font(.system(size: 21, weight: .semibold))
            Text(pageSubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch selection ?? .general {
        case .general: generalPage
        case .plans: plansPage
        case .content: contentPage
        case .appearance: appearancePage
        }
    }

    private var pageSubtitle: String {
        switch selection ?? .general {
        case .general: return "控制 RestPilot 如何随系统运行，以及什么时候暂停计时。"
        case .plans: return "组合短休息和站立休息，建立适合你的工作节奏。"
        case .content: return "管理休息时展示的文字和图片，并随时预览效果。"
        case .appearance: return "调整遮罩、显示器、声音与菜单栏表现。"
        }
    }

    private var generalPage: some View {
        VStack(spacing: 22) {
            SettingsGroup(
                title: "启动",
                state: settings.launchAtLogin ? .active : .inactive
            ) {
                settingRow(
                    "开机自动启动",
                    detail: "登录 Mac 后自动开始运行",
                    icon: "power",
                    isActive: settings.launchAtLogin
                ) {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden().controlSize(.small)
                        .onChange(of: settings.launchAtLogin) { updateLaunchAtLogin($0) }
                }
            }
            SettingsGroup(
                title: "智能暂停",
                state: settings.pauseWhenLocked || settings.pauseWhenIdle ? .active : .inactive
            ) {
                settingRow(
                    "锁屏或睡眠时暂停",
                    detail: "返回后从原来的剩余时间继续",
                    icon: "lock",
                    isActive: settings.pauseWhenLocked
                ) {
                    Toggle("", isOn: $settings.pauseWhenLocked).labelsHidden().controlSize(.small)
                }
                Divider()
                settingRow(
                    "长时间无操作时暂停",
                    detail: "避免离开电脑时仍累计工作时间",
                    icon: "hand.raised",
                    isActive: settings.pauseWhenIdle
                ) {
                    Toggle("", isOn: $settings.pauseWhenIdle).labelsHidden().controlSize(.small)
                }
                if settings.pauseWhenIdle {
                    Divider()
                    HStack {
                        Text("无操作阈值").foregroundStyle(.secondary)
                        Spacer()
                        Picker("无操作阈值", selection: $settings.idleMinutes) {
                            ForEach([1, 3, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 105)
                    }
                }
            }
        }
    }

    private var plansPage: some View {
        VStack(spacing: 22) {
            planGroup(kind: .eye, enabled: $settings.eyeEnabled)
            planGroup(kind: .stand, enabled: $settings.standEnabled)
            SettingsGroup(
                title: "跳过管理",
                state: settings.strengthenSkipReminders ? .active : .inactive
            ) {
                settingRow(
                    "连续跳过时加强提醒",
                    detail: "连续跳过 2 次后强化提示；自动休息始终可以延后",
                    icon: "bell.badge",
                    isActive: settings.strengthenSkipReminders
                ) {
                    Toggle("", isOn: $settings.strengthenSkipReminders)
                        .labelsHidden()
                        .controlSize(.small)
                }
                Text("跳过不会被当作完成，也不会打乱眼休与站立休息的正常顺序。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !settings.eyeEnabled && !settings.standEnabled {
                Label("至少启用一种休息计划；否则当前工作周期结束后会自动停止。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(RestPilotTheme.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RestPilotTheme.warningSurface,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
            }
        }
    }

    private func planGroup(kind: BreakKind, enabled: Binding<Bool>) -> some View {
        let isEnabled = enabled.wrappedValue
        return SettingsGroup(
            title: kind.displayName,
            state: isEnabled ? .active : .inactive
        ) {
            HStack {
                SettingsStatusIcon(
                    systemImage: kind == .eye ? "eye" : "figure.walk",
                    state: isEnabled ? .active : .inactive
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind == .eye ? "短暂离开屏幕，缓解眼部疲劳" : "定期站起来活动身体")
                    Label(
                        isEnabled ? "计划已启用" : "计划已关闭",
                        systemImage: isEnabled ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.weight(isEnabled ? .semibold : .regular))
                    .foregroundStyle(isEnabled ? RestPilotTheme.active : RestPilotTheme.inactive)
                }
                Spacer()
                Toggle("", isOn: enabled).labelsHidden()
            }
            if isEnabled {
                Divider()
                if kind == .eye {
                    durationEditor(title: "专注时长", value: $settings.workMinutes, range: 1...180, unit: "分钟")
                    durationEditor(title: "休息时长", value: $settings.eyeBreakSeconds, range: 5...600, unit: "秒", step: 5)
                } else {
                    durationEditor(title: "触发频率", value: $settings.standAfterEyeBreaks, range: 1...12, unit: "次眼休后")
                    durationEditor(title: "休息时长", value: $settings.standBreakMinutes, range: 1...30, unit: "分钟")
                    Text("例如设为 2：眼休 → 工作 → 眼休 → 工作 → 站立休息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("预览 \(kind.displayName)") { onPreview(kind, settings) }
                }
            }
        }
    }

    private func durationEditor(title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String, step: Int = 1) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .onChange(of: value.wrappedValue) { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }
            Text(unit).foregroundStyle(.secondary).frame(minWidth: 72, alignment: .leading)
        }
    }

    private var contentPage: some View {
        VStack(spacing: 16) {
            Picker("内容类型", selection: $contentKind) {
                ForEach(BreakKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("内容库").font(.headline)
                        Spacer()
                        Button { addContent() } label: { Image(systemName: "plus") }
                            .buttonStyle(.bordered).help("添加内容")
                    }
                    Text("拖动卡片排序；图片也可以直接拖到卡片中。")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView { contentCards }
                    HStack {
                        Button("恢复默认") { restoreDefaultContents() }
                        Spacer()
                        Button("全屏预览") { onPreview(contentKind, settings) }
                    }
                }
                .padding(16)
                .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("实时预览").font(.headline)
                        Spacer()
                        Text(contentKind.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    InlineBreakPreview(kind: contentKind, content: selectedContent, settings: settings)
                    Text("编辑文字、替换图片或调整显示样式后，预览会立即更新。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(minWidth: 280)
            }
            .frame(minHeight: 430)
        }
        .onChange(of: contentKind) { _ in selectedContentID = nil }
    }

    @ViewBuilder private var contentCards: some View {
        let binding = contentKind == .eye ? $settings.eyeContents : $settings.standContents
        if binding.wrappedValue.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "text.bubble").font(.system(size: 32)).foregroundStyle(.secondary)
                Text("还没有提示内容").font(.headline)
                Text("添加一条文字或图片提示。").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(binding.wrappedValue.enumerated()), id: \.element.id) { index, item in
                    contentCard(binding: binding, index: index, item: item)
                        .onDrag {
                            draggedContentID = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ContentReorderDropDelegate(
                            targetID: item.id,
                            draggedID: $draggedContentID,
                            items: binding
                        ))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func contentCard(binding: Binding<[BreakContent]>, index: Int, item: BreakContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                Toggle(isOn: binding[index].isEnabled) {
                    Label(
                        item.isEnabled ? "已启用" : "已停用",
                        systemImage: item.isEnabled ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.weight(item.isEnabled ? .semibold : .regular))
                    .foregroundStyle(item.isEnabled ? RestPilotTheme.active : RestPilotTheme.inactive)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Menu {
                    Button("复制") { duplicateContent(binding: binding, index: index) }
                    Button("删除", role: .destructive) { deleteContent(binding: binding, index: index) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
            }
            TextField("输入休息提示…", text: binding[index].text, axis: .vertical)
                .font(.body.weight(.medium))
                .textFieldStyle(.plain)
                .lineLimit(2...4)

            imageDropArea(binding: binding, index: index, item: item)

            HStack {
                Button(item.imagePath == nil ? "添加图片" : "更换图片") { chooseImage(binding: binding, index: index) }
                if item.imagePath != nil {
                    Button("移除图片", role: .destructive) { binding.wrappedValue[index].imagePath = nil }
                }
                Spacer()
                Button("预览此条") {
                    selectedContentID = item.id
                    onPreview(contentKind, settingsWithSelectedFirst(item))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(selectedContentID == item.id ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedContentID == item.id ? Color.accentColor.opacity(0.72) : Color(nsColor: .separatorColor).opacity(0.30), lineWidth: selectedContentID == item.id ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedContentID = item.id }
    }

    @ViewBuilder private func imageDropArea(binding: Binding<[BreakContent]>, index: Int, item: BreakContent) -> some View {
        if let path = item.imagePath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable().scaledToFill().frame(maxWidth: .infinity, minHeight: 120, maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) { Text("拖入另一张图片即可替换").font(.caption2).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(8) }
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { handleImageDrop($0, binding: binding, index: index) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus").font(.title2).foregroundStyle(.secondary)
                Text("拖入图片，或点击下方添加").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5])))
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { handleImageDrop($0, binding: binding, index: index) }
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 22) {
            SettingsGroup(
                title: "全屏背景",
                state: settings.backgroundMode == .none ? .inactive : .active
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("展示方式").foregroundStyle(.secondary)
                    Picker("展示方式", selection: Binding(
                        get: { settings.backgroundMode },
                        set: { settings.backgroundMode = $0 }
                    )) {
                        ForEach(BackgroundMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if settings.backgroundMode != .none {
                    Divider()
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(BuiltInBackground.allCases) { background in
                            backgroundTile(
                                title: background.displayName,
                                path: background.thumbnailPath,
                                selected: settings.backgroundMode == .fixed && settings.selectedBackgroundID != "custom" && settings.selectedBackground == background
                            ) {
                                settings.selectedBackground = background
                                settings.backgroundMode = .fixed
                            }
                        }
                        if let customPath = settings.customBackgroundPath {
                            backgroundTile(
                                title: "自定义背景",
                                path: customPath,
                                selected: settings.backgroundMode == .fixed && settings.selectedBackgroundID == "custom"
                            ) {
                                settings.selectedBackgroundID = "custom"
                                settings.backgroundMode = .fixed
                            }
                        }
                    }
                    HStack {
                        Button(settings.customBackgroundPath == nil ? "导入自定义背景…" : "更换自定义背景…") {
                            chooseBackground()
                        }
                        if settings.customBackgroundPath != nil {
                            Button("移除自定义", role: .destructive) {
                                settings.customBackgroundPath = nil
                                if settings.selectedBackgroundID == "custom" {
                                    settings.selectedBackground = .ambient
                                }
                            }
                        }
                        Spacer()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("背景暗化")
                            Spacer()
                            Text("\(Int(settings.backgroundDim * 100))%").foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { settings.backgroundDim },
                            set: { settings.backgroundDim = $0 }
                        ), in: 0...0.45)
                    }
                    Text(settings.backgroundMode == .random
                         ? "每次休息会从内置背景和自定义背景中随机选择。"
                         : "每块显示器会按自身比例独立裁切，不会拉伸图片。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsGroup(title: "休息遮罩") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("背景样式").foregroundStyle(.secondary)
                    Picker("背景样式", selection: $settings.overlayStyle) {
                        ForEach(OverlayStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
                settingRow(
                    "在所有显示器显示",
                    detail: "每块屏幕都会同步显示休息内容",
                    icon: "rectangle.on.rectangle",
                    isActive: settings.showOnAllDisplays
                ) {
                    Toggle("", isOn: $settings.showOnAllDisplays).labelsHidden()
                }
                Divider()
                settingRow(
                    "显示跳过按钮",
                    detail: "允许提前结束当前休息",
                    icon: "forward.end",
                    isActive: settings.showSkipButton
                ) {
                    Toggle("", isOn: $settings.showSkipButton).labelsHidden()
                }
                Divider()
                settingRow(
                    "柔和进入与退出",
                    detail: "休息遮罩会平滑淡入和淡出",
                    icon: "circle.lefthalf.filled",
                    isActive: settings.fadeInOverlay
                ) {
                    Toggle("", isOn: $settings.fadeInOverlay).labelsHidden()
                }
                Divider()
                settingRow(
                    "显示倒计时",
                    detail: "关闭后只展示休息内容",
                    icon: "clock",
                    isActive: settings.showCountdown
                ) {
                    Toggle("", isOn: $settings.showCountdown).labelsHidden()
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("遮罩强度"); Spacer(); Text("\(Int(settings.overlayOpacity * 100))%").foregroundStyle(.secondary) }
                    Slider(value: $settings.overlayOpacity, in: 0.55...0.98)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("文字大小"); Spacer(); Text("\(Int(settings.textScale * 100))%").foregroundStyle(.secondary) }
                    Slider(value: $settings.textScale, in: 0.75...1.35)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("图片大小"); Spacer(); Text("\(Int(settings.imageScale * 100))%").foregroundStyle(.secondary) }
                    Slider(value: $settings.imageScale, in: 0.6...1.4)
                }
                HStack { Spacer(); Button("预览遮罩") { onPreview(.eye, settings) } }
            }
            SettingsGroup(
                title: "菜单栏与声音",
                state: settings.showTimeInMenuBar || settings.playSoundWhenBreakEnds ? .active : .inactive
            ) {
                settingRow(
                    "显示剩余时间",
                    detail: "在菜单栏图标旁显示倒计时",
                    icon: "menubar.rectangle",
                    isActive: settings.showTimeInMenuBar
                ) {
                    Toggle("", isOn: $settings.showTimeInMenuBar).labelsHidden()
                }
                Divider()
                settingRow(
                    "休息结束播放声音",
                    detail: "使用 macOS 内置提示音",
                    icon: "speaker.wave.2",
                    isActive: settings.playSoundWhenBreakEnds
                ) {
                    Toggle("", isOn: $settings.playSoundWhenBreakEnds).labelsHidden()
                }
                if settings.playSoundWhenBreakEnds {
                    Divider()
                    HStack {
                        Picker("提示音", selection: $settings.endSoundName) {
                            ForEach(["Glass", "Hero", "Ping", "Pop", "Purr", "Submarine"], id: \.self) { Text($0).tag($0) }
                        }
                        Spacer()
                        Button("试听") { NSSound(named: NSSound.Name(settings.endSoundName))?.play() }
                    }
                }
            }
        }
    }

    private func backgroundTile(title: String, path: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Group {
                    if let path, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.975, green: 0.969, blue: 0.949),
                                Color(red: 0.925, green: 0.936, blue: 0.943)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor.opacity(0.72) : Color(nsColor: .separatorColor).opacity(0.30), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func chooseBackground() {
        guard let path = ContentFileStore.chooseAndCopyBackground() else { return }
        settings.customBackgroundPath = path
        settings.selectedBackgroundID = "custom"
        settings.backgroundMode = .fixed
    }

    private func settingRow<Accessory: View>(
        _ title: String,
        detail: String,
        icon: String,
        isActive: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            SettingsStatusIcon(
                systemImage: icon,
                state: isActive ? .active : .inactive
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            settings.launchAtLogin.toggle()
            launchError = "请先把 RestPilot.app 放入“应用程序”文件夹，然后重试。\n\n\(error.localizedDescription)"
        }
    }

    private func addContent() {
        let item = BreakContent(text: contentKind == .eye ? "看看远处，放松双眼" : "站起来活动一下")
        if contentKind == .eye { settings.eyeContents.append(item) }
        else { settings.standContents.append(item) }
        selectedContentID = item.id
    }

    private func restoreDefaultContents() {
        if contentKind == .eye { settings.eyeContents = AppSettings.default.eyeContents }
        else { settings.standContents = AppSettings.default.standContents }
    }

    private func chooseImage(binding: Binding<[BreakContent]>, index: Int) {
        guard let path = ContentFileStore.chooseAndCopyImage() else { return }
        binding.wrappedValue[index].imagePath = path
    }

    private func move(binding: Binding<[BreakContent]>, from index: Int, offset: Int) {
        let destination = index + offset
        guard binding.wrappedValue.indices.contains(destination) else { return }
        binding.wrappedValue.swapAt(index, destination)
    }

    private var selectedContent: BreakContent {
        let values = contentKind == .eye ? settings.eyeContents : settings.standContents
        return values.first { $0.id == selectedContentID } ?? values.first ?? BreakContent(text: "添加一条休息提示")
    }

    private func duplicateContent(binding: Binding<[BreakContent]>, index: Int) {
        var copy = binding.wrappedValue[index]
        copy.id = UUID()
        binding.wrappedValue.insert(copy, at: index + 1)
        selectedContentID = copy.id
    }

    private func deleteContent(binding: Binding<[BreakContent]>, index: Int) {
        let removedID = binding.wrappedValue[index].id
        binding.wrappedValue.remove(at: index)
        if selectedContentID == removedID { selectedContentID = binding.wrappedValue.first?.id }
    }

    private func settingsWithSelectedFirst(_ item: BreakContent) -> AppSettings {
        var copy = settings
        if contentKind == .eye {
            copy.eyeContents.removeAll { $0.id == item.id }
            copy.eyeContents.insert(item, at: 0)
        } else {
            copy.standContents.removeAll { $0.id == item.id }
            copy.standContents.insert(item, at: 0)
        }
        return copy
    }

    private func handleImageDrop(_ providers: [NSItemProvider], binding: Binding<[BreakContent]>, index: Int) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                if let path = ContentFileStore.copyImage(at: url), binding.wrappedValue.indices.contains(index) {
                    binding.wrappedValue[index].imagePath = path
                }
            }
        }
        return true
    }
}

private struct ContentReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var items: [BreakContent]

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID,
              let from = items.firstIndex(where: { $0.id == draggedID }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

private struct InlineBreakPreview: View {
    let kind: BreakKind
    let content: BreakContent
    let settings: AppSettings

    var body: some View {
        let backgroundPath = settings.resolvedBackgroundPath()
        let usesLightText = backgroundPath != nil || settings.overlayStyle == .dimmed
        ZStack {
            OverlayBackground(settings: settings, backgroundPath: backgroundPath)
            BreakPresentationLayout {
                VStack(spacing: 13) {
                    Text(kind.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(2.4)
                        .opacity(0.82)
                    Text(content.text)
                        .font(.system(size: 24 * settings.textScale, weight: .medium))
                        .multilineTextAlignment(.center)
                    if settings.showCountdown {
                        Text(formattedCountdown(settings.duration(for: kind)))
                            .font(.system(size: 22 * settings.textScale, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .opacity(0.86)
                    }
                    if let path = content.imagePath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(maxWidth: 200 * settings.imageScale, maxHeight: 80 * settings.imageScale)
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(usesLightText ? 0.18 : 0), radius: 10, y: 2)

                ViewThatFits(in: .horizontal) {
                    previewActions(
                        usesLightText: usesLightText,
                        stacksVertically: false
                    )
                    previewActions(
                        usesLightText: usesLightText,
                        stacksVertically: true
                    )
                }
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(
            usesLightText
                ? Color.white.opacity(0.94)
                : Color(red: 0.16, green: 0.17, blue: 0.18)
        )
    }

    private var previewSkipAction: (() -> Void)? {
        guard settings.showSkipButton else { return nil }
        return {}
    }

    private func previewActions(
        usesLightText: Bool,
        stacksVertically: Bool
    ) -> some View {
        OverlayActionRow(
            usesLightText: usesLightText,
            controlSize: .compact,
            snoozeAction: {},
            secondaryTitle: settings.showSkipButton ? "跳过这次休息" : nil,
            secondarySystemImage: settings.showSkipButton ? "forward.end" : nil,
            secondaryAction: previewSkipAction,
            enablesEscapeShortcut: false,
            stacksVertically: stacksVertically
        )
    }
}
