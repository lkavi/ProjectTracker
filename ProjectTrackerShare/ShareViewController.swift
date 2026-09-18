import UIKit
import UniformTypeIdentifiers

/// Share-sheet entry point. Takes the first shared text or file, drops it into
/// the App Group inbox and tells the user to open Project Tracker, which shows
/// the import preview when it next becomes active. The extension never parses
/// or writes project data itself, so it stays tiny and cannot corrupt anything.
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
        show(title: "Importing…", message: "Reading what you shared.")
        receive()
    }

    // MARK: - Receiving

    private func receive() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        if let file = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            file.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, _ in
                let data = (item as? URL).flatMap { try? Data(contentsOf: $0) }
                self?.finish(with: data)
            }
        } else if let json = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.json.identifier) }) {
            json.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { [weak self] data, _ in
                self?.finish(with: data)
            }
        } else if let text = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            text.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                let data: Data?
                switch item {
                case let string as String:             data = Data(string.utf8)
                case let attributed as NSAttributedString: data = Data(attributed.string.utf8)
                case let raw as Data:                  data = raw
                default:                               data = nil
                }
                self?.finish(with: data)
            }
        } else {
            show(title: "Nothing to import",
                 message: "Share the assistant's reply as text, or a Project Tracker file.")
        }
    }

    private func finish(with data: Data?) {
        DispatchQueue.main.async {
            guard let data, !data.isEmpty else {
                self.show(title: "Nothing to import",
                          message: "The shared item was empty. Copy the assistant's whole reply and share it again.")
                return
            }
            if SharedInbox.save(data) != nil {
                self.show(title: "Saved",
                          message: "Open Project Tracker to review and finish the import.")
            } else {
                self.show(title: "Couldn't save",
                          message: "Project Tracker's shared storage isn't available on this device.")
            }
        }
    }

    // MARK: - UI

    private func buildLayout() {
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.font = UIFont.systemFont(ofSize: titleLabel.font.pointSize, weight: .bold)
        titleLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, doneButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
    }

    private func show(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
    }

    @objc private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
