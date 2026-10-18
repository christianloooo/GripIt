import GripItScannerCore
import SceneKit
import UIKit

@MainActor private final class GripNodeButton: UIButton {
  let disc = UIView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    disc.isUserInteractionEnabled = false
    disc.layer.borderWidth = 1
    disc.layer.shadowColor = UIColor.black.cgColor
    disc.layer.shadowRadius = 4
    disc.layer.shadowOpacity = 0.3
    disc.layer.shadowOffset = CGSize(width: 0, height: 2)
    insertSubview(disc, at: 0)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() {
    super.layoutSubviews()
    let size: CGFloat = isSelected ? 34 : 28
    disc.frame = CGRect(
      x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
    disc.layer.cornerRadius = size / 2
    bringSubviewToFront(titleLabel!)
  }
}

/// Screen-space callouts stay attached to the posed skin while the camera orbits.
@MainActor final class GripGraphOverlay: UIView {
  private let pine = UIColor(red: 0.38, green: 0.91, blue: 0.72, alpha: 1)
  private var markers: [GripZoneID: GripNodeButton] = [:]
  private var zones: [GripZonePlan] = []
  private var selected: GripZoneID?
  private let lines = CAShapeLayer()
  private let connection = CAShapeLayer()
  private let card = UIView()
  private let heading = UILabel()
  private let instruction = UILabel()
  private let effort = UILabel()
  private let category = UILabel()
  private let hint = UILabel()
  private var projected: [GripZoneID: CGPoint] = [:]
  var onSelect: (GripZoneID) -> Void = { _ in }
  var onClose: () -> Void = {}

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    lines.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
    lines.fillColor = UIColor.clear.cgColor
    lines.lineWidth = 1
    layer.addSublayer(lines)
    connection.strokeColor = pine.withAlphaComponent(0.85).cgColor
    connection.fillColor = UIColor.clear.cgColor
    connection.lineWidth = 1.5
    connection.lineJoin = .round
    layer.addSublayer(connection)
    card.backgroundColor = UIColor(red: 0.055, green: 0.115, blue: 0.10, alpha: 0.98)
    card.layer.cornerRadius = 20
    card.layer.borderWidth = 1
    card.layer.borderColor = pine.withAlphaComponent(0.4).cgColor
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowRadius = 16
    card.layer.shadowOpacity = 0.3
    card.layer.shadowOffset = CGSize(width: 0, height: 5)
    card.accessibilityIdentifier = "grip-instruction-card"
    let stack = UIStackView(arrangedSubviews: [category, heading, instruction, effort])
    stack.axis = .vertical
    stack.spacing = 7
    stack.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -38),
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
    ])
    category.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
    category.textColor = pine
    heading.font = .systemFont(ofSize: 20, weight: .bold)
    heading.textColor = .white
    instruction.font = .systemFont(ofSize: 14, weight: .medium)
    instruction.textColor = UIColor.white.withAlphaComponent(0.86)
    instruction.numberOfLines = 4
    instruction.accessibilityIdentifier = "grip-node-instruction"
    effort.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
    effort.textColor = pine
    effort.accessibilityIdentifier = "grip-node-effort"
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark"), for: .normal)
    close.tintColor = UIColor.white.withAlphaComponent(0.65)
    close.accessibilityLabel = "Close grip instruction"
    close.accessibilityIdentifier = "close-grip-instruction"
    close.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
    close.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(close)
    NSLayoutConstraint.activate([
      close.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      close.topAnchor.constraint(equalTo: card.topAnchor),
      close.widthAnchor.constraint(equalToConstant: 44),
      close.heightAnchor.constraint(equalToConstant: 44),
    ])
    addSubview(card)
    hint.text = "Tap a numbered point to explore the grip"
    hint.font = .systemFont(ofSize: 12, weight: .medium)
    hint.textColor = UIColor.white.withAlphaComponent(0.55)
    hint.textAlignment = .center
    hint.isUserInteractionEnabled = false
    addSubview(hint)
    card.isHidden = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Empty space belongs to SceneKit's orbit, zoom, and pan gestures.
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    subviews.contains { !$0.isHidden && $0.isUserInteractionEnabled && $0.frame.contains(point) }
  }
  func configure(plan: GripPlan, selected: GripZoneID?) {
    zones = plan.zones
    self.selected = selected
    let valid = Set(zones.map(\.zoneId))
    for id in Array(markers.keys) where !valid.contains(id) {
      markers.removeValue(forKey: id)?.removeFromSuperview()
    }
    for (index, zone) in zones.enumerated() {
      let button: GripNodeButton
      if let existing = markers[zone.zoneId] {
        button = existing
      } else {
        button = GripNodeButton(frame: .zero)
        button.addAction(
          UIAction { [weak self] _ in self?.onSelect(zone.zoneId) }, for: .touchUpInside)
        button.accessibilityIdentifier = "grip-node-\(zone.zoneId.rawValue)"
        button.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        addSubview(button)
        markers[zone.zoneId] = button
      }
      let active = zone.zoneId == selected
      button.setTitle(String(format: "%02d", index + 1), for: .normal)
      button.setTitleColor(
        active ? UIColor(red: 0.025, green: 0.12, blue: 0.09, alpha: 1) : .white, for: .normal)
      button.isSelected = active
      button.disc.backgroundColor =
        active ? pine : UIColor(red: 0.06, green: 0.14, blue: 0.12, alpha: 0.9)
      button.disc.layer.borderColor =
        (active ? UIColor.white : pine.withAlphaComponent(0.5)).cgColor
      button.accessibilityLabel =
        "\(zone.title), \(zone.highlight?.intensity.rawValue ?? "none") effort. Show grip instruction."
      button.accessibilityTraits = active ? [.button, .selected] : .button
    }
    if let zone = zones.first(where: { $0.zoneId == selected }) {
      heading.text = zone.title
      instruction.text = zone.instruction
      category.text = "GRIP GUIDE / \(zone.highlight?.kind.rawValue.uppercased() ?? "PLACEMENT")"
      let intensity = zone.highlight?.intensity ?? .none
      let count = intensity == .firm ? 3 : intensity == .medium ? 2 : intensity == .light ? 1 : 0
      effort.text =
        "\(String(repeating: "■", count: count))\(String(repeating: "□", count: 3 - count))  \(intensity.rawValue.uppercased()) EFFORT"
      card.isHidden = false
      hint.isHidden = true
      bringSubviewToFront(card)
    } else {
      card.isHidden = true
      hint.isHidden = false
    }
    setNeedsLayout()
  }
  func project(_ points: [GripZoneID: CGPoint]) {
    projected = points
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 50, bounds.height > 80 else { return }
    let width = min(330, bounds.width - 28)
    let height = card.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
    ).height
    card.frame = CGRect(
      x: (bounds.width - width) / 2, y: bounds.height - height - 4, width: width, height: height)
    hint.frame = CGRect(x: 8, y: bounds.height - 38, width: bounds.width - 16, height: 25)
    let lower = max(100, card.isHidden ? bounds.height - 60 : card.frame.minY - 48)
    var points = zones.map { zone in
      let p = projected[zone.zoneId] ?? CGPoint(x: bounds.midX, y: bounds.midY)
      return CGPoint(x: min(bounds.width - 28, max(28, p.x)), y: min(lower, max(48, p.y)))
    }
    // Spread overlapping touch targets while keeping leaders on their skin anchors.
    for _ in 0..<18 {
      for i in points.indices {
        for j in points.indices where j > i {
          var delta = CGPoint(x: points[j].x - points[i].x, y: points[j].y - points[i].y)
          var distance = hypot(delta.x, delta.y)
          if distance < 52 {
            if distance < 0.1 {
              delta = CGPoint(x: j % 2 == 0 ? 1 : -1, y: 0.3)
              distance = hypot(delta.x, delta.y)
            }
            let shift = (52 - distance) / 2
            points[i].x -= delta.x / distance * shift
            points[i].y -= delta.y / distance * shift
            points[j].x += delta.x / distance * shift
            points[j].y += delta.y / distance * shift
          }
        }
        points[i].x = min(bounds.width - 28, max(28, points[i].x))
        points[i].y = min(lower, max(48, points[i].y))
      }
    }
    let leaders = UIBezierPath()
    for (index, zone) in zones.enumerated() {
      guard let button = markers[zone.zoneId] else { continue }
      button.frame = CGRect(x: points[index].x - 22, y: points[index].y - 22, width: 44, height: 44)
      if let anchor = projected[zone.zoneId],
        hypot(anchor.x - points[index].x, anchor.y - points[index].y) > 12
      {
        leaders.move(to: anchor)
        leaders.addLine(to: points[index])
      }
    }
    lines.path = leaders.cgPath
    let leader = UIBezierPath()
    if let index = zones.firstIndex(where: { $0.zoneId == selected }), !card.isHidden {
      let point = points[index]
      let elbow = CGPoint(x: point.x, y: card.frame.minY - 12)
      leader.move(to: point)
      leader.addLine(to: elbow)
      leader.addLine(to: CGPoint(x: card.frame.midX, y: elbow.y))
      leader.addLine(to: CGPoint(x: card.frame.midX, y: card.frame.minY))
    }
    connection.path = leader.cgPath
  }
}

@MainActor final class GripProjectionDriver: NSObject {
  weak var coordinator: GripSceneView.Coordinator?
  @objc func tick() { coordinator?.projectAnnotations() }
}
