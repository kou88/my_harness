import SwiftUI

struct AIConversationDetailView: View {
    let id: String
    @Bindable var state: AIChatState
    var body: some View { AIChatScreen(state: state, conversationId: id) }
}
