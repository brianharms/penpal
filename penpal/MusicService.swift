import MediaPlayer
import UIKit

class MusicService {
    static let shared = MusicService()

    private let player = MPMusicPlayerController.systemMusicPlayer

    func execute(action: String) -> String {
        switch action.lowercased() {
        case "play", "resume":
            player.play()
            return "playing"
        case "pause", "stop":
            player.pause()
            return "paused"
        case "skip", "next":
            player.skipToNextItem()
            return "skipped"
        case "previous", "back":
            player.skipToPreviousItem()
            return "going back"
        default:
            return "unknown music action"
        }
    }
}
