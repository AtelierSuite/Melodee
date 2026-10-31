//
//  TagInspectorView.swift
//  Melodee
//

import SwiftUI

struct TagInspectorView: View {

    @Bindable var model: TagInspectorModel

    var body: some View {
        Group {
            if model.loadedFiles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TagInspectorForm(model: model)
            }
        }
        .sheet(isPresented: $model.isShowingOnlineLookup) {
            OnlineLookupSheet(files: model.loadedFiles,
                              artist: model.loadedTag.albumArtist ?? model.loadedTag.artist ?? "",
                              album: model.loadedTag.album ?? "") {
                model.didApplyOnlineLookup()
            }
        }
        .alert(MacText.shared("OnlineLookup.SaveFirst"), isPresented: $model.isShowingSaveBeforeOnlineLookup) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        }
        .alert(MacText.shared("TagEditor.SaveFailed.Message"), isPresented: $model.isShowingSaveError) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        }
        .alert(MacText.shared("TagEditor.RemoveAllTags.Failed"), isPresented: $model.isShowingRemoveTagsError) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        }
        .alert(MacText.shared("ExtendedTags.Unsupported"), isPresented: $model.isShowingUnsupportedKeys) {
            Button(MacText.shared("Shared.OK"), role: .cancel) { }
        } message: {
            Text(verbatim: model.unsupportedKeys.joined(separator: ", "))
        }
    }
}
