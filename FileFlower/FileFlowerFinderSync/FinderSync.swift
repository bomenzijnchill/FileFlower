//
//  FinderSync.swift
//  FileFlowerFinderSync
//
//  Created by Koen Dijkstra on 19/02/2026.
//

import Cocoa
import FinderSync
import UserNotifications

class FinderSync: FIFinderSync {

    override init() {
        super.init()

        NSLog("FileFlower FinderSync launched from %@", Bundle.main.bundlePath as NSString)

        // Watch alle volumes — toolbar/context menu beschikbaar overal in Finder
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Toolbar Item

    override var toolbarItemName: String {
        return "FileFlower"
    }

    override var toolbarItemToolTip: String {
        return "Deploy folder structure template"
    }

    override var toolbarItemImage: NSImage {
        // Laad het custom FileFlower icoon uit de extension bundle
        let bundle = Bundle(for: FinderSync.self)
        if let iconURL = bundle.url(forResource: "toolbar_icon", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            image.isTemplate = true  // Finder past automatisch de juiste kleur toe
            image.size = NSSize(width: 16, height: 16)
            return image
        }
        // Fallback naar SF Symbol als het icoon niet gevonden wordt
        NSLog("FileFlower FinderSync: toolbar_icon.png niet gevonden, gebruik fallback")
        return NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Deploy FileFlower template")!
    }

    // MARK: - Menu Icon

    private var menuIcon: NSImage? {
        let bundle = Bundle(for: FinderSync.self)
        if let iconURL = bundle.url(forResource: "toolbar_icon", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            return image
        }
        return NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        NSLog("FileFlower FinderSync: menu requested for kind: %d", menuKind.rawValue)

        let menu = NSMenu(title: "")

        switch menuKind {
        case .contextualMenuForContainer, .toolbarItemMenu:
            let item = NSMenuItem(
                title: "Deploy folder structure",
                action: #selector(deployAction(_:)),
                keyEquivalent: ""
            )
            item.image = menuIcon
            item.tag = 1 // deploy to current folder
            menu.addItem(item)

        case .contextualMenuForItems:
            let item = NSMenuItem(
                title: "Deploy folder structure",
                action: #selector(deployAction(_:)),
                keyEquivalent: ""
            )
            item.image = menuIcon
            item.tag = 2 // deploy to selected folder
            menu.addItem(item)

        default:
            break
        }

        return menu
    }

    // MARK: - Actions

    @IBAction func deployAction(_ sender: AnyObject?) {
        let menuItem = sender as? NSMenuItem
        let tag = menuItem?.tag ?? 1

        NSLog("FileFlower FinderSync: deployAction triggered, tag: %d", tag)

        if tag == 2 {
            guard let items = FIFinderSyncController.default().selectedItemURLs(),
                  let firstItem = items.first else {
                NSLog("FileFlower FinderSync: No items selected")
                showNotification(title: "FileFlower", message: "Geen map geselecteerd.")
                return
            }

            NSLog("FileFlower FinderSync: Deploying to selected: %@", firstItem.path)
            sendDeployNotification(targetPath: firstItem.path)
        } else {
            guard let targetURL = FIFinderSyncController.default().targetedURL() else {
                NSLog("FileFlower FinderSync: No targeted URL")
                showNotification(title: "FileFlower", message: "Kan de huidige map niet bepalen.")
                return
            }

            NSLog("FileFlower FinderSync: Deploying to current: %@", targetURL.path)
            sendDeployNotification(targetPath: targetURL.path)
        }
    }

    // MARK: - Deploy via Distributed Notification

    private func sendDeployNotification(targetPath: String) {
        NSLog("FileFlower FinderSync: Sending deploy notification for: %@", targetPath)

        // Stuur een distributed notification naar de hoofdapp
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.fileflower.deployTemplate"),
            object: targetPath,
            userInfo: nil,
            deliverImmediately: true
        )

        let folderName = URL(fileURLWithPath: targetPath).lastPathComponent
        showNotification(
            title: "FileFlower",
            message: "Template wordt gedeployed in '\(folderName)'..."
        )
    }

    // MARK: - Notifications

    private func showNotification(title: String, message: String) {
        NSLog("FileFlower FinderSync: Notification: %@ - %@", title, message)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("FinderSync: Notification error: %@", error.localizedDescription)
            }
        }
    }
}
