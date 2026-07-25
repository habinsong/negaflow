import SwiftUI

struct AppMenuCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        AppStandardMenuCommands(model: model)
        AppWorkflowMenuCommands(model: model)
    }
}
