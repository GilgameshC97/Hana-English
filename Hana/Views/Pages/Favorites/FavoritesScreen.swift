import SwiftUI

struct FavoritesScreen: View {
    var body: some View {
        AccountVideoListScreen(
            kind: .favorites,
            title: "Favorites",
            emptyTitle: "No favorites",
            loginMessage: "Log in to view favorited videos."
        )
    }
}
