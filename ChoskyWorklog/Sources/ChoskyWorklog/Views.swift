import AppKit
import ApplicationServices
import SwiftUI
import WebKit

enum SidebarDestination: String, CaseIterable, Identifiable {
    case today = "Hoy"
    case active = "Sesión activa"
    case history = "Historial"
    case calendar = "Calendario"
    case clients = "Clientes y proyectos"
    case screenshots = "Capturas"
    case activity = "Actividad"
    case deliverables = "Resultados"
    case reports = "Informes"
    case sharing = "Compartir"
    case privacy = "Privacidad"
    case storage = "Almacenamiento"
    case permissions = "Permisos"
    case diagnostics = "Diagnóstico"
    case settings = "Ajustes"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .active: "timer"
        case .history: "clock.arrow.circlepath"
        case .calendar: "calendar"
        case .clients: "folder"
        case .screenshots: "photo.on.rectangle"
        case .activity: "waveform.path.ecg.rectangle"
        case .deliverables: "checkmark.seal"
        case .reports: "doc.richtext"
        case .sharing: "person.2"
        case .privacy: "hand.raised"
        case .storage: "internaldrive"
        case .permissions: "checkmark.shield"
        case .diagnostics: "stethoscope"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var sessions: SessionManager
    @State private var selection: SidebarDestination? = .today
    @State private var showStart = false

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 225)
            .safeAreaInset(edge: .bottom) {
                sessionControl
                    .padding()
                    .background(.bar)
            }
        } detail: {
            detail
                .navigationTitle(selection?.rawValue ?? ProductConfig.name)
                .toolbar {
                    ToolbarItemGroup {
                        EngineStatusLabel()
                        if sessions.activeSession == nil {
                            Button("Iniciar trabajo", systemImage: "play.fill") {
                                showStart = true
                            }
                            .keyboardShortcut("n", modifiers: [.command])
                        }
                    }
                }
        }
        .sheet(isPresented: $showStart) {
            StartSessionView(isPresented: $showStart)
                .environmentObject(sessions)
        }
        .alert(
            "Atención",
            isPresented: Binding(
                get: { sessions.lastError != nil },
                set: { if !$0 { sessions.clearError() } }
            )
        ) {
            Button("Aceptar") { sessions.clearError() }
        } message: {
            Text(sessions.lastError ?? "")
        }
        .alert(
            "Operación",
            isPresented: Binding(
                get: { model.operationMessage != nil },
                set: { if !$0 { model.operationMessage = nil } }
            )
        ) {
            Button("Aceptar") { model.operationMessage = nil }
        } message: {
            Text(model.operationMessage ?? "")
        }
        .overlay(alignment: .top) {
            if sessions.recoverySession != nil {
                RecoveryBanner()
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .today {
        case .today: TodayView()
        case .active: ActiveSessionView(showStart: $showStart)
        case .history: HistoryView()
        case .calendar: CalendarSummaryView()
        case .clients: ClientsProjectsView()
        case .screenshots: ScreenshotGalleryView()
        case .activity: ActivityWatchPanel()
        case .deliverables: DeliverablesView()
        case .reports: ReportsView()
        case .sharing: SharingView()
        case .privacy: PrivacyView()
        case .storage: StorageView()
        case .permissions: PermissionsView()
        case .diagnostics: DiagnosticsView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private var sessionControl: some View {
        if let active = sessions.activeSession {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: active.state == .running ? "record.circle" : "pause.circle")
                    Text(active.elapsed.worklogDuration)
                        .monospacedDigit()
                        .font(.headline)
                    Spacer()
                }
                HStack {
                    if active.state == .running {
                        Button("Pausar") { sessions.pause() }
                    } else {
                        Button("Reanudar") { sessions.resume() }
                    }
                    Button("Finalizar", role: .destructive) { sessions.finish() }
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button("Iniciar trabajo") { showStart = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }
}

struct EngineStatusLabel: View {
    @EnvironmentObject private var engine: ActivityWatchSupervisor

    var body: some View {
        Label(engine.serverStatus.rawValue, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(engine.serverStatus == .running ? Color.secondary : Color.orange)
            .help("Motor ActivityWatch: \(engine.serverStatus.rawValue)")
    }

    private var symbol: String {
        engine.serverStatus == .running ? "checkmark.circle" : "exclamationmark.triangle"
    }
}

struct RecoveryBanner: View {
    @EnvironmentObject private var sessions: SessionManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
            VStack(alignment: .leading) {
                Text("Sesión incompleta detectada").font(.headline)
                Text("El tiempo desde el cierre no se ha atribuido como actividad.")
                    .font(.caption)
            }
            Spacer()
            Button("Continuar") { sessions.recoverContinue() }
            Button("Finalizar") { sessions.recoverFinish() }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}

struct StartSessionView: View {
    @EnvironmentObject private var sessions: SessionManager
    @Binding var isPresented: Bool
    @State private var clientID: UUID?
    @State private var projectID: UUID?
    @State private var taskID: UUID?
    @State private var description = ""
    @State private var tags = ""
    @State private var billable = true
    @State private var screenshotsEnabled = true
    @State private var initialNote = ""
    @State private var expectedResults = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Iniciar trabajo").font(.largeTitle.bold())
            Form {
                Picker("Cliente", selection: $clientID) {
                    Text("Seleccionar").tag(nil as UUID?)
                    ForEach(sessions.clients) { Text($0.name).tag($0.id as UUID?) }
                }
                Picker("Proyecto", selection: $projectID) {
                    Text("Seleccionar").tag(nil as UUID?)
                    ForEach(sessions.projects(for: clientID)) {
                        Text($0.name).tag($0.id as UUID?)
                    }
                }
                Picker("Tarea", selection: $taskID) {
                    Text("Seleccionar").tag(nil as UUID?)
                    ForEach(sessions.tasks(for: projectID)) {
                        Text($0.name).tag($0.id as UUID?)
                    }
                }
                TextField("Descripción", text: $description, axis: .vertical)
                TextField("Etiquetas separadas por comas", text: $tags)
                Toggle("Trabajo facturable", isOn: $billable)
                Toggle("Capturas aleatorias activadas", isOn: $screenshotsEnabled)
                TextField("Nota inicial", text: $initialNote, axis: .vertical)
                TextField("Resultados esperados", text: $expectedResults, axis: .vertical)
            }
            HStack {
                Spacer()
                Button("Cancelar") { isPresented = false }
                Button("Iniciar trabajo") {
                    guard let clientID, let projectID, let taskID else { return }
                    sessions.start(SessionDraft(
                        clientID: clientID,
                        projectID: projectID,
                        taskID: taskID,
                        description: description,
                        tags: tags.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        },
                        isBillable: billable,
                        hourlyRate: sessions.projects.first(where: { $0.id == projectID })?.hourlyRate,
                        screenshotsEnabled: screenshotsEnabled,
                        initialNote: initialNote,
                        expectedResults: expectedResults
                    ))
                    if sessions.activeSession != nil { isPresented = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(clientID == nil || projectID == nil || taskID == nil)
            }
        }
        .padding(28)
        .frame(width: 620)
        .onAppear {
            clientID = sessions.clients.first?.id
            projectID = sessions.projects(for: clientID).first?.id
            taskID = sessions.tasks(for: projectID).first?.id
        }
        .onChange(of: clientID) {
            projectID = sessions.projects(for: clientID).first?.id
        }
        .onChange(of: projectID) {
            taskID = sessions.tasks(for: projectID).first?.id
            if let projectID,
               let project = sessions.projects.first(where: { $0.id == projectID }) {
                billable = project.isBillable
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TodayView: View {
    @EnvironmentObject private var sessions: SessionManager

    private var todaySessions: [SessionRecord] {
        sessions.sessions.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    MetricTile(
                        title: "Registrado",
                        value: todaySessions.reduce(0) { $0 + $1.elapsed }.worklogDuration,
                        symbol: "clock"
                    )
                    MetricTile(
                        title: "Activo",
                        value: todaySessions.reduce(0) { $0 + $1.activeSeconds }.worklogDuration,
                        symbol: "hand.tap"
                    )
                    MetricTile(
                        title: "AFK",
                        value: todaySessions.reduce(0) { $0 + $1.afkSeconds }.worklogDuration,
                        symbol: "moon"
                    )
                    MetricTile(
                        title: "Pausado",
                        value: todaySessions.reduce(0) { $0 + $1.pausedSeconds }.worklogDuration,
                        symbol: "pause"
                    )
                }
                Text("Sesiones de hoy").font(.title2.bold())
                if todaySessions.isEmpty {
                    ContentUnavailableView(
                        "Todavía no hay sesiones",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Inicia trabajo para registrar tiempo y actividad.")
                    )
                } else {
                    ForEach(todaySessions) { session in
                        SessionRow(session: session)
                    }
                }
                Text("El tiempo activo indica presencia de actividad de entrada; no equivale por sí solo a productividad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject private var sessions: SessionManager
    let session: SessionRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.state == .running ? "record.circle" : "clock")
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.description.isEmpty ? taskName : session.description)
                    .font(.headline)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.elapsed.worklogDuration).monospacedDigit()
            Text(session.state.label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 8)
    }

    private var taskName: String {
        sessions.tasks.first(where: { $0.id == session.taskID })?.name ?? "Sesión"
    }
}

struct ActiveSessionView: View {
    @EnvironmentObject private var sessions: SessionManager
    @Binding var showStart: Bool
    @State private var selectedTask: UUID?

    var body: some View {
        Group {
            if let session = sessions.activeSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        Text(session.elapsed.worklogDuration)
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(session.state.label)
                            .font(.headline)
                        HStack {
                            MetricTile(title: "Activo", value: session.activeSeconds.worklogDuration, symbol: "hand.tap")
                            MetricTile(title: "AFK", value: session.afkSeconds.worklogDuration, symbol: "moon")
                            MetricTile(title: "Pausado", value: session.pausedSeconds.worklogDuration, symbol: "pause")
                            MetricTile(title: "Capturas", value: "\(session.screenshotCount)", symbol: "camera")
                        }
                        Picker("Cambiar de tarea", selection: $selectedTask) {
                            ForEach(sessions.tasks(for: session.projectID)) {
                                Text($0.name).tag($0.id as UUID?)
                            }
                        }
                        .onChange(of: selectedTask) {
                            if let selectedTask, selectedTask != session.taskID {
                                sessions.switchTask(to: selectedTask)
                            }
                        }
                        HStack {
                            if session.state == .running {
                                Button("Pausar", systemImage: "pause.fill") { sessions.pause() }
                                Button("Pausa de privacidad", systemImage: "eye.slash") {
                                    sessions.togglePrivacyPause()
                                }
                            } else {
                                Button("Reanudar", systemImage: "play.fill") { sessions.resume() }
                            }
                            Button("Capturar ahora", systemImage: "camera") {
                                sessions.screenshotService.captureNow()
                            }
                            .disabled(
                                session.state != .running
                                    || !sessions.screenshotService.enabled
                            )
                            Button("Finalizar", systemImage: "stop.fill", role: .destructive) {
                                sessions.finish()
                            }
                        }
                        .buttonStyle(.bordered)
                        if sessions.screenshotService.showApproximateTime,
                           let nextCapture = sessions.screenshotService.nextApproximateCapture {
                            Label(
                                "Próxima captura aproximadamente \(nextCapture.formatted(date: .omitted, time: .shortened))",
                                systemImage: "clock.badge"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(30)
                }
                .onAppear { selectedTask = session.taskID }
            } else {
                ContentUnavailableView {
                    Label("No hay una sesión activa", systemImage: "timer")
                } description: {
                    Text("Selecciona cliente, proyecto y tarea para comenzar.")
                } actions: {
                    Button("Iniciar trabajo") { showStart = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var sessions: SessionManager

    var body: some View {
        List(sessions.sessions) { session in
            SessionRow(session: session)
        }
        .overlay {
            if sessions.sessions.isEmpty {
                ContentUnavailableView("Sin historial", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

struct CalendarSummaryView: View {
    @EnvironmentObject private var sessions: SessionManager
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DatePicker("Día", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .frame(maxWidth: 380)
            Divider()
            let selected = sessions.sessions.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
            Text("\(selected.count) sesiones · \(selected.reduce(0) { $0 + $1.elapsed }.worklogDuration)")
                .font(.title2.bold())
            ForEach(selected) { SessionRow(session: $0) }
            Spacer()
        }
        .padding(28)
    }
}

struct ClientsProjectsView: View {
    @EnvironmentObject private var sessions: SessionManager
    @State private var newClient = ""
    @State private var newProject = ""
    @State private var selectedClient: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Clientes").font(.title2.bold())
                List(sessions.clients, selection: $selectedClient) { client in
                    Label(client.name, systemImage: "person.crop.circle")
                        .tag(client.id)
                }
                HStack {
                    TextField("Nuevo cliente", text: $newClient)
                    Button("Añadir") {
                        sessions.createClient(name: newClient)
                        newClient = ""
                    }
                    .disabled(newClient.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 320)
            VStack(alignment: .leading) {
                Text("Proyectos").font(.title2.bold())
                List(sessions.projects(for: selectedClient)) { project in
                    HStack {
                        Circle().fill(Color(hex: project.color)).frame(width: 10, height: 10)
                        Text(project.name)
                        Spacer()
                        if project.isBillable { Image(systemName: "eurosign.circle") }
                    }
                }
                HStack {
                    TextField("Nuevo proyecto", text: $newProject)
                    Button("Añadir") {
                        guard let selectedClient else { return }
                        sessions.createProject(clientID: selectedClient, name: newProject)
                        newProject = ""
                    }
                    .disabled(selectedClient == nil || newProject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .frame(minWidth: 420)
        }
        .onAppear { selectedClient = sessions.clients.first?.id }
    }
}

struct ScreenshotGalleryView: View {
    @EnvironmentObject private var sessions: SessionManager
    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(sessions.screenshots.filter { $0.deletedAt == nil }) { screenshot in
                    ScreenshotCell(record: screenshot)
                }
            }
            .padding(24)
        }
        .overlay {
            if sessions.screenshots.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView(
                    "No hay capturas",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Solo se realizan durante una sesión activa y nunca con la pantalla bloqueada.")
                )
            }
        }
    }
}

struct ScreenshotCell: View {
    @EnvironmentObject private var sessions: SessionManager
    let record: ScreenshotRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let path = record.thumbnailPath,
                   let image = NSImage(contentsOf: ProductConfig.appSupportURL.appendingPathComponent(path)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary).overlay {
                        Image(systemName: "photo").font(.largeTitle)
                    }
                }
            }
            .frame(height: 145)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(record.capturedAt.formatted(date: .omitted, time: .standard))
                .font(.headline)
            Text(record.activeApplication ?? "Aplicación no disponible")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Mostrar") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        ProductConfig.appSupportURL.appendingPathComponent(record.relativePath)
                    ])
                }
                Spacer()
                Button("Eliminar", role: .destructive) {
                    sessions.deleteScreenshot(record)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ActivityWatchPanel: View {
    @EnvironmentObject private var engine: ActivityWatchSupervisor

    var body: some View {
        Group {
            if engine.serverStatus == .running {
                LocalWebView(url: URL(string: "http://127.0.0.1:\(ProductConfig.activityWatchPort)/")!)
            } else {
                ContentUnavailableView {
                    Label("ActivityWatch no está disponible", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(engine.lastError ?? "El motor local está detenido.")
                } actions: {
                    Button("Reiniciar motor") { engine.restart() }
                }
            }
        }
    }
}

struct LocalWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct DeliverablesView: View {
    @EnvironmentObject private var sessions: SessionManager
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Registrar un resultado").font(.title2.bold())
            TextField("Resultado realizado", text: $title)
            TextField("Detalles, archivos o enlaces", text: $details, axis: .vertical)
                .lineLimit(3...8)
            Button("Añadir resultado") {
                sessions.addDeliverable(title: title, details: details)
                title = ""
                details = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("Los resultados se redactan manualmente. La aplicación no usa IA externa ni inventa entregables.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
    }
}

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Informe mensual").font(.title2.bold())
            Text("Genera simultáneamente PDF, HTML autocontenido, CSV, JSON y ZIP con manifiesto SHA‑256.")
                .foregroundStyle(.secondary)
            Button("Generar informe de este mes", systemImage: "doc.badge.gearshape") {
                model.exportCurrentMonth()
            }
            .buttonStyle(.borderedProminent)
            if let export = model.lastExport {
                GroupBox("Última exportación") {
                    VStack(alignment: .leading, spacing: 10) {
                        FileLink(label: "PDF", url: export.pdf)
                        FileLink(label: "HTML", url: export.html)
                        FileLink(label: "CSV", url: export.csv)
                        FileLink(label: "JSON", url: export.json)
                        FileLink(label: "ZIP", url: export.zip)
                    }
                    .padding(6)
                }
            }
            Spacer()
        }
        .padding(28)
    }
}

struct FileLink: View {
    let label: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(label, systemImage: "doc")
        }
        .buttonStyle(.link)
    }
}

struct SharingView: View {
    @EnvironmentObject private var sharing: SharingServer

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Permitir acceso compartido",
                    isOn: Binding(
                        get: { sharing.masterEnabled },
                        set: { $0 ? sharing.enable() : sharing.revokeAll() }
                    )
                )
                Toggle("Solo este Mac", isOn: $sharing.localOnly)
                    .disabled(sharing.masterEnabled)
                LabeledContent("Estado", value: sharing.status)
                if let expiresAt = sharing.expiresAt {
                    LabeledContent("Caducidad", value: expiresAt.formatted())
                }
                if let url = sharing.shareURL {
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copiar enlace") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
                Button("Revocar todo inmediatamente", role: .destructive) {
                    sharing.revokeAll()
                }
                .disabled(!sharing.masterEnabled)
            } header: {
                Text("Interruptor maestro")
            } footer: {
                Text("Desactivado por defecto. Al revocar se cierran conexiones, se invalida el token y se detiene el listener.")
            }
            Section("Permisos de solo lectura") {
                Toggle("Ver cronómetro", isOn: $sharing.permissions.liveTimer)
                Toggle("Ver resumen de hoy", isOn: $sharing.permissions.todaySummary)
                Toggle("Ver sesiones finalizadas", isOn: $sharing.permissions.finishedSessions)
                Toggle("Ver historial anterior a hoy", isOn: $sharing.permissions.oldHistory)
                Toggle("Ver capturas", isOn: $sharing.permissions.screenshots)
                    .disabled(true)
                Toggle("Ver títulos de ventana", isOn: $sharing.permissions.windowTitles)
                    .disabled(true)
                Toggle("Ver tarifas", isOn: $sharing.permissions.rates)
                    .disabled(true)
                Toggle("Permitir descargas", isOn: $sharing.permissions.downloads)
                    .disabled(true)
                Text("Capturas, títulos, tarifas y descargas todavía no se publican en el panel v0.1.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var sessions: SessionManager
    @EnvironmentObject private var engine: ActivityWatchSupervisor

    var body: some View {
        Form {
            Section("Capturas") {
                Toggle(
                    "Capturas automáticas",
                    isOn: Binding(
                        get: { sessions.screenshotService.enabled },
                        set: { sessions.screenshotService.setEnabled($0) }
                    )
                )
                Toggle(
                    "Mostrar hora aproximada",
                    isOn: Binding(
                        get: { sessions.screenshotService.showApproximateTime },
                        set: { sessions.screenshotService.showApproximateTime = $0 }
                    )
                )
                Stepper(
                    "Intervalo mínimo: \(sessions.screenshotService.minimumMinutes) min",
                    value: Binding(
                        get: { sessions.screenshotService.minimumMinutes },
                        set: { sessions.screenshotService.setMinimumMinutes($0) }
                    ),
                    in: 1...60
                )
                Stepper(
                    "Intervalo máximo: \(sessions.screenshotService.maximumMinutes) min",
                    value: Binding(
                        get: { sessions.screenshotService.maximumMinutes },
                        set: { sessions.screenshotService.setMaximumMinutes($0) }
                    ),
                    in: sessions.screenshotService.minimumMinutes...120
                )
                Button("Saltar siguiente captura") { sessions.screenshotService.skipNext() }
            }
            Section("Seguimiento") {
                Toggle("Modo ActivityWatch continuo", isOn: $engine.continuousMode)
                Text("El modo estricto es el predeterminado: los watchers se detienen fuera de una sesión y durante las pausas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("No se registran teclas concretas, audio, cámara ni OCR. No existe telemetría ni envío externo.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var includeScreenshots = true

    var body: some View {
        Form {
            Section("Datos") {
                LabeledContent("Ruta", value: ProductConfig.appSupportURL.path)
                LabeledContent("Sesiones", value: "\(model.sessions.sessions.count)")
                LabeledContent("Capturas", value: "\(model.sessions.screenshots.count)")
                Button("Abrir en Finder") { NSWorkspace.shared.open(ProductConfig.appSupportURL) }
            }
            Section("Copia de seguridad") {
                Toggle("Incluir capturas", isOn: $includeScreenshots)
                Button("Crear y verificar backup") {
                    model.createBackup(includeScreenshots: includeScreenshots)
                }
                if let backup = model.lastBackup {
                    FileLink(label: backup.archive.lastPathComponent, url: backup.archive)
                    Text("SHA-256: \(backup.checksum)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PermissionsView: View {
    @EnvironmentObject private var sessions: SessionManager
    @State private var screenPermission = CGPreflightScreenCaptureAccess()
    @State private var accessibility = AXIsProcessTrusted()

    var body: some View {
        Form {
            PermissionRow(
                title: "Grabación de pantalla",
                granted: screenPermission,
                detail: "Necesaria únicamente para capturas de evidencia."
            ) {
                screenPermission = sessions.screenshotService.requestPermission()
            }
            PermissionRow(
                title: "Accesibilidad",
                granted: accessibility,
                detail: "Permite a ActivityWatch obtener títulos de ventanas."
            ) {
                accessibility = AXIsProcessTrustedWithOptions(
                    ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                )
            }
            Button("Volver a comprobar") {
                screenPermission = CGPreflightScreenCaptureAccess()
                accessibility = AXIsProcessTrusted()
            }
            Text("Si falta un permiso, el cronómetro sigue funcionando. La aplicación no finge que la captura o los títulos estén disponibles.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(granted ? "Concedido" : "Pendiente")
            } label: {
                Label(title, systemImage: granted ? "checkmark.circle" : "exclamationmark.triangle")
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if !granted { Button("Solicitar permiso", action: action) }
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var engine: ActivityWatchSupervisor
    @EnvironmentObject private var sharing: SharingServer
    @State private var integrity = "Sin comprobar"

    var body: some View {
        Form {
            Section("Aplicación") {
                LabeledContent("Versión", value: ProductConfig.version)
                LabeledContent("Arquitectura", value: SystemArchitecture.current)
                LabeledContent("Base de datos", value: integrity)
                LabeledContent("Ruta de datos", value: ProductConfig.appSupportURL.path)
            }
            Section("Procesos") {
                LabeledContent("Servidor", value: engine.serverStatus.rawValue)
                LabeledContent("PID servidor", value: engine.serverPID.map(String.init) ?? "—")
                LabeledContent("Watchers", value: engine.watcherPIDs.map(String.init).joined(separator: ", ").nilIfEmpty ?? "Detenidos")
                LabeledContent("Puerto", value: "127.0.0.1:\(ProductConfig.activityWatchPort)")
                LabeledContent("Compartición", value: sharing.status)
            }
            Section("Acciones") {
                Button("Comprobar integridad") {
                    integrity = (try? model.database.integrityCheck()) ?? "Error"
                }
                Button("Reiniciar ActivityWatch") { engine.restart() }
                Button("Abrir logs") { NSWorkspace.shared.open(ProductConfig.logsURL) }
                Button("Copiar diagnóstico") {
                    let text = """
                    \(ProductConfig.name) \(ProductConfig.version)
                    Arquitectura: \(SystemArchitecture.current)
                    ActivityWatch: \(engine.serverStatus.rawValue)
                    Watchers: \(engine.watcherStatus.rawValue)
                    Base de datos: \(integrity)
                    Compartición: \(sharing.status)
                    """
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var sessions: SessionManager
    @EnvironmentObject private var engine: ActivityWatchSupervisor

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Producto", value: ProductConfig.name)
                LabeledContent("Identificador", value: ProductConfig.bundleIdentifier)
                LabeledContent("Zona horaria", value: ProductConfig.timezone.identifier)
                LabeledContent("Moneda predeterminada", value: ProductConfig.defaultCurrency)
            }
            Section("ActivityWatch") {
                Toggle("Seguimiento continuo", isOn: $engine.continuousMode)
                Button("Reiniciar motor") { engine.restart() }
            }
            Section("Privacidad") {
                Toggle(
                    "Capturas",
                    isOn: Binding(
                        get: { sessions.screenshotService.enabled },
                        set: { sessions.screenshotService.setEnabled($0) }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 600, minHeight: 420)
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var sessions: SessionManager
    @EnvironmentObject private var engine: ActivityWatchSupervisor
    @EnvironmentObject private var sharing: SharingServer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let session = sessions.activeSession {
                Text(session.elapsed.worklogDuration)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(session.state.label).font(.headline)
                HStack {
                    Label(session.activeSeconds.worklogDuration, systemImage: "hand.tap")
                    Label("\(session.screenshotCount)", systemImage: "camera")
                }
                .font(.caption)
                HStack {
                    if session.state == .running {
                        Button("Pausar") { sessions.pause() }
                    } else {
                        Button("Reanudar") { sessions.resume() }
                    }
                    if session.state == .running || session.state == .privacyPaused {
                        Button("Privacidad") { sessions.togglePrivacyPause() }
                    }
                    Button("Finalizar", role: .destructive) { sessions.finish() }
                }
                Button("Capturar ahora") { sessions.screenshotService.captureNow() }
                    .disabled(
                        session.state != .running
                            || !sessions.screenshotService.enabled
                    )
            } else {
                Text("Sin sesión activa").font(.headline)
                Text("Abre el panel para iniciar trabajo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Label("ActivityWatch: \(engine.serverStatus.rawValue)", systemImage: "waveform.path.ecg")
            Label("Acceso: \(sharing.status)", systemImage: "person.2")
            HStack {
                Button("Abrir panel") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                if sharing.masterEnabled {
                    Button("Revocar acceso", role: .destructive) { sharing.revokeAll() }
                }
            }
            Button("Salir completamente") { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 330)
    }
}

enum SystemArchitecture {
    static var current: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x5E5CE6
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
