// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import AVKit
import Foundation

#if !os(watchOS)

@MainActor
public final class VideoPlayerView: _PlatformBaseView {
    // MARK: Configuration

    /// `.resizeAspectFill` by default.
    public var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    /// `true` by default. If disabled, will only play a video once.
    public var isLooping = true {
        didSet {
            guard isLooping != oldValue else { return }
            player?.actionAtItemEnd = isLooping ? .none : .pause
            if isLooping, !(player?.nowPlaying ?? false) {
                restart()
            }
        }
    }

    /// Add if you want to do something at the end of the video
    var onVideoFinished: (() -> Void)?

    // MARK: Initialization
#if !os(macOS)
    override public class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        (layer as? AVPlayerLayer) ?? AVPlayerLayer() // The right side should never happen
    }
#else
    public let playerLayer = AVPlayerLayer()

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Creating a view backed by a custom layer on macOS is ... hard
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.frame = bounds
    }

    override public func layout() {
        super.layout()

        playerLayer.frame = bounds
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
#endif

    // MARK: Private

    private var player: AVPlayer? {
        didSet {
            registerNotifications()
        }
    }

    private var playerObserver: AnyObject?

    public func reset() {
        playerLayer.player = nil
        player = nil
        playerObserver = nil
    }

    public var asset: AVAsset? {
        didSet { assetDidChange() }
    }

    private func assetDidChange() {
        if asset == nil {
            reset()
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTimeNotification(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )

#if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
#endif
    }

    public func restart() {
        player?.seek(to: CMTime.zero)
        player?.play()
    }

    public func play() {
        guard let asset = asset else {
            return
        }

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = isLooping ? .none : .pause
        self.player = player

        playerLayer.player = player

        playerObserver = player.observe(\.status, options: [.new, .initial]) { player, _ in
            Task { @MainActor in
                if player.status == .readyToPlay {
                    player.play()
                }
            }
        }
    }

    @objc private func playerItemDidPlayToEndTimeNotification(_ notification: Notification) {
        guard let playerItem = notification.object as? AVPlayerItem else {
            return
        }
        if isLooping {
            playerItem.seek(to: CMTime.zero, completionHandler: nil)
        } else {
            onVideoFinished?()
        }
    }

    @objc private func applicationWillEnterForeground() {
        if shouldResumeOnInterruption {
            player?.play()
        }
    }

#if os(iOS) || os(tvOS)
    override public func willMove(toWindow newWindow: UIWindow?) {
        if newWindow != nil && shouldResumeOnInterruption {
            player?.play()
        }
    }
#endif

    private var shouldResumeOnInterruption: Bool {
        return player?.nowPlaying == false &&
        player?.status == .readyToPlay &&
        isLooping
    }
}

extension AVLayerVideoGravity {
    init(_ contentMode: ImageResizingMode) {
        switch contentMode {
        case .aspectFit: self = .resizeAspect
        case .aspectFill: self = .resizeAspectFill
        case .center: self = .resizeAspect
        case .fill: self = .resize
        }
    }
}

@MainActor
extension AVPlayer {
    var nowPlaying: Bool {
        rate != 0 && error == nil
    }
}

#endif
