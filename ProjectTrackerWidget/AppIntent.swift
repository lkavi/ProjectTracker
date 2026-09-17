import WidgetKit
import AppIntents

/// A project the user can pin a widget to, shown in the widget's edit sheet.
/// Backed by the project list the app writes to the App Group.
struct ProjectAppEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Project" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static var defaultQuery = ProjectQuery()
}

struct ProjectQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProjectAppEntity] {
        allProjects().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProjectAppEntity] {
        allProjects()
    }

    private func allProjects() -> [ProjectAppEntity] {
        ProgressStore.loadProjectRefs().map { ProjectAppEntity(id: $0.id, name: $0.name) }
    }
}

/// Widget configuration: which project this widget tracks. Leaving "Project"
/// unset (the default) follows whichever project is currently active in the app.
struct SelectProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Project" }
    static var description: IntentDescription {
        IntentDescription("Choose which project this widget shows. Leave unset to follow the project you're currently working in.")
    }

    @Parameter(title: "Project")
    var project: ProjectAppEntity?
}
