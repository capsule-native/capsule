//
//  AppShellView.swift
//  Capsule
//
//  Copyright © 2026 Capsule. All rights reserved.
//
//  The navigational frame: a NavigationSplitView (sidebar | content) with a global health
//  banner pinned above the content, a trailing `.inspector`, and a persistent bottom
//  Activity pane. It binds only to domain models (`SystemStatusModel`, `WorkspaceModel`)
//  and the view-only `ShellState`.

import AppKit
import CapsuleDomain
import SwiftUI

public struct AppShellView: View {
    @Bindable var shell: ShellState
    let systemModel: SystemStatusModel
    let workspaceModel: WorkspaceModel
    @Bindable var browserModel: ContainerBrowserModel
    @Bindable var lifecycleModel: ContainerLifecycleModel
    let statsModel: ContainerStatsModel
    @Bindable var imageBrowserModel: ImageBrowserModel
    @Bindable var imageActionsModel: ImageActionsModel
    let registrySearchModel: RegistrySearchModel
    @Bindable var networkBrowserModel: NetworkBrowserModel
    @Bindable var networkActionsModel: NetworkActionsModel
    @Bindable var machineBrowserModel: MachineBrowserModel
    @Bindable var machineActionsModel: MachineActionsModel
    @Bindable var volumeBrowserModel: VolumeBrowserModel
    let volumeActionsModel: VolumeActionsModel
    @Bindable var taskCenter: TaskCenter
    @Bindable var storageModel: StorageDashboardModel
    @Bindable var serviceLogsModel: LogsModel
    @Bindable var aboutModel: AboutModel
    @Bindable var runModel: RunModel
    @Bindable var buildModel: BuildModel
    @Bindable var logsModel: LogsModel
    @Bindable var copyModel: CopyModel
    let actions: ShellActions
    let terminalSurfaceProvider: any TerminalSurfaceProviding
    let commandContext: CommandContext

    public init(
        shell: ShellState,
        systemModel: SystemStatusModel,
        workspaceModel: WorkspaceModel,
        browserModel: ContainerBrowserModel,
        lifecycleModel: ContainerLifecycleModel,
        statsModel: ContainerStatsModel,
        imageBrowserModel: ImageBrowserModel,
        imageActionsModel: ImageActionsModel,
        registrySearchModel: RegistrySearchModel,
        networkBrowserModel: NetworkBrowserModel,
        networkActionsModel: NetworkActionsModel,
        machineBrowserModel: MachineBrowserModel,
        machineActionsModel: MachineActionsModel,
        volumeBrowserModel: VolumeBrowserModel,
        volumeActionsModel: VolumeActionsModel,
        taskCenter: TaskCenter,
        storageModel: StorageDashboardModel,
        serviceLogsModel: LogsModel,
        aboutModel: AboutModel,
        runModel: RunModel,
        buildModel: BuildModel,
        logsModel: LogsModel,
        copyModel: CopyModel,
        actions: ShellActions,
        terminalSurfaceProvider: any TerminalSurfaceProviding = StubTerminalSurfaceProvider(),
        commandContext: CommandContext
    ) {
        self.shell = shell
        self.systemModel = systemModel
        self.workspaceModel = workspaceModel
        self.browserModel = browserModel
        self.lifecycleModel = lifecycleModel
        self.statsModel = statsModel
        self.imageBrowserModel = imageBrowserModel
        self.imageActionsModel = imageActionsModel
        self.registrySearchModel = registrySearchModel
        self.networkBrowserModel = networkBrowserModel
        self.networkActionsModel = networkActionsModel
        self.machineBrowserModel = machineBrowserModel
        self.machineActionsModel = machineActionsModel
        self.volumeBrowserModel = volumeBrowserModel
        self.volumeActionsModel = volumeActionsModel
        self.taskCenter = taskCenter
        self.storageModel = storageModel
        self.serviceLogsModel = serviceLogsModel
        self.aboutModel = aboutModel
        self.runModel = runModel
        self.buildModel = buildModel
        self.logsModel = logsModel
        self.copyModel = copyModel
        self.actions = actions
        self.terminalSurfaceProvider = terminalSurfaceProvider
        self.commandContext = commandContext
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                shell: shell,
                availableFeatures: systemModel.health.availableFeatures,
                bannerKind: systemModel.health.bannerKind,
                statusLabel: systemModel.health.localizedStatusLabel
            )
        } detail: {
            detailColumn
        }
        .inspector(isPresented: $shell.inspectorPresented) {
            inspectorPanel
        }
        .task {
            await systemModel.refreshStatus()
            commandContext.pluginCatalog.refresh()
            runModel.loadPresets()
            buildModel.loadPresets()
        }
        .onChange(of: systemModel.health.isRunning) { _, isRunning in
            // Plugins require the service; re-discover them the moment it comes up so they
            // surface in the palette/menu without requiring a relaunch.
            if isRunning {
                commandContext.pluginCatalog.refresh()
            }
        }
        .sheet(isPresented: $shell.commandPalettePresented) {
            CommandPaletteView(shell: shell, context: commandContext)
        }
        .sheet(item: $shell.pendingSheet) { intent in
            pendingSheetView(intent)
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            SystemHealthBanner(
                health: systemModel.health,
                compatibilityWarning: systemModel.compatibilityWarning,
                onRecover: actions.recover
            )

            if let notice = lifecycleModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { handleNoticeAction($0) },
                    onForceStop: { id in
                        lifecycleModel.notice = nil
                        // The real destructive escalation for a hung stop: kill (SIGKILL).
                        Task { _ = await lifecycleModel.kill(id: id) }
                    },
                    onDismiss: { lifecycleModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = imageActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in imageActionsModel.notice = nil },
                    onForceStop: { _ in imageActionsModel.notice = nil },
                    onDismiss: { imageActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = networkActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in networkActionsModel.notice = nil },
                    onForceStop: { _ in networkActionsModel.notice = nil },
                    onDismiss: { networkActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = volumeActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in volumeActionsModel.notice = nil },
                    onForceStop: { _ in volumeActionsModel.notice = nil },
                    onDismiss: { volumeActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            if let notice = machineActionsModel.notice {
                LifecycleNoticeView(
                    notice: notice,
                    onAction: { _ in machineActionsModel.notice = nil },
                    onForceStop: { _ in machineActionsModel.notice = nil },
                    onDismiss: { machineActionsModel.notice = nil }
                )
                .padding(.top, 6)
            }

            ContentColumnView(
                section: shell.selection,
                systemTab: $shell.systemTab,
                health: systemModel.health,
                actions: actions,
                browserModel: browserModel,
                lifecycleModel: lifecycleModel,
                statsModel: statsModel,
                imageBrowserModel: imageBrowserModel,
                imageActionsModel: imageActionsModel,
                registrySearchModel: registrySearchModel,
                networkBrowserModel: networkBrowserModel,
                networkActionsModel: networkActionsModel,
                machineBrowserModel: machineBrowserModel,
                machineActionsModel: machineActionsModel,
                volumeBrowserModel: volumeBrowserModel,
                volumeActionsModel: volumeActionsModel,
                storageModel: storageModel,
                serviceLogsModel: serviceLogsModel,
                aboutModel: aboutModel,
                runModel: runModel,
                buildModel: buildModel,
                logsModel: logsModel,
                copyModel: copyModel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shell.activityPanePresented {
                ActivityPaneView(
                    shell: shell,
                    activityLog: shell.activityLog,
                    taskCenter: taskCenter,
                    attachSession: lifecycleModel.attachSession,
                    terminalAvailable: lifecycleModel.isTerminalAvailable,
                    terminalSurfaceProvider: terminalSurfaceProvider,
                    onDetach: { lifecycleModel.detach() },
                    onRetryAttach: { retryAttach() },
                    onOpenShell: { openShellForSelection() },
                    onCloseTerminal: { shell.closeTerminal() },
                    onOpenInTerminalApp: { request in
                        lifecycleModel.openInExternalTerminal(request.argv)
                    }
                )
            }
        }
        .toolbar {
            if sectionSupportsSearch {
                ToolbarItem(placement: .primaryAction) {
                    NativeSearchField(text: searchTextBinding, prompt: searchPrompt)
                        .frame(width: 200)
                        .accessibilityLabel(Text("Search", bundle: .module))
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    shell.toggleActivityPane()
                } label: {
                    Image(systemName: "square.bottomthird.inset.filled")
                }
                .help("Toggle the Activity pane")
                .accessibilityLabel(Text("Toggle activity pane", bundle: .module))

                Button {
                    shell.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle the Inspector")
                .accessibilityLabel(Text("Toggle inspector", bundle: .module))
            }
        }
    }

    /// The inspector is attached to the `NavigationSplitView` itself — not to the detail column —
    /// so it forms a sibling region rather than nesting inside the detail's toolbar host. This
    /// keeps the detail's toolbar items ordered sensibly in the content column (the toggles below
    /// land beside the list actions rather than jumping to the leading edge).
    @ViewBuilder
    private var inspectorPanel: some View {
        Group {
            switch shell.selection {
            case .containers:
                ContainerInspectorView(model: browserModel, stats: statsModel)
            case .images:
                ImageInspectorView(model: imageBrowserModel)
            case .networks:
                NetworkInspectorView(model: networkBrowserModel)
            case .volumes:
                VolumeInspectorView(model: volumeBrowserModel)
            case .machines:
                MachineInspectorView(model: machineBrowserModel, actions: machineActionsModel)
            default:
                InspectorView(section: shell.selection)
            }
        }
        .inspectorColumnWidth(min: 240, ideal: 320, max: 420)
    }

    // MARK: - Search
    //
    // Search is a real `NSSearchField` placed as an ordinary toolbar item (see
    // ``NativeSearchField``) rather than via `.searchable`. On macOS a `.searchable` field is a
    // special trailing element that anchors to the whole window's trailing edge — landing over
    // the inspector and overhanging the content/inspector divider by a dozen-odd points no matter
    // how the inspector is attached or sized. An ordinary toolbar item stays in the content
    // column beside the list actions, so it never straddles the divider.

    /// Only resource surfaces back a filterable list; System (status/logs/about) has nothing to
    /// search, so it gets no field.
    private var sectionSupportsSearch: Bool {
        switch shell.selection {
        case .containers, .images, .volumes, .networks, .machines: return true
        case .system: return false
        }
    }

    /// Routes the single, shell-level search field to the browser model backing the current
    /// section. Each model is the very instance handed down to its list view, so filtering keeps
    /// working unchanged — only the search field itself moved.
    private var searchTextBinding: Binding<String> {
        switch shell.selection {
        case .containers: return $browserModel.searchText
        case .images: return $imageBrowserModel.searchText
        case .volumes: return $volumeBrowserModel.searchText
        case .networks: return $networkBrowserModel.searchText
        case .machines: return $machineBrowserModel.searchText
        case .system: return .constant("")
        }
    }

    private var searchPrompt: String {
        switch shell.selection {
        case .containers: return String(localized: "Search containers", bundle: .module)
        case .images: return String(localized: "Search images", bundle: .module)
        case .volumes: return String(localized: "Search volumes", bundle: .module)
        case .networks: return String(localized: "Search networks", bundle: .module)
        case .machines: return String(localized: "Search machines", bundle: .module)
        case .system: return ""
        }
    }

    /// Routes a notice's recovery action. `.retry` is container-scoped — it refreshes the
    /// container list, never the system status. The `.retryInTerminal` case runs the command
    /// in the embedded terminal.
    private func handleNoticeAction(_ action: RecoveryAction) {
        switch action {
        case .retry:
            lifecycleModel.notice = nil
            Task { await browserModel.refresh() }
        case let .retryInTerminal(command):
            lifecycleModel.runInTerminal(command)
            lifecycleModel.notice = nil
        case .openLogs:
            shell.revealLogs()
            lifecycleModel.notice = nil
        default:
            actions.recover(action)
            lifecycleModel.notice = nil
        }
    }

    /// Re-attaches to the single selected container (the attach console's Retry button).
    private func retryAttach() {
        guard browserModel.selection.count == 1, let id = browserModel.selection.first else {
            return
        }
        lifecycleModel.retryAttach(id: id)
    }

    /// Opens a shell for the single selected container (the attach console's Open Shell).
    private func openShellForSelection() {
        guard browserModel.selection.count == 1, let id = browserModel.selection.first else {
            return
        }
        lifecycleModel.openShell(id: id)
    }

    /// Presents the app-level sheets requested from the palette/menus, reusing the same sheet
    /// views/models the list surfaces use. The caller (the catalog action) preps the model
    /// (e.g. `runModel.reset` / `runModel.apply`) before setting `shell.pendingSheet`.
    @ViewBuilder
    private func pendingSheetView(_ intent: AppSheetIntent) -> some View {
        switch intent {
        case .run:
            QuickRunSheet(
                model: runModel,
                onResolveImage: { _ in shell.present(.pull) },
                onClose: { shell.pendingSheet = nil })
        case .build:
            BuildSheet(model: buildModel, onClose: { shell.pendingSheet = nil })
        case .pull:
            PullImageSheet(
                initialReference: "",
                searchModel: registrySearchModel,
                onPull: { reference, platform in
                    imageActionsModel.pull(reference: reference, platform: platform)
                },
                onRetry: { imageActionsModel.retryTask($0) },
                onClose: { shell.pendingSheet = nil },
                invocationFor: { ref, platform in
                    imageActionsModel.pullInvocation(reference: ref, platform: platform)
                })
        case let .copy(containerID):
            CopySheet(model: copyModel, onClose: { shell.pendingSheet = nil })
                .onAppear { copyModel.reset(containerID: containerID ?? "") }
        case let .export(containerID):
            exportSheet(containerID: containerID)
        case let .console(seed):
            CommandConsoleView(
                seed: seed,
                onRunEmbedded: { request in shell.openTerminal(request) },
                onRunExternal: { argv in lifecycleModel.openInExternalTerminal(argv) },
                onClose: { shell.pendingSheet = nil })
        }
    }

    /// A minimal export prompt: a Save panel feeds `lifecycleModel.export(id:to:)`.
    private func exportSheet(containerID: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Container").font(.headline)
            Text("Export “\(containerID)” to a tar archive on disk.", bundle: .module)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { shell.pendingSheet = nil }
                Button("Choose File…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "\(containerID).tar"
                    panel.canCreateDirectories = true
                    panel.title = "Export Container"
                    let response = panel.runModal()
                    shell.pendingSheet = nil
                    if response == .OK, let url = panel.url {
                        Task { await lifecycleModel.export(id: containerID, to: url) }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

/// A real `NSSearchField` bridged into SwiftUI so it can live as an ordinary toolbar item. We use
/// this instead of `.searchable` because a `.searchable` field on macOS anchors to the window's
/// trailing edge and overhangs the inspector divider (see the note on ``AppShellView``'s search
/// helpers). As a plain toolbar item this stays in the content column, and it keeps the native
/// look and behaviors (rounded field, magnifier, built-in clear button).
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.controlSize = .regular
        // Let the SwiftUI `.frame(width:)` drive the width instead of the intrinsic content size.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
