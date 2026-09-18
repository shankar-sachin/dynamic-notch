import SwiftUI

/// The player. Artwork flies down out of the pill's ear and grows into place.
struct NowPlayingPanel: View {
    let model: NotchViewModel
    var glue: Namespace.ID

    var body: some View {
        if model.mediaAccessDenied {
            VStack(spacing: 9) {
                Image(systemName: "lock.badge.clock")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.32))
                Text("Automation access needed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Dynamic Notch needs permission to ask Music and Spotify what's playing.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                Button("Open Privacy Settings") { model.onRequestMediaAccess?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.16)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let track = model.nowPlaying, !track.isEmpty {
            player(track)
        } else {
            EmptyPanel(
                symbol: "music.note",
                title: "Nothing playing",
                detail: "Start something in Music or Spotify."
            )
        }
    }

    private func player(_ track: NowPlayingSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(image: track.artwork, accent: track.accent, cornerRadius: 10)
                .matchedGeometryEffect(id: "artwork", in: glue, isSource: model.isExpanded)
                .frame(width: 92, height: 92)
                // All the colour the panel gets: a light leak around the art,
                // falling off fast so the body stays black.
                .shadow(color: track.accent.opacity(0.45), radius: 18, y: 4)
                .shadow(color: track.accent.opacity(0.22), radius: 34)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: track.title, font: .system(size: 15, weight: .semibold))
                    .frame(height: 19)

                MarqueeText(
                    text: [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "),
                    font: .system(size: 11.5, weight: .medium),
                    color: .white.opacity(0.52)
                )
                .frame(height: 15)

                Spacer(minLength: 4)

                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let position = track.position(at: context.date)
                    Scrubber(
                        progress: track.duration > 0 ? position / track.duration : 0,
                        elapsed: position,
                        remaining: max(0, track.duration - position),
                        tint: track.accent,
                        onScrub: { fraction in
                            model.onMediaCommand?(.seek(fraction * track.duration))
                        },
                        onScrubStateChange: { model.isInteractionLocked = $0 }
                    )
                }

                transport(track)
                    .padding(.top, 2)
            }
        }
    }

    private func transport(_ track: NowPlayingSnapshot) -> some View {
        GlassEffectContainer(spacing: 10) {
            transportRow(track)
        }
    }

    private func transportRow(_ track: NowPlayingSnapshot) -> some View {
        HStack(spacing: 4) {
            NotchButton(size: 32) {
                model.onMediaCommand?(.previous)
            } label: {
                Image(systemName: "backward.fill").font(.system(size: 13, weight: .semibold))
            }

            NotchButton(size: 38, filled: true, tint: track.accent) {
                model.onMediaCommand?(.playPause)
            } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .contentTransition(.symbolEffect(.replace.offUp))
            }

            NotchButton(size: 32) {
                model.onMediaCommand?(.next)
            } label: {
                Image(systemName: "forward.fill").font(.system(size: 13, weight: .semibold))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared "there's nothing here yet" treatment.
struct EmptyPanel: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.32))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
