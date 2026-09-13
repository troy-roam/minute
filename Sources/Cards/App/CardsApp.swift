import AppKit
import SwiftUI

@main
struct MinuteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup("minute") {
            ContentView(library: library)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CardsCommands(library: library)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        BundledFonts.register()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CardsCommands: Commands {
    let library: LibraryStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                library.addCard()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Reveal Notes Folder") {
                library.revealNotesFolder()
            }

            Button("Reload Notes from Disk") {
                library.reloadFromDisk()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Button("Find in Notes") {
                NotificationCenter.default.post(name: .focusMinuteSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Copy Card Link") {
                library.copySelectedCardLink()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(library.selectedCard == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Undo Delete Note") {
                library.undoLastDelete()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(library.deletedNoteName == nil)

            Button("Delete Note") {
                library.deleteSelectedCard()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(library.selectedCard == nil)
        }
    }
}
