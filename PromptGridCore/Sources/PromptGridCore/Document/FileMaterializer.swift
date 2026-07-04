//
//  FileMaterializer.swift
//  PromptGridCore
//
//  Downloads iCloud placeholders so their bytes are local before we read them
//  (Specification §11). When a project package lives in an iCloud Drive folder,
//  its image files may be offloaded to the cloud ("dataless" placeholders);
//  reading one returns nothing until it's materialized. For local libraries this
//  is a no-op, so it's safe to call unconditionally.
//
//  These calls block (polling), so run them off the main thread.
//

import Foundation

public enum FileMaterializer {

    /// Ensure a single file's contents are local, downloading from iCloud and
    /// waiting if it's an offloaded placeholder. No-op for non-ubiquitous or
    /// already-downloaded files.
    public static func materialize(_ url: URL, timeout: TimeInterval = 180) {
        guard let values = try? url.resourceValues(
            forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return }        // local file
        if values.ubiquitousItemDownloadingStatus != .notDownloaded { return } // has data already

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus, status != .notDownloaded {
                return
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    /// Materialize every regular file inside a directory (e.g. a `.pgproj`
    /// package) so it can be fully read. No-op for a local package.
    public static func materializeContents(of directory: URL, timeout: TimeInterval = 300) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                materialize(fileURL, timeout: timeout)
            }
        }
    }
}
