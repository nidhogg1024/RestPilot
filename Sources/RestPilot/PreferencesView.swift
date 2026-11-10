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
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader
                    pageContent
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: selection == .content ? 760 : 680, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .layoutPriority(1)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(RestPilotTheme.canvas)
        .toggleStyle(SoftSwitchStyle())
        .controlSize(.small)
        .tint(RestPilotTheme.active)
        .onChange(of: settings) { onSave($0) }
        .alert("无法修改开机启动", isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
            Button("好") { launchError = nil }
        } message: { Text(launchError ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsSection.allCases) { section in
                sidebarRow(section)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(width: 172)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        let selected = (selection ?? .general) == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? RestPilotTheme.active : RestPilotTheme.inkSecondary)
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? RestPilotTheme.ink : RestPilotTheme.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(SoftSurface(cornerRadius: 10, shadowRadius: 6).opacity(selected ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selection?.rawValue ?? "设置")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(RestPilotTheme.ink)
            Text(pageSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(RestPilotTheme.inkSecondary)
        }
        .padding(.horizontal, 4)
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
        case .appearance: return "调整休息画面、显示器、声音与菜单栏表现。"
        }
    }

    private var generalPage: some View {
        VStack(spacing: 22) {
            SettingsGroup(title: "启动") {
                SettingsRow(title: "开机自动启动", detail: "登录 Mac 后自动开始运行") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                        .onChange(of: settings.launchAtLogin) { updateLaunchAtLogin($0) }
                }
            }
            SettingsGroup(title: "智能暂停") {
                SettingsRow(title: "锁屏或睡眠时暂停", detail: "返回后从原来的剩余时间继续") {
                    Toggle("", isOn: $settings.pauseWhenLocked).labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "长时间无操作时暂停", detail: "避免离开电脑时仍累计工作时间") {
                    Toggle("", isOn: $settings.pauseWhenIdle).labelsHidden()
                }
                if settings.pauseWhenIdle {
                    RowDivider()
                    SettingsRow(title: "无操作多久算离开") {
                        Picker("无操作阈值", selection: $settings.idleMinutes) {
                            ForEach([1, 3, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                        }
                        .labelsHidden()
                        .controlSize(.regular)
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
                title: "休息欠账",
                footer: "完成或部分完成的休息按实际时长抵扣，离开电脑 15 分钟以上也算休息。欠账隔天清零，自动休息始终可以延后。"
            ) {
                SettingsRow(
                    title: "记录当天欠下的休息",
                    detail: "跳过的时长会累计。欠账多时下一次休息适度延长，跳过需等待 10 秒"
                ) {
                    Toggle("", isOn: $settings.strengthenSkipReminders).labelsHidden()
                }
            }
            if !settings.eyeEnabled && !settings.standEnabled {
                Label("至少启用一种休息计划，否则当前工作周期结束后会自动停止。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(RestPilotTheme.warning)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RestPilotTheme.warningSurface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
        }
    }

    private func planGroup(kind: BreakKind, enabled: Binding<Bool>) -> some View {
        SettingsGroup(
            title: kind.displayName,
            footer: kind == .stand && enabled.wrappedValue
                ? "例如设为 2：眼睛休息、工作、眼睛休息、工作，然后站立休息。"
                : nil
        ) {
            SettingsRow(
                title: kind == .eye ? "提醒我看看远处" : "提醒我站起来活动",
                detail: kind == .eye ? "短暂离开屏幕，缓解眼部疲劳" : "定期起身，活动一下身体"
            ) {
                Toggle("", isOn: enabled).labelsHidden()
            }
            if enabled.wrappedValue {
                RowDivider()
                if kind == .eye {
                    numberRow("每专注多久休息一次", value: $settings.workMinutes, range: 1...180, unit: "分钟")
                    RowDivider()
                    numberRow("每次休息多久", value: $settings.eyeBreakSeconds, range: 5...600, unit: "秒", step: 5)
                } else {
                    numberRow("每几次眼睛休息后站立", value: $settings.standAfterEyeBreaks, range: 1...12, unit: "次")
                    RowDivider()
                    numberRow("每次休息多久", value: $settings.standBreakMinutes, range: 1...30, unit: "分钟")
                }
                RowDivider()
                SettingsRow(title: "看看效果") {
                    softButton("预览") { onPreview(kind, settings) }
                }
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String, step: Int = 1) -> some View {
        SettingsRow(title: title) {
            HStack(spacing: 8) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(RestPilotTheme.ink)
                    .frame(width: 52, height: 28)
                    .background(RestPilotTheme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: value.wrappedValue) { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }
                    .accessibilityLabel(title)
                Text(unit)
                    .font(.system(size: 12.5))
                    .foregroundStyle(RestPilotTheme.inkSecondary)
                    .frame(width: 28, alignment: .leading)
            }
        }
    }

    /// Quiet pill button used for secondary actions inside cards.
    private func softButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(role == .destructive ? RestPilotTheme.warning : RestPilotTheme.ink)
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(RestPilotTheme.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(SoftPressStyle())
    }

    private var contentPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("内容类型", selection: $contentKind) {
                ForEach(BreakKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .frame(width: 220)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("内容库")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(RestPilotTheme.inkSecondary)
                        Spacer()
                        Button { addContent() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RestPilotTheme.ink)
                                .frame(width: 28, height: 28)
                                .background(RestPilotTheme.fill, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(SoftPressStyle())
                        .help("添加内容")
                        .accessibilityLabel("添加内容")
                    }
                    .padding(.horizontal, 4)
                    contentCards
                    Text("拖动卡片排序，图片也可以直接拖到卡片中。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(RestPilotTheme.inkTertiary)
                        .padding(.horizontal, 4)
                    HStack {
                        softButton("恢复默认") { restoreDefaultContents() }
                        Spacer()
                    }
                }
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 360)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("实时预览")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(RestPilotTheme.inkSecondary)
                        Spacer()
                        softButton("全屏预览") { onPreview(contentKind, settings) }
                    }
                    .padding(.horizontal, 4)
                    InlineBreakPreview(kind: contentKind, content: selectedContent, settings: settings)
                }
                .frame(minWidth: 280)
            }
        }
        .onChange(of: contentKind) { _ in selectedContentID = nil }
    }

    @ViewBuilder private var contentCards: some View {
        let binding = contentKind == .eye ? $settings.eyeContents : $settings.standContents
        if binding.wrappedValue.isEmpty {
            SoftCard {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 26))
                        .foregroundStyle(RestPilotTheme.inkTertiary)
                    Text("还没有提示内容")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RestPilotTheme.ink)
                    Text("添加一条文字或图片提示。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(RestPilotTheme.inkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        } else {
            VStack(spacing: 10) {
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
        }
    }

    private func contentCard(binding: Binding<[BreakContent]>, index: Int, item: BreakContent) -> some View {
        let selected = selectedContentID == item.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(RestPilotTheme.inkTertiary)
                Text(item.isEnabled ? "已启用" : "已停用")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.isEnabled ? RestPilotTheme.active : RestPilotTheme.inkTertiary)
                Spacer()
                Toggle("启用这条提示", isOn: binding[index].isEnabled).labelsHidden()
                Menu {
                    Button("复制") { duplicateContent(binding: binding, index: index) }
                    Button("删除", role: .destructive) { deleteContent(binding: binding, index: index) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .tint(RestPilotTheme.inkSecondary)
                    .accessibilityLabel("更多操作")
            }
            TextField("输入休息提示…", text: binding[index].text, axis: .vertical)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(RestPilotTheme.ink)
                .textFieldStyle(.plain)
                .lineLimit(1...4)

            imageDropArea(binding: binding, index: index, item: item)

            HStack(spacing: 8) {
                softButton(item.imagePath == nil ? "添加图片" : "更换图片") { chooseImage(binding: binding, index: index) }
                if item.imagePath != nil {
                    softButton("移除图片", role: .destructive) { binding.wrappedValue[index].imagePath = nil }
                }
                Spacer()
                softButton("预览此条") {
                    selectedContentID = item.id
                    onPreview(contentKind, settingsWithSelectedFirst(item))
                }
            }
        }
        .padding(14)
        .background(SoftSurface(
            stroke: selected ? RestPilotTheme.active.opacity(0.75) : RestPilotTheme.hairline,
            strokeWidth: selected ? 1.5 : 1
        ))
        .contentShape(Rectangle())
        .onTapGesture { selectedContentID = item.id }
    }

    @ViewBuilder private func imageDropArea(binding: Binding<[BreakContent]>, index: Int, item: BreakContent) -> some View {
        if let path = item.imagePath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable().scaledToFill().frame(maxWidth: .infinity, minHeight: 120, maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { handleImageDrop($0, binding: binding, index: index) }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                Text("把图片拖到这里")
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(RestPilotTheme.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RestPilotTheme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { handleImageDrop($0, binding: binding, index: index) }
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 22) {
            SettingsGroup(
                title: "休息画面背景",
                footer: backgroundFooter
            ) {
                segmentedRow("展示方式") {
                    Picker("展示方式", selection: Binding(
                        get: { settings.backgroundMode },
                        set: { settings.backgroundMode = $0 }
                    )) {
                        ForEach(BackgroundMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                if settings.backgroundMode != .none {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 12) {
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
                        HStack(spacing: 8) {
                            softButton(settings.customBackgroundPath == nil ? "导入自定义背景…" : "更换自定义背景…") {
                                chooseBackground()
                            }
                            if settings.customBackgroundPath != nil {
                                softButton("移除自定义", role: .destructive) {
                                    settings.customBackgroundPath = nil
                                    if settings.selectedBackgroundID == "custom" {
                                        settings.selectedBackground = .ambient
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(16)
                    RowDivider()
                    sliderRow("背景暗化", value: Binding(
                        get: { settings.backgroundDim },
                        set: { settings.backgroundDim = $0 }
                    ), in: 0...0.45)
                }
            }
            SettingsGroup(title: "休息画面") {
                segmentedRow("背景样式") {
                    Picker("背景样式", selection: $settings.overlayStyle) {
                        ForEach(OverlayStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                RowDivider()
                SettingsRow(title: "在所有显示器显示", detail: "每块屏幕都会同步显示休息内容") {
                    Toggle("", isOn: $settings.showOnAllDisplays).labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "显示跳过按钮", detail: "允许提前结束当前休息") {
                    Toggle("", isOn: $settings.showSkipButton).labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "柔和进入与退出", detail: "休息画面会平滑淡入和淡出") {
                    Toggle("", isOn: $settings.fadeInOverlay).labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "显示倒计时", detail: "关闭后只展示休息内容") {
                    Toggle("", isOn: $settings.showCountdown).labelsHidden()
                }
                RowDivider()
                sliderRow("色彩浓度", value: $settings.overlayOpacity, in: 0.55...0.98)
                RowDivider()
                sliderRow("文字大小", value: $settings.textScale, in: 0.75...1.35)
                RowDivider()
                sliderRow("图片大小", value: $settings.imageScale, in: 0.6...1.4)
                RowDivider()
                SettingsRow(title: "看看效果") {
                    softButton("预览") { onPreview(.eye, settings) }
                }
            }
            SettingsGroup(title: "菜单栏与声音") {
                SettingsRow(title: "显示剩余时间", detail: "在菜单栏图标旁显示倒计时") {
                    Toggle("", isOn: $settings.showTimeInMenuBar).labelsHidden()
                }
                RowDivider()
                SettingsRow(title: "休息结束播放声音", detail: "使用 macOS 内置提示音") {
                    Toggle("", isOn: $settings.playSoundWhenBreakEnds).labelsHidden()
                }
                if settings.playSoundWhenBreakEnds {
                    RowDivider()
                    SettingsRow(title: "提示音") {
                        HStack(spacing: 8) {
                            Picker("提示音", selection: $settings.endSoundName) {
                                ForEach(["Glass", "Hero", "Ping", "Pop", "Purr", "Submarine"], id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .controlSize(.regular)
                            .frame(width: 120)
                            softButton("试听") { NSSound(named: NSSound.Name(settings.endSoundName))?.play() }
                        }
                    }
                }
            }
        }
    }

    private var backgroundFooter: String? {
        switch settings.backgroundMode {
        case .none: return nil
        case .fixed: return "每块显示器会按自身比例独立裁切，不会拉伸图片。"
        case .random: return "每次休息会从内置背景和自定义背景中随机选择。"
        }
    }

    private func segmentedRow<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
        SettingsRow(title: title) {
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                .frame(width: 270)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        SettingsRow(title: title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range)
                    .frame(width: 190)
                    .accessibilityLabel(title)
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(RestPilotTheme.inkSecondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    private func backgroundTile(title: String, path: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let path, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.90, blue: 0.82),
                                Color(red: 0.87, green: 0.91, blue: 0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? RestPilotTheme.active : RestPilotTheme.hairline, lineWidth: selected ? 2 : 1)
                )
                Text(title)
                    .font(.system(size: 11.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? RestPilotTheme.ink : RestPilotTheme.inkSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chooseBackground() {
        guard let path = ContentFileStore.chooseAndCopyBackground() else { return }
        settings.customBackgroundPath = path
        settings.selectedBackgroundID = "custom"
        settings.backgroundMode = .fixed
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
                VStack(spacing: 0) {
                    BreakKindChip(title: kind.displayName, usesLightText: usesLightText, scale: 0.85)
                    Text(content.text)
                        .font(.system(size: 22 * settings.textScale, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(backgroundPath != nil ? 0.28 : 0), radius: 10, y: 2)
                        .padding(.top, 14)
                    if settings.showCountdown {
                        CountdownPill(
                            time: formattedCountdown(settings.duration(for: kind)),
                            progress: 0.7,
                            usesLightText: usesLightText,
                            scale: 0.7 * settings.textScale
                        )
                        .padding(.top, 18)
                    }
                    if let path = content.imagePath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(maxWidth: 200 * settings.imageScale, maxHeight: 80 * settings.imageScale)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)

                ViewThatFits(in: .horizontal) {
                    previewActions(usesLightText: usesLightText, stacksVertically: false)
                    previewActions(usesLightText: usesLightText, stacksVertically: true)
                }
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RestPilotTheme.hairline, lineWidth: 1)
        )
        .foregroundStyle(
            usesLightText
                ? Color.white.opacity(0.95)
                : RestPilotTheme.overlayInk
        )
    }

    private func previewActions(
        usesLightText: Bool,
        stacksVertically: Bool
    ) -> some View {
        OverlayActionRow(
            usesLightText: usesLightText,
            controlSize: .compact,
            snoozeAction: {},
            secondaryTitle: settings.showSkipButton ? "跳过" : nil,
            secondaryAction: settings.showSkipButton ? {} : nil,
            enablesEscapeShortcut: false,
            stacksVertically: stacksVertically
        )
    }
}
