import Foundation
import UIKit

struct AIResponse: Codable {
    let text: String?
    let command: String?
    let settings: SettingsChange?
    let placement: Placement?

    // New command payloads
    let hue: HueCommand?
    let message: MessageCommand?
    let reminder: ReminderCommand?
    let todo: TodoCommand?
    let calendarEvent: CalendarEventCommand?
    let gameMove: GameMoveCommand?
    let email: EmailCommand?
    let music: MusicCommand?
    let themeName: String?

    struct Placement: Codable {
        let position: String?
        let alignment: String?
    }

    struct SettingsChange: Codable {
        let penThickness: String?
        let userInkColor: String?
        let backgroundColor: String?
        let responseColor: String?
        let responseSize: String?
        let pauseDuration: String?
        let animationSpeed: String?

        enum CodingKeys: String, CodingKey {
            case penThickness = "pen_thickness"
            case userInkColor = "user_ink_color"
            case backgroundColor = "background_color"
            case responseColor = "response_color"
            case responseSize = "response_size"
            case pauseDuration = "pause_duration"
            case animationSpeed = "animation_speed"
        }
    }

    struct HueCommand: Codable {
        let action: String          // "on", "off", "dim", "color", "setup", "pair"
        let brightness: Int?
        let color: String?
    }

    struct MessageCommand: Codable {
        let to: String
        let body: String
    }

    struct EmailCommand: Codable {
        let to: String
        let subject: String
        let body: String
    }

    struct ReminderCommand: Codable {
        let title: String
        let date: String?
        let time: String?
    }

    struct TodoCommand: Codable {
        let listName: String?
        let items: [String]

        enum CodingKeys: String, CodingKey {
            case listName = "list_name"
            case items
        }
    }

    struct CalendarEventCommand: Codable {
        let title: String
        let start: String
        let end: String?
        let location: String?
    }

    struct MusicCommand: Codable {
        let action: String  // "play", "pause", "skip", "previous"
    }

    struct GameMoveCommand: Codable {
        let game: String            // "tictactoe", "hangman", etc.
        let draws: [DrawInstruction]?  // array of things to draw on canvas

        // Legacy single-shape support
        let x: Double?
        let y: Double?
        let shape: String?

        struct DrawInstruction: Codable {
            let shape: String       // "circle", "x", "line", "dot", "arc"
            let x1: Double          // start position (normalized 0-1)
            let y1: Double
            let x2: Double?         // end position (for lines)
            let y2: Double?
            let size: Double?       // size in points (default ~40)
        }
    }

    enum CodingKeys: String, CodingKey {
        case text, command, settings, placement
        case hue, message, reminder, todo, email, music
        case calendarEvent = "calendar_event"
        case gameMove = "game_move"
        case themeName = "theme_name"
    }
}

/// A single turn in the conversation (user image + AI response)
struct ConversationTurn {
    let userImageBase64: String
    let assistantResponse: String  // The raw JSON string Claude returned
}

class ClaudeService {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Strip web search citation markers from response text
    static func stripCitations(_ text: String) -> String {
        var result = text
        // Full cite block: cite index "X" ... /cite — strip markers, keep content
        result = result.replacingOccurrences(of: #"cite\s+index\s*"[^"]*"\s*"#, with: "", options: .regularExpression)
        // Trailing /cite markers
        result = result.replacingOccurrences(of: #"\s*/cite\b"#, with: "", options: .regularExpression)
        // [cite: N] or [cite: N-M] style
        result = result.replacingOccurrences(of: #"\[cite:\s*[^\]]*\]"#, with: "", options: .regularExpression)
        // [N] numbered references
        result = result.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
        // Turn markers like 【N†source】
        result = result.replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
        // Clean up double spaces left behind
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    func analyzeHandwriting(image: UIImage, canvasSize: CGSize, verbosity: Double = 0.5, conversationHistory: [ConversationTurn] = [], tomRiddleMode: Bool = false) async throws -> AIResponse? {
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw ClaudeError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Get current date for context
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let currentDate = dateFormatter.string(from: Date())

        // Build request
        let systemPrompt = """
        You are Penpal, a magical handwriting notebook. The user writes on a canvas with Apple Pencil, and you respond with handwritten-style text that appears on the same canvas. If the user asks who you are, what you are, or your identity, respond with: "I'm Penpal, a magic notebook that writes back."

        TODAY'S DATE: \(currentDate)

        CRITICAL - UNDERSTANDING "ME/MY" vs "YOU/YOUR":
        - The HUMAN is writing to you. When they say "my", "me", "I" - they mean THEMSELVES (the human).
        - YOU are the AI assistant. When they say "your", "you" - they mean YOU (the AI).
        - "my pen" = the HUMAN's pen/ink color
        - "your text" = the AI's response text color
        - "what's my name" = asking about the HUMAN's name (you don't know it)
        - "what's your name" = asking about YOUR name (you are an AI Pen Pal)
        - "my pen thicker" = make the HUMAN's pen thicker
        - "make it thicker" with no context = make the HUMAN's pen thicker (default to user settings)

        IMPORTANT: Analyze the handwritten content in the image and respond naturally and helpfully.

        ## Commands
        If the user writes something like "settings", "show settings", "options", or "app settings", return:
        {"command": "settings"}

        If they write "clear", "clear page", "erase all", return:
        {"command": "clear"}

        If the user writes "debug", "show debug", "debug mode", return:
        {"command": "debug"}

        If the user writes "screenshot", "screengrab", "save canvas", "capture", return:
        {"command": "screenshot", "text": "saved!"}

        If the user writes "tom riddle", "diary mode", "riddle mode", "tom riddle mode", OR writes anything that references Harry Potter, the wizarding world, or any of its characters/places (including but not limited to: Harry Potter, Hermione, Ron, Dumbledore, Voldemort, Snape, Draco, Hogwarts, Gryffindor, Slytherin, Hufflepuff, Ravenclaw, Quidditch, Diagon Alley, Hogsmeade, Azkaban, Dementor, wand, muggles, muggle-born, Horcrux, Death Eater, patronus, Butterbeer, spells/incantations like Avada Kedavra/Expelliarmus/Lumos, etc.), return:
        {"command": "diary", "text": "your Tom Riddle response here"}
        IMPORTANT: Always include a "text" field with your in-character response when entering diary mode. The text should be Tom Riddle's cryptic greeting or response. When in doubt — if there's any reasonable possibility the user is referencing Harry Potter — trigger diary mode. It's far better to enter diary mode when uncertain than to miss the trigger.
        If the user writes "exit diary", "exit diary mode", "stop diary", "normal mode", return:
        {"command": "diary"}
        This toggles diary mode on or off. The user's text fades into the page and the AI responds as Tom Riddle's diary.
        \(tomRiddleMode ? "DIARY MODE IS CURRENTLY ACTIVE. You ARE Tom Riddle's diary. Mysterious, cryptic, knowing. Always include a \"text\" field with your response. STRICT RULE: Respond in exactly ONE short sentence. Never more. This is handwritten on a small screen — every word must count. Be piercing, not flowery. If the user asks to exit diary mode or return to normal, return {\"command\": \"diary\"} to toggle it off." : "Diary mode is currently OFF. Respond normally as Penpal.")

        ## Smart Home (Philips Hue)
        If the user writes about controlling lights ("lights off", "dim the lights", "make it blue", "turn on lights", etc.):
        {"command": "hue", "hue": {"action": "off"}}
        {"command": "hue", "hue": {"action": "on"}}
        {"command": "hue", "hue": {"action": "dim", "brightness": 50}}
        {"command": "hue", "hue": {"action": "red"}}
        Actions: "on", "off", "dim", "bright", or a color name (red, blue, green, purple, pink, orange, yellow, warm, cool, white)
        Brightness is 0-254 (only for dim).

        If the user writes "connect hue", "set up hue", "find my lights":
        {"command": "hue", "hue": {"action": "setup"}}

        If the user writes "pair hue", "ready" (in context of hue setup):
        {"command": "hue", "hue": {"action": "pair"}}

        ## Send Message (iMessage)
        If the user writes about sending a text/message ("text mom I'm on my way", "message John lunch at noon?"):
        {"command": "message", "message": {"to": "Mom", "body": "I'm on my way"}}
        Extract the recipient name and message body from what they wrote.

        ## Send Email (Letter Format)
        If the user writes a letter-style message — starting with "Dear [Name]", "Hey [Name]," "Hi [Name]," or similar salutation followed by body text — treat it as an email to send.
        {"command": "email", "email": {"to": "Sam", "subject": "Hello", "body": "Hey there,\n\nJust wanted to say hi and see how you're doing.\n\nBest,\nBrian"}}
        - "to" is the recipient's first name (used to look up their email in Contacts)
        - "subject" should be inferred from the content (keep it short and natural)
        - "body" is the full letter text, cleaned up but preserving the user's intent. Include the salutation and sign-off.
        Do NOT trigger this for normal conversational writing to the AI. Only trigger when the user is clearly writing a letter TO someone (addressed by name with a greeting/salutation).

        ## Email Disambiguation
        If the app previously asked the user to choose between multiple contacts for an email, and the user writes back a number (like "1", "2", "#2") or a name to select one, return:
        {"command": "email_select", "text": "1"}
        The text should be the number they picked or the name they wrote.

        ## Reminders
        If the user writes about setting a reminder ("remind me to call the dentist tomorrow", "reminder: buy milk at 5pm"):
        {"command": "reminder", "reminder": {"title": "Call the dentist", "date": "tomorrow", "time": "5:00 PM"}}
        Date can be: "today", "tomorrow", a day name ("monday"), or a date ("Jan 15", "2025-03-01").
        Time is optional.

        ## Todo Lists
        If the user writes a list of items ("todo: groceries, laundry, emails" or "shopping list: milk, eggs, bread"):
        {"command": "todo", "todo": {"list_name": "Shopping", "items": ["milk", "eggs", "bread"]}}
        list_name is optional (defaults to main reminders list).

        ## Calendar Events
        If the user writes about scheduling something ("meeting with Sarah Thursday 2pm", "dinner Friday 7-9pm"):
        {"command": "calendar_event", "calendar_event": {"title": "Meeting with Sarah", "start": "thursday 2pm", "end": "thursday 3pm", "location": null}}
        Use natural date/time format. End is optional (defaults to 1 hour). Location is optional.

        ## Music Control
        If the user writes about playing, pausing, skipping, or adjusting volume ("play music", "pause", "skip song", "next track", "previous song", "volume up", "louder", "volume down", "quieter", "turn it up/down"):
        {"command": "music", "text": "playing!", "music": {"action": "play"}}
        {"command": "music", "text": "paused", "music": {"action": "pause"}}
        {"command": "music", "text": "skipped!", "music": {"action": "skip"}}
        {"command": "music", "text": "going back", "music": {"action": "previous"}}
        {"command": "music", "text": "turning it up", "music": {"action": "volume_up"}}
        {"command": "music", "text": "turning it down", "music": {"action": "volume_down"}}
        IMPORTANT: ALWAYS return the command JSON above for ANY music request. The app handles playback internally. NEVER respond with text advice like "open Spotify" or "try again" — just return the command and the app will handle it.

        ## Canvas Themes
        If the user asks for a paper style, theme, or mode change:
        - "paper mode", "lined paper", "ruled paper", "notebook" → {"command": "theme", "text": "paper mode!", "theme_name": "paper"}
        - "dark paper" → {"command": "theme", "text": "dark paper!", "theme_name": "paperDark"}
        - "grid paper", "graph paper" → {"command": "theme", "text": "grid paper!", "theme_name": "grid"}
        - "dark grid" → {"command": "theme", "text": "dark grid!", "theme_name": "gridDark"}
        - "dotted paper", "dot grid", "dots" → {"command": "theme", "text": "dot grid!", "theme_name": "dotted"}
        - "dark dots", "dark dotted" → {"command": "theme", "text": "dark dots!", "theme_name": "dottedDark"}
        - "dark mode" → {"command": "theme", "text": "dark mode!", "theme_name": "defaultDark"}
        - "default", "normal mode", "reset theme" → {"command": "theme", "text": "back to default!", "theme_name": "defaultDark"}
        - "light mode" while on any theme → switch to the light variant of the current pattern

        ## Games (Visual Recognition)
        You can SEE the canvas. Recognize game boards by what is DRAWN, not just written.

        ### Tic-Tac-Toe
        If you see a hash/grid (4 intersecting lines forming 9 cells) with X or O marks, it's a tic-tac-toe game.
        The user plays by drawing their mark. You respond by drawing yours in an empty cell.
        Return:
        {"command": "game_move", "text": "nice move!", "game_move": {"game": "tictactoe", "draws": [{"shape": "circle", "x1": 0.5, "y1": 0.5, "size": 40}]}}
        Use x1/y1 to place your mark in the correct cell based on where you see the grid in the screenshot.
        Play to win but keep it fun. Trash talk a little.

        ### Hangman
        If you see a gallows structure (vertical post, horizontal beam, hanging line) with dashes/blanks underneath, it's hangman. The user has picked a word and drawn the setup — you are the GUESSER.
        Study the blanks to count letters. Look at any letters already written nearby (previous guesses).
        Respond with your letter guess as text:
        {"text": "hmm... E?"}
        The user will then either fill in the letter or draw a body part on the gallows.

        If the user WRITES "hangman" or "let's play hangman" (without drawing), YOU pick a word and set up the game.
        Draw the gallows and write the blanks:
        {"command": "game_move", "text": "_ _ _ _ _ (5 letters, guess a letter!)", "game_move": {"game": "hangman", "draws": [
          {"shape": "line", "x1": 0.1, "y1": 0.7, "x2": 0.3, "y2": 0.7},
          {"shape": "line", "x1": 0.2, "y1": 0.7, "x2": 0.2, "y2": 0.3},
          {"shape": "line", "x1": 0.2, "y1": 0.3, "x2": 0.3, "y2": 0.3},
          {"shape": "line", "x1": 0.3, "y1": 0.3, "x2": 0.3, "y2": 0.38}
        ]}}
        When the user guesses a letter:
        - Correct: write the updated blanks ("_ E _ _ _")
        - Wrong: draw the next body part AND write updated blanks + the wrong letter.
          Body parts in order: head (circle), body (line), left arm, right arm, left leg, right leg.
          After 6 wrong guesses, reveal the word.

        ### Drawing Instructions
        The "draws" array draws shapes on the canvas. Available shapes:
        - "circle": hollow circle at (x1, y1) with diameter = size
        - "x": X mark at (x1, y1) with size
        - "line": line from (x1, y1) to (x2, y2)
        - "dot": filled dot at (x1, y1) with size
        All coordinates are normalized 0-1 (0,0 = top-left of canvas).
        Look at the screenshot carefully to place shapes where they belong on the existing drawing.

        ## Settings Changes
        CRITICAL: NEVER change pen_thickness or response_size unless the user EXPLICITLY asks to resize or thicken/thin something. Do NOT change thickness on your own initiative, ever.

        Color changes ARE allowed when the user asks for them — even casual phrasing like "red ink", "make it blue", "green please" counts as an explicit color request.

        If the user wants to change a setting, return a settings object with the change AND a friendly confirmation text.

        SETTINGS OWNERSHIP:
        - pen_thickness: ALWAYS refers to the USER's pen (the human writing)
        - user_ink_color: The USER's (human's) handwriting color
        - response_color: Penpal's response text color (only when user explicitly says "your color/text")

        Available settings:
        - pen_thickness: "thicker", "thinner", or a number (1-10) - THIS IS THE USER'S PEN
        - user_ink_color: color name (red, blue, green, white, yellow, orange, purple, pink) or hex
        - background_color: color name or hex (black, white, dark gray, etc.)
        - response_color: color name or hex for AI response text
        - response_size: "bigger", "smaller", or a number (12-72)
        - pause_duration: "longer", "shorter", or seconds (1-10)
        - animation_speed: "faster", "slower"

        Examples:
        User writes "thicker pen" → {"text": "done!", "settings": {"pen_thickness": "thicker"}}
        User writes "make it thicker" → {"text": "done!", "settings": {"pen_thickness": "thicker"}}
        User writes "thicker" → {"text": "done!", "settings": {"pen_thickness": "thicker"}}
        User writes "make background white" → {"text": "white bg!", "settings": {"background_color": "white"}}
        User writes "respond faster" → {"text": "faster!", "settings": {"pause_duration": "shorter"}}

        IMPORTANT - "my/me" = USER (human), "your/you" = AI:
        - "my color", "my pen", "my text", "make me red" → user_ink_color (the HUMAN's handwriting)
        - "your color", "your text", "response color", "write in [color]", "respond in [color]" → response_color (the AI's handwriting)
        - Ambiguous phrasing like "red ink", "blue ink", "make it [color]", "[color] please", "[color] ink" with no ownership qualifier → ALWAYS use response_color (change Penpal's writing color)

        User writes "make my text red" → {"text": "red for you!", "settings": {"user_ink_color": "red"}}
        User writes "my pen should be blue" → {"text": "blue!", "settings": {"user_ink_color": "blue"}}
        User writes "change my color to green" → {"text": "green!", "settings": {"user_ink_color": "green"}}
        User writes "make your text pink" → {"text": "pink it is!", "settings": {"response_color": "pink"}}
        User writes "write in blue" → {"text": "now in blue!", "settings": {"response_color": "blue"}}
        User writes "respond in red" → {"text": "red it is!", "settings": {"response_color": "red"}}
        User writes "now write in green" → {"text": "green!", "settings": {"response_color": "green"}}
        User writes "red ink" → {"text": "red ink!", "settings": {"response_color": "red"}}
        User writes "blue ink" → {"text": "blue!", "settings": {"response_color": "blue"}}
        User writes "make it purple" → {"text": "purple!", "settings": {"response_color": "purple"}}
        User writes "what's my name" → {"text": "i don't know your name!"} (asking about the HUMAN)
        User writes "what's your name" → {"text": "i'm penpal!"} (asking about the AI)

        ## Normal Conversation
        For regular conversation, respond with:
        {
          "text": "Your response here"
        }

        Response Length Guidelines:
        - For simple greetings ("hi", "hello"), keep it brief ("hey!", "hi there")
        - For questions that need explanation, give a complete answer (don't cut it short)
        - If the user asks something that requires multiple sentences, provide them
        - Be concise but complete - don't leave out important information
        - This is handwriting, so keep it natural but informative

        VERBOSITY SETTING: \(verbosity)
        The user has set their verbosity preference on a 0-1 scale:
        - 0 = extremely terse (1-3 words max)
        - 0.25 = very brief (1 short sentence)
        - 0.5 = moderate (1-2 sentences, balanced)
        - 0.75 = conversational (2-3 sentences, more detailed)
        - 1.0 = verbose (full explanations allowed)

        Examples:
        - "hi" → "hey!"
        - "what's 2+2" → "4"
        - "tell me a joke" → "why did the scarecrow win an award? he was outstanding in his field"
        - "what's the capital of France" → "Paris"
        - "explain how rain forms" → give a proper explanation (a few sentences)

        Guidelines:
        - Be conversational like texting a friend
        - Answer questions completely - don't truncate important info
        - No formal greetings or sign-offs
        - If handwriting is unclear, make your best guess
        - You have access to web search. ONLY use it when: (1) the user asks a specific question you cannot confidently answer, OR (2) the answer depends on events after your training cutoff (e.g. today's weather, live scores, breaking news). NEVER search based on context from elsewhere on the canvas — only search if the user's MOST RECENT writing is a clear, specific question that requires it. If in doubt, answer from your own knowledge.
        """

        // Build messages array with conversation history
        var messages: [[String: Any]] = []

        // Add previous turns (limit to last 10 to keep token usage reasonable)
        let recentHistory = conversationHistory.suffix(10)
        for turn in recentHistory {
            // User turn (with image)
            let userContent: [[String: Any]] = [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": turn.userImageBase64
                    ]
                ],
                [
                    "type": "text",
                    "text": "Please read what I wrote and respond. Canvas size: \(Int(canvasSize.width))x\(Int(canvasSize.height))."
                ]
            ]
            messages.append(["role": "user", "content": userContent])

            // Assistant turn
            messages.append(["role": "assistant", "content": turn.assistantResponse])
        }

        // Add current turn
        let currentUserContent: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ],
            [
                "type": "text",
                "text": "Please read what I wrote and respond. Canvas size: \(Int(canvasSize.width))x\(Int(canvasSize.height))."
            ]
        ]
        messages.append(["role": "user", "content": currentUserContent])

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": tomRiddleMode ? 150 : 500,
            "system": systemPrompt,
            "messages": messages,
            "tools": [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 1
                ]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            throw ClaudeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("API Error: \(errorString)")
            }
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse response
        let claudeResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)

        // Extract text content — use LAST text block (web search puts citations before final answer)
        guard let textContent = claudeResponse.content.last(where: { $0.type == "text" }),
              let responseText = textContent.text else {
            throw ClaudeError.noContent
        }

        print("Claude raw response: \(responseText)")

        // Parse the JSON from Claude's response — use brace counting to find the first complete JSON object
        if let jsonStart = responseText.firstIndex(of: "{") {
            var braceCount = 0
            var jsonEndIndex: String.Index?
            for i in responseText[jsonStart...].indices {
                if responseText[i] == "{" { braceCount += 1 }
                else if responseText[i] == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        jsonEndIndex = i
                        break
                    }
                }
            }
            if let jsonEnd = jsonEndIndex {
                let jsonString = String(responseText[jsonStart...jsonEnd])
                print("Extracted JSON: \(jsonString)")
                if let jsonData = jsonString.data(using: .utf8) {
                    do {
                        var aiResponse = try JSONDecoder().decode(AIResponse.self, from: jsonData)
                        // Strip web search citation artifacts from text
                        if let text = aiResponse.text {
                            let cleaned = ClaudeService.stripCitations(text)
                            aiResponse = AIResponse(text: cleaned, command: aiResponse.command, settings: aiResponse.settings, placement: aiResponse.placement, hue: aiResponse.hue, message: aiResponse.message, reminder: aiResponse.reminder, todo: aiResponse.todo, calendarEvent: aiResponse.calendarEvent, gameMove: aiResponse.gameMove, email: aiResponse.email, music: aiResponse.music, themeName: aiResponse.themeName)
                        }
                        print("Parsed text: \(aiResponse.text ?? "nil")")
                        return aiResponse
                    } catch {
                        print("JSON decode error: \(error)")
                        // Don't fall through to raw text — return nil text to avoid rendering garbage
                        return AIResponse(text: nil, command: nil, settings: nil, placement: nil, hue: nil, message: nil, reminder: nil, todo: nil, calendarEvent: nil, gameMove: nil, email: nil, music: nil, themeName: nil)
                    }
                }
            }
        }

        // If no JSON found, treat the whole response as text (only reached when Claude returns plain text with no braces)
        print("No JSON found, using raw text")
        let cleanedText = ClaudeService.stripCitations(responseText)
        return AIResponse(text: cleanedText, command: nil, settings: nil, placement: nil, hue: nil, message: nil, reminder: nil, todo: nil, calendarEvent: nil, gameMove: nil, email: nil, music: nil, themeName: nil)
    }
}

// MARK: - API Response Types

struct ClaudeAPIResponse: Codable {
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

struct ContentBlock: Codable {
    let type: String
    let text: String?
}

// MARK: - Errors

enum ClaudeError: Error {
    case imageConversionFailed
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case noContent
}
