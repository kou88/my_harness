import SwiftUI

struct AIConversationDetailView: View {
    let id: String
    @Bindable var state: AIChatState
    @Bindable var cronState: AICronState
    var body: some View { AIChatScreen(state: state, cronState: cronState, conversationId: id) }
}
