import Foundation
import UIKit

enum AppLinks {
    static let map: [String: String] = [
        "whatsapp": "whatsapp://", "instagram": "instagram://", "youtube": "youtube://",
        "spotify": "spotify://", "maps": "maps://", "google maps": "comgooglemaps://",
        "phone": "tel://", "messages": "sms://", "mail": "mailto:", "gmail": "googlegmail://",
        "telegram": "tg://", "twitter": "twitter://", "x": "twitter://", "facebook": "fb://",
        "snapchat": "snapchat://", "linkedin": "linkedin://", "netflix": "nflx://",
        "uber": "uber://", "paytm": "paytm://", "google pay": "tez://", "gpay": "tez://",
        "phonepe": "phonepe://", "swiggy": "swiggy://", "zomato": "zomato://",
        "facetime": "facetime://", "music": "music://", "notes": "mobilenotes://",
        "reminders": "x-apple-reminderkit://", "calendar": "calshow://",
        "photos": "photos-redirect://", "files": "shareddocuments://",
        "settings": "app-settings:", "safari": "https://www.google.com",
        "shortcuts": "shortcuts://"
    ]

    static func url(for name: String, raw: String?) -> URL? {
        if let raw, !raw.isEmpty, let u = URL(string: raw) { return u }
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = map[key] ?? map.first(where: { key.contains($0.key) })?.value { return URL(string: s) }
        return nil
    }
}

extension Tools {
    /// Opens a URL / another app. Not possible from inside the widget process.
    static func open(_ url: URL) async -> String {
        #if WIDGET_EXT
        return "Opening apps isn't available from the widget."
        #else
        let ok: Bool = await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { cont.resume(returning: $0) }
            }
        }
        return ok ? "Opened." : "Couldn't open it. The app may not be installed."
        #endif
    }
}
