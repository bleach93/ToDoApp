//
//  ContentView.swift
//  To Do App
//
//  Created by Jesus Eduardo Soto Tirado on 10/05/26.
//

import SwiftUI
import UserNotifications
import UIKit

// MARK: - MODELO

// Estado de la tarea
enum Estado: String, Codable, CaseIterable {
    case noComenzada
    case enProgreso
    case terminada

    var titulo: String {
        switch self {
        case .noComenzada: return "No comenzada"
        case .enProgreso: return "En progreso"
        case .terminada: return "Terminada"
        }
    }
}

// Prioridad de la tarea
enum Prioridad: String, Codable, CaseIterable {
    case baja
    case media
    case alta

    var color: Color {
        switch self {
        case .baja: return .gray
        case .media: return .yellow
        case .alta: return .red
        }
    }

    var valorOrden: Int {
        switch self {
        case .alta: return 0
        case .media: return 1
        case .baja: return 2
        }
    }
}

// Filtro para mostrar tareas
enum FiltroTareas: String, CaseIterable {
    case todas
    case pendientes
    case enProgreso
    case terminadas

    var titulo: String {
        switch self {
        case .todas: return "Todas"
        case .pendientes: return "Pendientes"
        case .enProgreso: return "En progreso"
        case .terminadas: return "Terminadas"
        }
    }
}

// Orden para organizar tareas
enum OrdenTareas: String, CaseIterable {
    case manual
    case prioridad
    case fecha
    case estado

    var titulo: String {
        switch self {
        case .manual: return "Manual"
        case .prioridad: return "Prioridad"
        case .fecha: return "Fecha"
        case .estado: return "Estado"
        }
    }
}

// Modelo principal
struct Tarea: Identifiable, Equatable, Codable {
    let id: UUID
    var texto: String
    var estado: Estado
    var prioridad: Prioridad
    var fecha: Date?

    init(
        id: UUID = UUID(),
        texto: String,
        estado: Estado = .noComenzada,
        prioridad: Prioridad = .media,
        fecha: Date? = nil
    ) {
        self.id = id
        self.texto = texto
        self.estado = estado
        self.prioridad = prioridad
        self.fecha = fecha
    }
}

// MARK: - VIEWMODEL

final class TareasViewModel: ObservableObject {

    @Published var lista: [Tarea] = [] {
        didSet { guardar() }
    }

    @Published var tarea: String = ""
    @Published var seleccion: Set<UUID> = []
    @Published var mostrarAlertaEliminar = false

    private let key = "tareas_guardadas"

    init() {
        cargar()
    }

    // Haptic feedback
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // Pedir permiso solo cuando se necesite
    func pedirPermisoNotificaciones() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Crear tarea
    func agregarTarea(texto: String, prioridad: Prioridad, fecha: Date?) {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }

        let nueva = Tarea(
            texto: limpio,
            estado: .noComenzada,
            prioridad: prioridad,
            fecha: fecha
        )

        lista.append(nueva)
        programarNotificacion(for: nueva)
        haptic()
    }

    // Editar tarea existente
    func actualizarTarea(_ tareaActualizada: Tarea) {
        guard let index = lista.firstIndex(where: { $0.id == tareaActualizada.id }) else { return }

        lista[index] = tareaActualizada

        // Quito la notificación anterior para no duplicar
        cancelarNotificacion(id: tareaActualizada.id)

        // Programo de nuevo si tiene fecha
        programarNotificacion(for: tareaActualizada)

        haptic(.medium)
    }

    // Cambiar estado de una tarea
    func cambiarEstado(_ item: Tarea) {
        guard let index = lista.firstIndex(where: { $0.id == item.id }) else { return }

        switch lista[index].estado {
        case .noComenzada:
            lista[index].estado = .enProgreso
        case .enProgreso:
            lista[index].estado = .terminada
        case .terminada:
            lista[index].estado = .noComenzada
        }

        haptic()
    }

    // Borrar una tarea
    func borrarTarea(_ item: Tarea) {
        cancelarNotificacion(id: item.id)
        lista.removeAll { $0.id == item.id }
        seleccion.remove(item.id)
        haptic(.medium)
    }

    // Borrar seleccionadas
    func borrarSeleccion() {
        let ids = seleccion.map { $0.uuidString }

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)

        lista.removeAll { seleccion.contains($0.id) }
        seleccion.removeAll()
        haptic(.medium)
    }

    // Cambiar estado en lote
    func cambiarEstadoSeleccionadas(_ estado: Estado) {
        for index in lista.indices {
            if seleccion.contains(lista[index].id) {
                lista[index].estado = estado
            }
        }

        seleccion.removeAll()
        haptic(.medium)
    }

    // Reordenar lista
    func move(from source: IndexSet, to destination: Int) {
        lista.move(fromOffsets: source, toOffset: destination)
        haptic()
    }

    // Guardar local
    private func guardar() {
        if let encoded = try? JSONEncoder().encode(lista) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    // Cargar local
    private func cargar() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Tarea].self, from: data) else { return }

        lista = decoded
    }

    // Programar notificación
    private func programarNotificacion(for tarea: Tarea) {
        guard let fecha = tarea.fecha else { return }

        // No programo fechas pasadas
        guard fecha > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tarea pendiente"
        content.body = tarea.texto
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fecha),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: tarea.id.uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // Cancelar notificación de una tarea
    private func cancelarNotificacion(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    // Título dinámico del alert
    func textoEliminar() -> String {
        return seleccion.count == 1 ? "¿Eliminar tarea?" : "¿Eliminar tareas?"
    }

    // Subtítulo dinámico del alert
    func detalleEliminar() -> String {
        return seleccion.count == 1
        ? "Se eliminará 1 tarea"
        : "Se eliminarán \(seleccion.count) tareas"
    }
}

// MARK: - ROW

struct TareaRowView: View {

    let item: Tarea
    let isSelected: Bool
    let isSelectionMode: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onSelectMultiple: () -> Void
    let onDelete: () -> Void

    private var iconName: String {
        switch item.estado {
        case .noComenzada: return "circle"
        case .enProgreso: return "circle.fill"
        case .terminada: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch item.estado {
        case .noComenzada: return .white.opacity(0.6)
        case .enProgreso: return .blue
        case .terminada: return .green
        }
    }

    private var priorityColor: Color {
        item.prioridad.color
    }

    var body: some View {
        HStack(spacing: 12) {

            RoundedRectangle(cornerRadius: 4)
                .fill(priorityColor)
                .frame(width: 6, height: 34)

            Button(action: onToggle) {
                Image(systemName: iconName)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {

                Text(item.texto)
                    .foregroundColor(item.estado == .terminada ? .white.opacity(0.4) : .white)
                    .strikethrough(item.estado == .terminada)

                HStack(spacing: 8) {
                    Text(item.prioridad.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundColor(priorityColor.opacity(0.9))

                    Text(item.estado.titulo)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }

                if let fecha = item.fecha {
                    Label(fecha.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .white.opacity(0.5))
            } else {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())

        // Si ya hay selección, tap selecciona/deselecciona
        // Si no hay selección, tap edita
        .onTapGesture {
            if isSelectionMode {
                onSelectMultiple()
            } else {
                onEdit()
            }
        }

        // Mantener presionado activa selección
        .onLongPressGesture {
            onSelectMultiple()
        }

        .swipeActions {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

// MARK: - EDITAR TAREA

struct EditarTareaView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var tarea: Tarea
    @State private var usarFecha: Bool

    let onSave: (Tarea) -> Void

    init(tarea: Tarea, onSave: @escaping (Tarea) -> Void) {
        _tarea = State(initialValue: tarea)
        _usarFecha = State(initialValue: tarea.fecha != nil)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {

                Section("Tarea") {
                    TextField("Nombre de la tarea", text: $tarea.texto)
                }

                Section("Prioridad") {
                    Picker("Prioridad", selection: $tarea.prioridad) {
                        ForEach(Prioridad.allCases, id: \.self) { prioridad in
                            Text(prioridad.rawValue.capitalized).tag(prioridad)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Estado") {
                    Picker("Estado", selection: $tarea.estado) {
                        ForEach(Estado.allCases, id: \.self) { estado in
                            Text(estado.titulo).tag(estado)
                        }
                    }
                }

                Section("Recordatorio") {
                    Toggle("Usar fecha", isOn: $usarFecha)

                    if usarFecha {
                        DatePicker(
                            "Fecha",
                            selection: Binding(
                                get: { tarea.fecha ?? Date() },
                                set: { tarea.fecha = $0 }
                            ),
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle("Editar tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        tarea.texto = tarea.texto.trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !tarea.texto.isEmpty else { return }

                        if !usarFecha {
                            tarea.fecha = nil
                        }

                        onSave(tarea)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - SPLASH

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("app_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .shadow(color: .black.opacity(0.4), radius: 20)

                Text("To Do App")
                    .foregroundColor(.white)
                    .font(.largeTitle.bold())
            }
        }
    }
}

// MARK: - CONTENT VIEW

struct ContentView: View {

    @StateObject private var vm = TareasViewModel()

    @State private var showSplash = true
    @State private var fecha: Date = Date()
    @State private var usarFecha: Bool = false
    @State private var prioridad: Prioridad = .media

    @State private var tareaEditando: Tarea?
    @State private var tareaParaEliminar: Tarea?

    @State private var busqueda: String = ""
    @State private var filtro: FiltroTareas = .todas
    @State private var orden: OrdenTareas = .manual

    // Tareas filtradas, buscadas y ordenadas
    private var tareasMostradas: [Tarea] {
        var tareas = vm.lista

        switch filtro {
        case .todas:
            break
        case .pendientes:
            tareas = tareas.filter { $0.estado == .noComenzada }
        case .enProgreso:
            tareas = tareas.filter { $0.estado == .enProgreso }
        case .terminadas:
            tareas = tareas.filter { $0.estado == .terminada }
        }

        if !busqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tareas = tareas.filter {
                $0.texto.localizedCaseInsensitiveContains(busqueda)
            }
        }

        switch orden {
        case .manual:
            break
        case .prioridad:
            tareas.sort { $0.prioridad.valorOrden < $1.prioridad.valorOrden }
        case .fecha:
            tareas.sort {
                ($0.fecha ?? Date.distantFuture) < ($1.fecha ?? Date.distantFuture)
            }
        case .estado:
            tareas.sort { $0.estado.rawValue < $1.estado.rawValue }
        }

        return tareas
    }

    private var totalCompletadas: Int {
        vm.lista.filter { $0.estado == .terminada }.count
    }

    private var porcentajeCompletado: Double {
        guard !vm.lista.isEmpty else { return 0 }
        return Double(totalCompletadas) / Double(vm.lista.count)
    }

    var body: some View {
        ZStack {

            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                mainView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSplash = false
                }
            }
        }

        // Alerta para borrar seleccionadas
        .alert(vm.textoEliminar(), isPresented: $vm.mostrarAlertaEliminar) {
            Button("Cancelar", role: .cancel) { }

            Button("Eliminar", role: .destructive) {
                vm.borrarSeleccion()
            }
        } message: {
            Text(vm.detalleEliminar())
        }

        // Alerta para borrar una sola tarea
        .alert("¿Eliminar tarea?", isPresented: Binding(
            get: { tareaParaEliminar != nil },
            set: { if !$0 { tareaParaEliminar = nil } }
        )) {
            Button("Cancelar", role: .cancel) {
                tareaParaEliminar = nil
            }

            Button("Eliminar", role: .destructive) {
                if let tarea = tareaParaEliminar {
                    vm.borrarTarea(tarea)
                    tareaParaEliminar = nil
                }
            }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }

        // Sheet para editar tarea
        .sheet(item: $tareaEditando) { tarea in
            EditarTareaView(tarea: tarea) { tareaActualizada in
                vm.actualizarTarea(tareaActualizada)
            }
        }
    }

    // MARK: MAIN UI

    private var mainView: some View {
        VStack(spacing: 16) {

            headerView

            inputBar

            toolsView

            if vm.lista.isEmpty {
                emptyState
            } else if tareasMostradas.isEmpty {
                noResultsView
            } else {
                listView
            }

            if !vm.seleccion.isEmpty {
                selectionBar
            }
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: HEADER

    private var headerView: some View {
        VStack(spacing: 8) {

            Text("Lista To Do")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            if !vm.lista.isEmpty {
                VStack(spacing: 6) {
                    Text("\(totalCompletadas)/\(vm.lista.count) completadas")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    ProgressView(value: porcentajeCompletado)
                        .tint(.green)
                }
            }

            if !vm.seleccion.isEmpty {
                Text("\(vm.seleccion.count) seleccionada(s)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: INPUT BAR

    private var inputBar: some View {
        VStack(spacing: 10) {

            HStack {

                TextField("Nueva Tarea", text: $vm.tarea)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)

                Button {
                    if usarFecha {
                        vm.pedirPermisoNotificaciones()
                    }

                    vm.agregarTarea(
                        texto: vm.tarea,
                        prioridad: prioridad,
                        fecha: usarFecha ? fecha : nil
                    )

                    vm.tarea = ""
                    usarFecha = false
                    prioridad = .media
                    fecha = Date()

                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
            }

            HStack {

                Menu {
                    Button("Alta 🔴") { prioridad = .alta }
                    Button("Media 🟡") { prioridad = .media }
                    Button("Baja ⚪️") { prioridad = .baja }
                } label: {
                    HStack {
                        Circle()
                            .fill(prioridad.color)
                            .frame(width: 10, height: 10)

                        Text(prioridad.rawValue.capitalized)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button {
                    usarFecha.toggle()

                    if usarFecha {
                        vm.pedirPermisoNotificaciones()
                    }
                } label: {
                    Image(systemName: usarFecha ? "calendar.badge.clock" : "calendar")
                        .foregroundColor(usarFecha ? .blue : .white.opacity(0.6))
                }
            }

            if usarFecha {
                DatePicker(
                    "Fecha",
                    selection: $fecha,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(.blue)
            }
        }
    }

    // MARK: TOOLS

    private var toolsView: some View {
        VStack(spacing: 10) {

            TextField("Buscar tarea", text: $busqueda)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.white)

            Picker("Filtro", selection: $filtro) {
                ForEach(FiltroTareas.allCases, id: \.self) { filtro in
                    Text(filtro.titulo).tag(filtro)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Orden:")
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Menu {
                    ForEach(OrdenTareas.allCases, id: \.self) { orden in
                        Button(orden.titulo) {
                            self.orden = orden
                        }
                    }
                } label: {
                    HStack {
                        Text(orden.titulo)
                        Image(systemName: "chevron.down")
                    }
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: LISTA

    private var listView: some View {
        List {
            ForEach(tareasMostradas) { item in
                TareaRowView(
                    item: item,
                    isSelected: vm.seleccion.contains(item.id),
                    isSelectionMode: !vm.seleccion.isEmpty,

                    onToggle: {
                        vm.cambiarEstado(item)
                    },

                    onEdit: {
                        tareaEditando = item
                    },

                    onSelectMultiple: {
                        vm.seleccion.toggle(item.id)
                    },

                    onDelete: {
                        tareaParaEliminar = item
                    }
                )
            }
            .onMove { source, destination in
                if filtro == .todas && busqueda.isEmpty && orden == .manual {
                    vm.move(from: source, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .toolbar { EditButton() }
    }

    // MARK: SELECTION BAR

    private var selectionBar: some View {
        VStack(spacing: 10) {

            HStack {

                Button {
                    vm.seleccion.removeAll()
                } label: {
                    Text("Cancelar")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    vm.mostrarAlertaEliminar = true
                } label: {
                    Text("Eliminar")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Menu {
                Button("En progreso 🔵") {
                    vm.cambiarEstadoSeleccionadas(.enProgreso)
                }

                Button("Completada 🟢") {
                    vm.cambiarEstadoSeleccionadas(.terminada)
                }

                Button("No comenzada ⚪️") {
                    vm.cambiarEstadoSeleccionadas(.noComenzada)
                }

            } label: {
                Text("Cambiar estado")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }

    // MARK: EMPTY

    private var emptyState: some View {
        VStack(spacing: 12) {

            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.4))

            Text("No tienes tareas")
                .foregroundColor(.white)

            Text("Crea tu primera tarea usando el botón +")
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, 40)
    }

    // MARK: NO RESULTS

    private var noResultsView: some View {
        VStack(spacing: 12) {

            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.4))

            Text("No se encontraron tareas")
                .foregroundColor(.white)

            Text("Cambia el filtro o la búsqueda")
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, 40)
    }
}

// MARK: SET EXTENSION

extension Set {
    mutating func toggle(_ value: Element) {
        if contains(value) {
            remove(value)
        } else {
            insert(value)
        }
    }
}

// MARK: PREVIEW

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
