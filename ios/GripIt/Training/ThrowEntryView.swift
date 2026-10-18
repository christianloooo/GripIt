import GripItScannerCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ThrowEntryView: View {
  @ObservedObject var model: TrainingFlowModel
  @State private var feedback: FocusAssessment?
  @State private var showFeedback = false
  @State private var replacement: ThrowEntryReplacement?
  @State private var selectedPhoto: SessionThrowPhoto?
  @State private var pickedPhoto: PhotosPickerItem?
  @State private var showFiles = false
  @State private var loadingPhoto = false
  @State private var photoMessage: String?
  @State private var reviewedThrow: ReviewedPhotoThrow?
  @FocusState private var editing: Bool

  var body: some View {
    ScrollViewReader { proxy in
      Form {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            TrainingStepLabel(step: 3)
            Text("Record your throw.").font(.title.bold())
            Text("Add a photo of your \(model.pitch.shortTitle.lowercased()) readings, or enter them below.")
              .font(.subheadline).foregroundStyle(.secondary)
            if model.usesSampleHand {
              Label("Sample hand", systemImage: "hand.raised")
                .font(.caption).foregroundStyle(.mint)
            }
          }.padding(.vertical, 6)
        }.listRowBackground(Color.clear)

        Section {
          photoStrip
          HStack(spacing: 12) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
              Label("Upload photo", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(ThrowPhotoStyle.ink)
            .accessibilityIdentifier("upload-throw-photo")
            .disabled(loadingPhoto)
            Button { showFiles = true } label: {
              Image(systemName: "folder").frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered).tint(.mint)
            .accessibilityLabel("Choose photo from Files")
            .disabled(loadingPhoto)
          }
          if loadingPhoto {
            ProgressView("Opening photo…").font(.caption).tint(.mint)
          }
          if let photoMessage {
            Text(photoMessage).font(.caption).foregroundStyle(.orange)
          }
        } header: {
          HStack {
            Text("SESSION PHOTOS")
            Spacer()
            Text("\(model.photos.count)").monospacedDigit()
          }
        } footer: {
          Text("Tap a photo to review its readings. A throw is added only after you confirm.")
        }.listRowBackground(ThrowPhotoStyle.surface)

        if model.draft.source == .sample {
          Section {
            HStack {
              Label("Sample throws", systemImage: "flask").foregroundStyle(.mint)
              Spacer()
              Button("Use real throws") { requestReplacement(sample: false) }
                .font(.subheadline.weight(.semibold))
            }
          }.listRowBackground(ThrowPhotoStyle.surface)
        }

        ForEach($model.draft.rows) { $row in
          Section {
            field("Velocity", value: $row.velocityMph, unit: "mph", key: "velocityMph", id: row.id)
            field("Total spin", value: $row.totalSpinRpm, unit: "rpm", key: "totalSpinRpm", id: row.id)
            field("Spin direction", value: $row.spinDirectionClock, unit: "12:30",
              key: "spinDirectionClock", id: row.id, clock: true)
            field("Spin efficiency", value: $row.spinEfficiencyPercent, unit: "%",
              key: "spinEfficiencyPercent", id: row.id)
            field("Gyro angle", value: $row.gyroDegree, unit: "°",
              key: "gyroDegree", id: row.id, signed: true)
            field("Horizontal break", value: $row.horizontalBreakInches, unit: "in",
              key: "horizontalBreakInches", id: row.id, signed: true)
            field("Vertical break", value: $row.verticalBreakInches, unit: "in",
              key: "verticalBreakInches", id: row.id, signed: true)
            field("Release height", value: $row.releaseHeightFeet, unit: "ft",
              key: "releaseHeightFeet", id: row.id)
            DisclosureGroup("Optional score") {
              field("Rapsodo score", value: $row.rapsodoScore, unit: "", key: "rapsodoScore", id: row.id)
            }
          } header: {
            HStack {
              Text("Throw \((model.draft.rows.firstIndex { $0.id == row.id } ?? 0) + 1)")
              Spacer()
              if model.draft.rows.count > 1 {
                Button("Remove", role: .destructive) { model.removeThrow(row.id) }
              }
            }
          }
          .listRowBackground(ThrowPhotoStyle.surface).id(row.id)
        }

        Section {
          Button { model.addThrow() } label: {
            Label("Add another throw", systemImage: "plus")
          }
          if model.draft.source != .sample {
            Button("Use sample throws") { requestReplacement(sample: true) }
              .foregroundStyle(.secondary)
          }
        } footer: {
          Text("One throw is enough. Three or more lets us check consistency.")
        }.listRowBackground(ThrowPhotoStyle.surface)
      }
      .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
      .background(ThrowPhotoStyle.background).preferredColorScheme(.dark).tint(.mint)
      .navigationTitle(model.pitch.shortTitle).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { editing = false }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          if let message = model.message { Text(message).font(.caption).foregroundStyle(.orange) }
          Button {
            editing = false
            if let result = model.assessment() {
              feedback = result
              showFeedback = true
            } else if let first = model.draft.rows.first(where: { model.errors[$0.id] != nil }) {
              withAnimation { proxy.scrollTo(first.id, anchor: .top) }
            }
          } label: {
            HStack {
              Text("See feedback")
              Spacer()
              Image(systemName: "arrow.up.right")
            }.font(.headline).frame(maxWidth: .infinity, minHeight: 40)
          }
          .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(ThrowPhotoStyle.ink)
          .accessibilityIdentifier("see-feedback")
        }.padding(.horizontal, 20).padding(.vertical, 12).background(ThrowPhotoStyle.background)
      }
      .onChange(of: model.draft.rows.count) { _, _ in scrollToLatest(proxy) }
      .onChange(of: pickedPhoto) { _, item in
        guard let item else { return }
        Task { await openPickedPhoto(item) }
      }
      .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
        switch result {
        case .success(let url):
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          do { addPhoto(try Data(contentsOf: url)) }
          catch { photoMessage = "This photo could not be opened. Choose another image." }
        case .failure:
          photoMessage = "This photo could not be opened. Choose another image."
        }
      }
      .fullScreenCover(item: $selectedPhoto, onDismiss: finishPhotoReview) { photo in
        ThrowPhotoReview(photo: photo, pitchTitle: model.pitch.shortTitle) { row in
          reviewedThrow = ReviewedPhotoThrow(row: row, source: photo.source)
          selectedPhoto = nil
        }
      }
      .confirmationDialog("Replace these throw entries?", isPresented: Binding(
        get: { replacement != nil }, set: { if !$0 { replacement = nil } }
      ), titleVisibility: .visible) {
        if let pending = replacement {
          Button("Replace entries", role: .destructive) {
            switch pending {
            case .session(let sample): model.replaceDraft(sample: sample)
            case .photo(let result): appendPhotoThrow(result)
            }
            replacement = nil
          }
        }
        Button("Cancel", role: .cancel) { replacement = nil }
      } message: {
        Text("Sample readings and your own throws stay in separate sessions. Replacing removes the current entries.")
      }
      .navigationDestination(isPresented: $showFeedback) {
        if let feedback { FocusAssessmentView(model: model, assessment: feedback) }
      }
    }
  }

  private var photoStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(model.photos) { photo in
          Button { selectedPhoto = photo } label: {
            VStack(alignment: .leading, spacing: 8) {
              Image(uiImage: photo.image).resizable().scaledToFit()
                .frame(width: 166, height: 120)
                .background(ThrowPhotoStyle.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                  Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold)).padding(7)
                    .background(.black.opacity(0.65), in: Circle()).padding(7)
                }
              Text(photo.title).font(.caption.weight(.semibold))
              Text(photo.fixture == nil ? "YOUR PHOTO" : "SAMPLE PHOTO")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1).foregroundStyle(.mint)
            }.frame(width: 166, alignment: .leading)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Review \(photo.title)")
          .accessibilityIdentifier("throw-photo-\(photo.fixture?.rawValue ?? photo.id.uuidString)")
        }
      }.padding(.vertical, 6)
    }
  }

  @MainActor private func openPickedPhoto(_ item: PhotosPickerItem) async {
    loadingPhoto = true
    photoMessage = nil
    defer { loadingPhoto = false; pickedPhoto = nil }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        photoMessage = "This photo could not be opened. Choose another image."
        return
      }
      addPhoto(data)
    } catch { photoMessage = "This photo could not be opened. Choose another image." }
  }

  private func addPhoto(_ data: Data) {
    let fixture = RapsodoPhotoFixture.matching(data)
    let preview = fixture?.previewURL.flatMap { try? Data(contentsOf: $0) } ?? data
    guard let image = UIImage(data: preview) else {
      photoMessage = "This image format could not be opened. Try a PNG or JPEG photo."
      return
    }
    photoMessage = nil
    let photo = SessionThrowPhoto(title: "Photo \(model.photos.count - RapsodoPhotoFixture.allCases.count + 1)",
      image: image, fixture: fixture)
    model.photos.append(photo)
    selectedPhoto = photo
  }

  private func finishPhotoReview() {
    guard let result = reviewedThrow else { return }
    reviewedThrow = nil
    if model.draft.source != result.source && model.hasEntries {
      replacement = .photo(result)
    } else { appendPhotoThrow(result) }
  }

  private func appendPhotoThrow(_ result: ReviewedPhotoThrow) {
    if model.draft.source != result.source {
      var session = ThrowSessionDraft(source: result.source)
      session.rows = [result.row]
      model.draft = session
    } else if let empty = model.draft.rows.firstIndex(where: { $0.hasNoPhotoReadings }) {
      model.draft.rows[empty] = result.row
    } else { model.draft.rows.append(result.row) }
  }

  private func requestReplacement(sample: Bool) {
    if model.hasEntries { replacement = .session(sample: sample) }
    else { model.replaceDraft(sample: sample) }
  }

  private func scrollToLatest(_ proxy: ScrollViewProxy) {
    if let last = model.draft.rows.last, last.velocityMph.isEmpty {
      withAnimation { proxy.scrollTo(last.id, anchor: .top) }
    }
  }

  private func field(_ title: String, value: Binding<String>, unit: String,
    key: String, id: String, clock: Bool = false, signed: Bool = false) -> some View {
    let required = ["velocityMph", "totalSpinRpm", "spinDirectionClock"].contains(key)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 12) {
        Text(title).font(.subheadline)
        Spacer(minLength: 8)
        TextField(clock ? "12:30" : required ? "Required" : "Optional", text: value)
          .multilineTextAlignment(.trailing)
          .keyboardType(clock || signed ? .numbersAndPunctuation : .decimalPad)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($editing).frame(minWidth: 70, maxWidth: 110)
          .accessibilityLabel(title).accessibilityIdentifier("\(id)-\(key)")
        if !unit.isEmpty, !clock {
          Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
      }
      if let error = model.errors[id]?[key] {
        Text(error).font(.caption).foregroundStyle(.orange)
      }
    }.padding(.vertical, 4)
  }
}

private enum ThrowPhotoStyle {
  static let background = Color(red: 0.025, green: 0.045, blue: 0.04)
  static let surface = Color(red: 0.035, green: 0.075, blue: 0.065)
  static let ink = Color(red: 0.025, green: 0.12, blue: 0.09)
}

struct SessionThrowPhoto: Identifiable {
  let id = UUID()
  let title: String
  let image: UIImage
  let fixture: RapsodoPhotoFixture?
  var source: ThrowSource { fixture == nil ? .manual : .sample }

  static var bundled: [Self] {
    RapsodoPhotoFixture.allCases.compactMap { fixture in
      guard let url = fixture.previewURL, let image = UIImage(contentsOfFile: url.path) else { return nil }
      return Self(title: fixture.title, image: image, fixture: fixture)
    }
  }
}

private struct ReviewedPhotoThrow {
  let row: ThrowDraft
  let source: ThrowSource
}

private enum ThrowEntryReplacement {
  case session(sample: Bool)
  case photo(ReviewedPhotoThrow)
}

private extension ThrowDraft {
  var hasNoPhotoReadings: Bool {
    [velocityMph, totalSpinRpm, spinDirectionClock, spinEfficiencyPercent, gyroDegree,
      horizontalBreakInches, verticalBreakInches, releaseHeightFeet, rapsodoScore]
      .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
}

private struct ThrowPhotoReview: View {
  let photo: SessionThrowPhoto
  let pitchTitle: String
  let onConfirm: (ThrowDraft) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var draft: ThrowDraft
  @State private var scanning = true
  @State private var scanPosition: CGFloat = 0
  @State private var preparing = true
  @State private var revealed = 0
  @State private var errors: [String: String] = [:]
  @State private var errorMessage: String?
  @FocusState private var editing: Bool

  init(photo: SessionThrowPhoto, pitchTitle: String, onConfirm: @escaping (ThrowDraft) -> Void) {
    self.photo = photo
    self.pitchTitle = pitchTitle
    self.onConfirm = onConfirm
    _draft = State(initialValue: ThrowDraft(source: photo.source))
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let narrow = geometry.size.width < 600
        HStack(alignment: .top, spacing: narrow ? 10 : 24) {
          photoPanel
            .frame(width: max(115, geometry.size.width * (narrow ? 0.40 : 0.48)))
          ScrollView {
            VStack(alignment: .leading, spacing: narrow ? 14 : 18) {
              reviewHeader
              reading("Velocity", value: $draft.velocityMph, unit: "mph", key: "velocityMph", required: true)
              reading("Total spin", value: $draft.totalSpinRpm, unit: "rpm", key: "totalSpinRpm", required: true)
              reading("Spin direction", value: $draft.spinDirectionClock, unit: "clock",
                key: "spinDirectionClock", required: true, punctuation: true)
              reading("Spin efficiency", value: $draft.spinEfficiencyPercent, unit: "%", key: "spinEfficiencyPercent")
              reading("Gyro angle", value: $draft.gyroDegree, unit: "°", key: "gyroDegree", punctuation: true)
              reading("Horizontal break", value: $draft.horizontalBreakInches, unit: "in",
                key: "horizontalBreakInches", punctuation: true)
              reading("Vertical break", value: $draft.verticalBreakInches, unit: "in",
                key: "verticalBreakInches", punctuation: true)
              reading("Release height", value: $draft.releaseHeightFeet, unit: "ft", key: "releaseHeightFeet")
              reading("Rapsodo score", value: $draft.rapsodoScore, unit: "", key: "rapsodoScore")
              Text("Leave readings that are absent from the photo empty.")
                .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6).padding(.trailing, 2)
          }.scrollDismissesKeyboard(.interactively)
        }.padding(.horizontal, narrow ? 14 : 24).padding(.top, 10)
      }
      .background(ThrowPhotoStyle.background).preferredColorScheme(.dark).tint(.mint)
      .navigationTitle("Review readings").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }.accessibilityIdentifier("cancel-photo-readings")
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { editing = false }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 8) {
          if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.orange) }
          Button(action: confirm) {
            HStack {
              Text("Confirm readings")
              Spacer()
              Image(systemName: "checkmark")
            }.font(.headline).frame(maxWidth: .infinity, minHeight: 40)
          }
          .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(ThrowPhotoStyle.ink)
          .disabled(preparing).accessibilityIdentifier("confirm-photo-readings")
        }.padding(.horizontal, 20).padding(.vertical, 12).background(ThrowPhotoStyle.background)
      }
      .task { await prepareReadings() }
    }
  }

  private var reviewHeader: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(pitchTitle.uppercased())
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(1).foregroundStyle(.mint)
      Text(preparing ? "Preparing readings" : "Check your readings")
        .font(.headline)
      Text(photo.fixture == nil
        ? "Enter the values visible in your photo."
        : "Confirm each value against this sample photo.")
        .font(.caption).foregroundStyle(.secondary)
      if preparing && photo.fixture != nil {
        Text("\(revealed) readings ready").font(.caption2.monospacedDigit()).foregroundStyle(.mint)
      }
    }.accessibilityElement(children: .combine)
  }

  private var photoPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      GeometryReader { bounds in
        ZStack(alignment: .top) {
          ThrowPhotoZoomView(image: photo.image)
            .accessibilityLabel(photo.title + ". Pinch to zoom and drag to inspect the photo.")
          if scanning {
            LinearGradient(colors: [.clear, .mint.opacity(0.20), .mint.opacity(0.65)],
              startPoint: .top, endPoint: .bottom)
              .frame(height: 55)
              .overlay(alignment: .bottom) { Rectangle().fill(.mint).frame(height: 1) }
              .offset(y: scanPosition * max(0, bounds.size.height - 55))
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.mint.opacity(0.18), lineWidth: 1))
      }
      .frame(maxHeight: .infinity)
      .background(ThrowPhotoStyle.surface, in: RoundedRectangle(cornerRadius: 18))
      Text(photo.title).font(.caption.weight(.semibold))
      Label("Pinch to zoom", systemImage: "arrow.up.left.and.arrow.down.right")
        .font(.system(size: 10)).foregroundStyle(.secondary)
      if photo.fixture != nil {
        Text("SAMPLE PHOTO").font(.system(size: 8, weight: .semibold, design: .monospaced))
          .tracking(1).foregroundStyle(.mint)
      }
    }.padding(.bottom, 12)
  }

  private func reading(_ title: String, value: Binding<String>, unit: String, key: String,
    required: Bool = false, punctuation: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 3) {
        TextField(required ? (key == "spinDirectionClock" ? "12:30" : "Required") : "Optional", text: value)
          .font(.system(.body, design: .monospaced).weight(.medium))
          .keyboardType(punctuation ? .numbersAndPunctuation : .decimalPad)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($editing).disabled(preparing)
          .accessibilityLabel(title).accessibilityIdentifier("photo-\(key)")
        Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10).padding(.vertical, 12)
      .background(ThrowPhotoStyle.surface, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10)
        .stroke(errors[key] == nil ? Color.mint.opacity(value.wrappedValue.isEmpty ? 0.08 : 0.3) : Color.orange, lineWidth: 1))
      if let error = errors[key] { Text(error).font(.caption2).foregroundStyle(.orange) }
    }
  }

  @MainActor private func prepareReadings() async {
    do {
      if !reduceMotion {
        withAnimation(.linear(duration: 0.85)) { scanPosition = 1 }
        try await Task.sleep(for: .milliseconds(900))
      }
      scanning = false
      if let fixture = photo.fixture {
        let values = fixture.makeDraft()
        let readings: [(WritableKeyPath<ThrowDraft, String>, String)] = [
          (\.velocityMph, values.velocityMph), (\.totalSpinRpm, values.totalSpinRpm),
          (\.spinDirectionClock, values.spinDirectionClock),
          (\.spinEfficiencyPercent, values.spinEfficiencyPercent), (\.gyroDegree, values.gyroDegree),
          (\.horizontalBreakInches, values.horizontalBreakInches),
          (\.verticalBreakInches, values.verticalBreakInches),
        ]
        for (key, value) in readings where !value.isEmpty {
          try Task.checkCancellation()
          if !reduceMotion { try await Task.sleep(for: .milliseconds(150)) }
          draft[keyPath: key] = value
          revealed += 1
        }
      }
      preparing = false
    } catch { /* Dismissing the review cancels its animation and leaves entries untouched. */ }
  }

  private func confirm() {
    editing = false
    do {
      errors = try NativeFocusEngine.validate(draft).errors
      guard errors.isEmpty else {
        errorMessage = "Check the highlighted readings before adding this throw."
        return
      }
      onConfirm(draft)
    } catch { errorMessage = error.localizedDescription }
  }
}

/// A native zoom surface keeps the full capture on the left while readings stay editable on the right.
private struct ThrowPhotoZoomView: UIViewRepresentable {
  let image: UIImage
  func makeUIView(context: Context) -> ThrowPhotoZoomScrollView {
    let view = ThrowPhotoZoomScrollView()
    view.photoView.image = image
    return view
  }
  func updateUIView(_ uiView: ThrowPhotoZoomScrollView, context: Context) {}
}

private final class ThrowPhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
  let photoView = UIImageView()
  private var fittedSize = CGSize.zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    delegate = self
    showsHorizontalScrollIndicator = false
    showsVerticalScrollIndicator = false
    bouncesZoom = true
    backgroundColor = UIColor(red: 0.02, green: 0.035, blue: 0.03, alpha: 1)
    addSubview(photoView)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let image = photoView.image, bounds.width > 0, bounds.height > 0 else { return }
    if fittedSize != bounds.size {
      fittedSize = bounds.size
      zoomScale = 1
      photoView.frame = CGRect(origin: .zero, size: image.size)
      contentSize = image.size
      let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
      minimumZoomScale = fit
      maximumZoomScale = fit * 8
      zoomScale = fit
    }
    centerPhoto()
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { photoView }
  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }
  private func centerPhoto() {
    contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0,
      (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
  }
}
