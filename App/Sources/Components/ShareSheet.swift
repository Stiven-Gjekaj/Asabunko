import SwiftUI
import UIKit

/// A file to share, for a sheet.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The share sheet of iOS: AirDrop, Save to Files, and the apps that open the file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
