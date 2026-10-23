//  MessageComposer.swift
//  ThinkingOfYou/Messages — SwiftUI wrapper for MFMessageComposeViewController.
//
//  Usage (UI), attached once at the root so it works from either mode:
//    .sheet(item: $messages.composer) { draft in
//        MessageComposer(draft: draft) { outcome in messages.composerFinished(outcome) }
//            .ignoresSafeArea()
//    }
//  Present only when `MessageComposer.canSendText()`; MessagesViewModel
//  already falls back to the Messages app (sms: URL) when it can't.

import MessageUI
import SwiftUI
import UIKit

/// How a compose sheet ended (mirrors MessageComposeResult without needing
/// MessageUI in view files).
enum ComposeOutcome: String, Equatable, Sendable {
    case sent
    case cancelled
    case failed
}

/// A message ready for the composer sheet.
struct ComposeDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var recipients: [String]
    var body: String
    /// For the UI (e.g. a title); not used by the composer itself.
    var personName: String?
    var contactID: String?

    init(id: UUID = UUID(), recipients: [String], body: String = "", personName: String? = nil, contactID: String? = nil) {
        self.id = id
        self.recipients = recipients
        self.body = body
        self.personName = personName
        self.contactID = contactID
    }
}

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (ComposeOutcome) -> Void

    init(recipients: [String], body: String = "", onFinish: @escaping (ComposeOutcome) -> Void) {
        self.recipients = recipients
        self.body = body
        self.onFinish = onFinish
    }

    init(draft: ComposeDraft, onFinish: @escaping (ComposeOutcome) -> Void) {
        self.init(recipients: draft.recipients, body: draft.body, onFinish: onFinish)
    }

    /// False on the simulator and on devices with Messages turned off.
    static func canSendText() -> Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard MFMessageComposeViewController.canSendText() else {
            return ComposerUnavailableViewController()
        }
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var onFinish: (ComposeOutcome) -> Void

        init(onFinish: @escaping (ComposeOutcome) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            let outcome: ComposeOutcome
            switch result {
            case .sent: outcome = .sent
            case .failed: outcome = .failed
            case .cancelled: outcome = .cancelled
            @unknown default: outcome = .cancelled
            }
            onFinish(outcome)
        }
    }
}

/// Shown instead of the composer when this device can't send messages.
private final class ComposerUnavailableViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "This device can't send messages.\nTurn on iMessage or SMS in Settings."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }
}
