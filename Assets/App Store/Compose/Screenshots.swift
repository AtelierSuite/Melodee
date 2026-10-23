import AppKit

/// The same screenshots on every device, each from the capture of the same name.
@MainActor
enum Screenshots {
    static let all: [Screenshot] = [
        Screenshot(
            name: "01-library",
            copy: [
                "en": Copy(header: "Your music, your files", caption: "Play straight from your folders"),
                "ja": Copy(header: "音楽を、ファイルのままで", caption: "フォルダからそのまま再生")
            ],
            theme: Palette.nocturne
        ),
        Screenshot(
            name: "02-album",
            copy: [
                "en": Copy(header: "Browse your albums", caption: "With artwork and tags from your files"),
                "ja": Copy(header: "アルバムを美しく", caption: "アートワークもタグもファイルから")
            ],
            theme: Palette.nocturne
        ),
        Screenshot(
            name: "03-now-playing",
            copy: [
                "en": Copy(header: "Front and center", caption: "See what's playing, and what's next"),
                "ja": Copy(header: "再生中を大きく", caption: "次に流れる曲もひと目でわかる")
            ],
            theme: Palette.nocturne
        ),
        Screenshot(
            name: "04-tag-editor",
            copy: [
                "en": Copy(header: "Edit tags in a tap", caption: "Titles, artists, albums, and artwork"),
                "ja": Copy(header: "タグをかんたん編集", caption: "タイトル・アーティスト・アートワークも")
            ],
            theme: Palette.nocturne
        ),
        Screenshot(
            name: "05-playlist",
            copy: [
                "en": Copy(header: "Playlists that travel", caption: "Saved right beside your music"),
                "ja": Copy(header: "持ち歩けるプレイリスト", caption: "音楽と同じフォルダに保存")
            ],
            theme: Palette.nocturne
        ),
        Screenshot(
            name: "06-context-menu",
            copy: [
                "en": Copy(header: "Queue, convert, and more", caption: "Everything is a long press away"),
                "ja": Copy(header: "キューも変換も", caption: "長押しするだけですぐに操作")
            ],
            theme: Palette.nocturne
        )
    ]
}
