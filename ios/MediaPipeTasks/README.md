# MediaPipe binary package

This small local package uses the official Google MediaPipe Tasks iOS 1.1.1
binary URLs, SHA-256 checksums, common target dependencies, and linker settings
from [the pinned upstream manifest](https://github.com/google-ai-edge/mediapipe/blob/50505c8312c7eacb1bd411cecdc4cc9fd08d53cb/Package.swift).

It exports only the Vision product used by GripIt. All supporting binary targets
remain unchanged because the shared task graph library requires their symbols.
No hand detection implementation or model weights have changed. Xcode downloads
the official binary archives directly without cloning MediaPipe's source history.

Upstream wrapper source and package configuration are Apache-2.0 licensed by the
MediaPipe Authors. The configuration is adapted only for local packaging and the
single exported product. See LICENSE and the notices inside Google's archives.
