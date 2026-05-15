import SwiftUI
import Combine
import AVFoundation

@MainActor
class VisualSearchViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var isSearching = false
    @Published var error: String? = nil
    @Published var imageURL: String = ""

    // Video state
    @Published var serverVideoPath: String = ""
    @Published var videoFeedSaved: Bool = false
    @Published var isUploadingVideo: Bool = false
    @Published var videoUploadError: String? = nil

    var currentCrop: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    private var searchTask: Task<Void, Never>? = nil

    func scheduleSearch(imageData: Data?, feedURL: String?, crop: CGRect, keyword: String, token: String, delay: Double = 0.8) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await performSearch(imageData: imageData, feedURL: feedURL, crop: crop, keyword: keyword, token: token)
        }
    }

    func performSearch(imageData: Data?, feedURL: String?, crop: CGRect, keyword: String, token: String) async {
        isSearching = true
        error = nil

        let cropString = "\(String(format: "%.4f", crop.minX));\(String(format: "%.4f", crop.minY));\(String(format: "%.4f", crop.maxX));\(String(format: "%.4f", crop.maxY))"

        do {
            let response = try await APIService.shared.visualSearch(
                imageData: imageData ?? Data(),
                imageURL: feedURL,
                crop: cropString,
                keyword: keyword.isEmpty ? nil : keyword,
                token: token
            )

            guard !Task.isCancelled else {
                isSearching = false
                return
            }

            if response.ok {
                products = response.products ?? []
                if let url = response.imageUrl {
                    imageURL = url
                }
                error = nil
            } else {
                error = response.error ?? "Search failed."
            }
        } catch is CancellationError {
            isSearching = false
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            isSearching = false
            return
        } catch {
            if products.isEmpty {
                self.error = "Network error. Please try again."
            }
        }

        isSearching = false
    }

    // MARK: - Video frame search

    func scheduleVideoSearch(frameData: Data, crop: CGRect, keyword: String, token: String, delay: Double = 0.8) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await performVideoSearch(frameData: frameData, crop: crop, keyword: keyword, token: token)
        }
    }

    func performVideoSearch(frameData: Data, crop: CGRect, keyword: String, token: String) async {
        isSearching = true
        error = nil

        let cropString = "\(String(format: "%.4f", crop.minX));\(String(format: "%.4f", crop.minY));\(String(format: "%.4f", crop.maxX));\(String(format: "%.4f", crop.maxY))"

        let shouldSaveFeed = !videoFeedSaved && !serverVideoPath.isEmpty

        do {
            let response = try await APIService.shared.visualSearchVideoFrame(
                frameData: frameData,
                videoPath: serverVideoPath.isEmpty ? nil : serverVideoPath,
                crop: cropString,
                keyword: keyword.isEmpty ? nil : keyword,
                saveFeedEntry: shouldSaveFeed,
                token: token
            )

            if response.ok {
                products = response.products ?? []
                if let url = response.imageUrl {
                    imageURL = url
                }
                if shouldSaveFeed {
                    videoFeedSaved = true
                }
            } else {
                error = response.error ?? "Search failed."
            }
        } catch is CancellationError {
            isSearching = false
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            isSearching = false
            return
        } catch {
            if products.isEmpty {
                self.error = "Network error. Please try again."
            }
        }

        isSearching = false
    }

    // MARK: - Upload video to server

    func uploadVideo(videoURL: URL, token: String) async {
        isUploadingVideo = true
        videoUploadError = nil
        serverVideoPath = ""
        videoFeedSaved = false

        do {
            let videoData = try Data(contentsOf: videoURL)
            let filename = videoURL.lastPathComponent.isEmpty ? "video.mp4" : videoURL.lastPathComponent

            let response = try await APIService.shared.uploadVideo(
                videoData: videoData,
                filename: filename,
                token: token
            )

            if response.ok, let path = response.path {
                serverVideoPath = path
            } else {
                videoUploadError = response.error ?? "Video upload failed."
            }
        } catch {
            videoUploadError = "Video could not be uploaded: \(error.localizedDescription)"
        }

        isUploadingVideo = false
    }

    func resetVideoState() {
        serverVideoPath = ""
        videoFeedSaved = false
        videoUploadError = nil
        isUploadingVideo = false
    }
}

// MARK: - Capture a frame from AVPlayer at current time

extension AVPlayer {
    func captureCurrentFrame() async -> UIImage? {
        guard let asset = currentItem?.asset,
              let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let time = currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }

        _ = track
        return UIImage(cgImage: cgImage)
    }
}
