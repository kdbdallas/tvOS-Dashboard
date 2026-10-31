import SwiftUI
import Photos

/// Displays rotating photos from iCloud Photos library
struct PhotoView: View {
    @ObservedObject var photoService: PhotoService

    var body: some View {
        ZStack {
            // Dark background
            Color.black

            switch photoService.authorizationStatus {
            case .notDetermined:
                authorizationPrompt

            case .restricted, .denied:
                accessDeniedView

            case .authorized, .limited:
                if photoService.isLoading {
                    loadingView
                } else if let image = photoService.currentPhoto {
                    photoContent(image: image)
                } else if let error = photoService.errorMessage {
                    errorView(message: error)
                } else {
                    loadingView
                }

            @unknown default:
                accessDeniedView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var authorizationPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.7))

            Text("Photo Access Required")
                .font(.title2)
                .foregroundColor(.white)

            Text("Grant access to display photos from your iCloud library")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Grant Access") {
                Task {
                    await photoService.requestAuthorization()
                }
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(40)
    }

    private var accessDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Photo Access Denied")
                .font(.title2)
                .foregroundColor(.white)

            Text("Enable photo access in Settings to display your photos")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading photos...")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func photoContent(image: UIImage) -> some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .transition(.opacity.animation(.easeInOut(duration: 1.0)))
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.yellow)

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await photoService.loadPhotos()
                }
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(40)
    }
}

#Preview {
    PhotoView(photoService: PhotoService())
        .frame(height: 400)
        .padding()
}
