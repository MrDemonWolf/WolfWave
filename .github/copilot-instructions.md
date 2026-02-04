# GitHub Copilot Instructions for WolfWave

This document provides guidelines and examples for GitHub Copilot when assisting with development in the WolfWave project, which is built using SwiftUI and Swift. These instructions ensure consistent, high-quality code that aligns with Apple's best practices and the project's architecture.

## General Guidelines

- **Language**: Use Swift 5.9+ syntax and features.
- **Framework**: Prioritize SwiftUI for UI development, with UIKit only when necessary (e.g., for AppKit integration in macOS apps).
- **Architecture**: Follow MVVM (Model-View-ViewModel) pattern where applicable, especially for complex views.
- **Naming Conventions**: Use camelCase for variables/functions, PascalCase for types/structs/classes.
- **Error Handling**: Use Swift's `Result` type or `throws` for error handling; avoid force unwrapping.
- **Concurrency**: Prefer async/await over DispatchQueue for modern concurrency.
- **Documentation**: Add comments for complex logic; use Swift's documentation syntax (///).

## SwiftUI Examples

### Basic View Structure

When creating a new SwiftUI view, use the following pattern:

```swift
import SwiftUI

struct ContentView: View {
    @State private var isLoading = false

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading...")
            } else {
                Text("Hello, World!")
                    .font(.title)
                    .foregroundColor(.blue)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
```

### State Management

Use `@State`, `@ObservedObject`, or `@EnvironmentObject` appropriately:

```swift
class ViewModel: ObservableObject {
    @Published var items: [String] = []

    func fetchData() async {
        // Simulate network call
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        items = ["Item 1", "Item 2", "Item 3"]
    }
}

struct ListView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        List(viewModel.items, id: \.self) { item in
            Text(item)
        }
        .task {
            await viewModel.fetchData()
        }
    }
}
```

### Navigation

For navigation in SwiftUI apps:

```swift
struct MainView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Button("Go to Detail") {
                    path.append("detail")
                }
            }
            .navigationDestination(for: String.self) { value in
                if value == "detail" {
                    DetailView()
                }
            }
        }
    }
}

struct DetailView: View {
    var body: some View {
        Text("Detail View")
    }
}
```

## Swift Examples

### Structs and Classes

Prefer structs for data models:

```swift
struct User {
    let id: UUID
    var name: String
    var email: String

    init(name: String, email: String) {
        self.id = UUID()
        self.name = name
        self.email = email
    }
}

class UserService {
    func createUser(name: String, email: String) -> User {
        return User(name: name, email: email)
    }
}
```

### Error Handling

Use custom error types:

```swift
enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
}

func fetchUser(id: String) async throws -> User {
    guard let url = URL(string: "https://api.example.com/users/\(id)") else {
        throw NetworkError.invalidURL
    }

    let (data, _) = try await URLSession.shared.data(from: url)

    guard let user = try? JSONDecoder().decode(User.self, from: data) else {
        throw NetworkError.decodingError
    }

    return user
}
```

### Concurrency

Use async/await for asynchronous operations:

```swift
func performAsyncTask() async {
    do {
        let user = try await fetchUser(id: "123")
        print("Fetched user: \(user.name)")
    } catch {
        print("Error: \(error)")
    }
}
```

## Project-Specific Guidelines

- **Twitch Integration**: When working with Twitch API, ensure proper authentication using device code flow as implemented in `TwitchDeviceAuth.swift`.
- **Music Monitoring**: For music playback monitoring, reference `MusicPlaybackMonitor.swift` for system integration.
- **Settings Views**: Follow the pattern in `SettingsView.swift` for creating settings interfaces.
- **WebSocket**: Use modern WebSocket APIs for real-time communication.

## References

- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [Swift Language Guide](https://docs.swift.org/swift-book/LanguageGuide/TheBasics.html)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

When suggesting code, always consider the existing codebase structure and maintain consistency with the project's style and architecture.
