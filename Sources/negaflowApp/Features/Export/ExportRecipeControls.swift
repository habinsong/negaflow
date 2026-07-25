import SwiftUI

struct ExportRecipeControls: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftName = ""
    @State private var isRenaming = false

    private var selectedRecipe: ExportRecipe? {
        model.selectedExportRecipeID.flatMap { id in
            model.exportRecipes.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Picker(model.localizedExportRecipe(.title), selection: $model.selectedExportRecipeID) {
                    Text(model.localizedExportRecipe(.empty)).tag(UUID?.none)
                    ForEach(model.exportRecipes) { recipe in
                        Text(recipe.name).tag(recipe.id as UUID?)
                    }
                }
                .onChange(of: model.selectedExportRecipeID) { _, _ in applySelectedRecipe() }

                Menu {
                    Button(model.localizedExportRecipe(.saveCurrent)) {
                        _ = model.saveCurrentExportRecipe(name: model.nextExportRecipeName())
                        loadDraftName()
                    }

                    if selectedRecipe != nil {
                        Button(model.text(AppLocalizedPhrase.rename)) {
                            isRenaming = true
                            loadDraftName()
                        }

                        Divider()

                        Button(model.text(AppLocalizedPhrase.delete), role: .destructive) {
                            guard let selectedRecipe else { return }
                            model.deleteExportRecipe(selectedRecipe)
                            isRenaming = false
                            loadDraftName()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help(model.localizedExportRecipe(.title))
            }

            if isRenaming {
                HStack(spacing: 6) {
                    TextField(model.localizedExportRecipe(.name), text: $draftName)
                        .onSubmit { renameSelectedRecipe() }

                    Button(model.text(AppLocalizedPhrase.rename)) {
                        renameSelectedRecipe()
                    }
                    .disabled(!canRenameSelectedRecipe)

                    Button {
                        isRenaming = false
                        loadDraftName()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear { loadDraftName() }
    }

    private var canRenameSelectedRecipe: Bool {
        guard let selectedRecipe else { return false }
        return model.canSaveExportRecipeName(draftName, excluding: selectedRecipe.id)
    }

    private func applySelectedRecipe() {
        guard let selectedRecipe else {
            isRenaming = false
            loadDraftName()
            return
        }
        model.applyExportRecipe(selectedRecipe)
        isRenaming = false
        loadDraftName()
    }

    private func loadDraftName() {
        draftName = selectedRecipe?.name ?? model.nextExportRecipeName()
    }

    private func renameSelectedRecipe() {
        guard let selectedRecipe,
              canRenameSelectedRecipe,
              model.renameExportRecipe(selectedRecipe, to: draftName) else {
            loadDraftName()
            return
        }
        isRenaming = false
        loadDraftName()
    }
}
