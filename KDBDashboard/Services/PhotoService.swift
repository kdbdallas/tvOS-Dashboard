import Foundation
import Photos
import UIKit

/// Represents a photo album
struct PhotoAlbum: Identifiable, Equatable {
    let id: String
    let name: String
    let assetCount: Int

    static func == (lhs: PhotoAlbum, rhs: PhotoAlbum) -> Bool {
        lhs.id == rhs.id
    }
}

/// Service for fetching and rotating photos from iCloud Photos library
@MainActor
class PhotoService: ObservableObject {
    @Published var currentPhoto: UIImage?
    @Published var isLoading = false
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var availableAlbums: [PhotoAlbum] = []

    private var allAssets: [PHAsset] = []
    private var displayedAssetIds: Set<String> = []
    private var rotationTask: Task<Void, Never>?

    private let imageManager = PHCachingImageManager()
    private let settingsManager = SettingsManager.shared

    init() {
        checkAuthorizationStatus()
    }

    /// Checks the current photo library authorization status
    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Requests access to the photo library
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status

        if status == .authorized || status == .limited {
            await fetchAvailableAlbums()
            await loadPhotos()
        }
    }

    /// Fetches all available photo albums from the library
    func fetchAvailableAlbums() async {
        isLoading = true
        errorMessage = nil

        var albums: [PhotoAlbum] = []

        // Fetch user-created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )

        userAlbums.enumerateObjects { collection, _, _ in
            let assetFetchOptions = PHFetchOptions()
            assetFetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let assets = PHAsset.fetchAssets(in: collection, options: assetFetchOptions)

            if assets.count > 0 {
                albums.append(PhotoAlbum(
                    id: collection.localIdentifier,
                    name: collection.localizedTitle ?? "Untitled Album",
                    assetCount: assets.count
                ))
            }
        }

        // Fetch smart albums (Camera Roll, Favorites, etc.)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )

        smartAlbums.enumerateObjects { collection, _, _ in
            let assetFetchOptions = PHFetchOptions()
            assetFetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let assets = PHAsset.fetchAssets(in: collection, options: assetFetchOptions)

            if assets.count > 0 {
                albums.append(PhotoAlbum(
                    id: collection.localIdentifier,
                    name: collection.localizedTitle ?? "Untitled Album",
                    assetCount: assets.count
                ))
            }
        }

        // Sort albums by name
        availableAlbums = albums.sorted { $0.name < $1.name }
        isLoading = false
    }

    /// Loads all photos from the selected album or entire library
    func loadPhotos() async {
        isLoading = true
        errorMessage = nil

        // Check if a specific album is selected
        guard let selectedAlbumName = settingsManager.selectedAlbumName else {
            errorMessage = "No album selected. Please select an album in settings."
            isLoading = false
            return
        }

        // Find the album by name
        let albumFetchOptions = PHFetchOptions()
        albumFetchOptions.predicate = NSPredicate(format: "%K == %@", "localizedTitle", selectedAlbumName)

        // Try fetching from regular albums first
        var albumResults = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: albumFetchOptions)

        // If not found in regular albums, try smart albums
        if albumResults.count == 0 {
            albumResults = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: albumFetchOptions)
        }

        // Access the first object, which should be your specific album if it exists
        guard let specificAlbum = albumResults.firstObject else {
            print("No Album Found")
            errorMessage = "Album '\(selectedAlbumName)' not found"
            isLoading = false
            return
        }

        // Now fetch assets within this specific album
        let assetFetchOptions = PHFetchOptions()
        assetFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assetFetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let assetsInAlbum = PHAsset.fetchAssets(in: specificAlbum, options: assetFetchOptions)

        // Convert fetch result to array
        var assets: [PHAsset] = []
        assetsInAlbum.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        allAssets = assets
        displayedAssetIds.removeAll()

        isLoading = false

        if allAssets.isEmpty {
            errorMessage = "No photos found in album '\(selectedAlbumName)'"
        } else {
            await displayRandomPhoto()
        }
    }

    /// Displays a random photo from the library
    func displayRandomPhoto() async {
        guard !allAssets.isEmpty else {
            errorMessage = "No photos available"
            return
        }

        // Reset displayed IDs if we've shown all photos
        if displayedAssetIds.count >= allAssets.count {
            displayedAssetIds.removeAll()
        }

        // Find a photo we haven't displayed yet
        var randomAsset: PHAsset?
        var attempts = 0
        let maxAttempts = allAssets.count

        while randomAsset == nil && attempts < maxAttempts {
            let randomIndex = Int.random(in: 0..<allAssets.count)
            let asset = allAssets[randomIndex]

            if !displayedAssetIds.contains(asset.localIdentifier) {
                randomAsset = asset
                displayedAssetIds.insert(asset.localIdentifier)
            }
            attempts += 1
        }

        // Fallback to any random photo if all have been displayed
        if randomAsset == nil {
            displayedAssetIds.removeAll()
            let randomIndex = Int.random(in: 0..<allAssets.count)
            randomAsset = allAssets[randomIndex]
            displayedAssetIds.insert(randomAsset!.localIdentifier)
        }

        if let asset = randomAsset {
            await loadImage(for: asset)
        }
    }

    /// Loads the full image for a given asset
    private func loadImage(for asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // Allow fetching from iCloud
        options.isSynchronous = false

        // Target size for Apple TV (1920x1080 or 3840x2160 for 4K)
        let targetSize = CGSize(width: 1920, height: 1080)

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                Task { @MainActor in
                    if let image = image {
                        self?.currentPhoto = image
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Starts the automatic photo rotation timer
    func startRotation() {
        // Cancel existing rotation task if any
        rotationTask?.cancel()

        rotationTask = Task {
            // Initial authorization check
            if authorizationStatus == .notDetermined {
                await requestAuthorization()
            } else if authorizationStatus == .authorized || authorizationStatus == .limited {
                if allAssets.isEmpty {
                    await loadPhotos()
                }
            }

            // Rotation loop
            while !Task.isCancelled {
                let interval = settingsManager.photoRotationInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                if !Task.isCancelled && (authorizationStatus == .authorized || authorizationStatus == .limited) {
                    await displayRandomPhoto()
                }
            }
        }
    }

    /// Restarts the rotation timer with updated interval
    func restartRotation() {
        startRotation()
    }

    /// Manually triggers the next photo
    func nextPhoto() {
        Task {
            await displayRandomPhoto()
        }
    }
}
