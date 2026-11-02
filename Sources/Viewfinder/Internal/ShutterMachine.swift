enum PressSource: Sendable, Hashable {
  case touch
  case hardware
}

enum ShutterInput: Sendable, Hashable {
  case press(PressSource)
  case release(PressSource)
  case cancel(PressSource)
  case activate
}

enum ShutterMachine {
  struct State: Sendable, Hashable {
    var owner: PressSource?
  }

  enum Effect: Sendable, Hashable {
    case capturePhoto
  }

  static func reduce(_ state: inout State, _ input: ShutterInput, canPress: Bool) -> Effect? {
    switch input {
    case .press(let source):
      guard state.owner == nil, canPress else { return nil }
      state.owner = source
      return nil
    case .release(let source):
      guard state.owner == source else { return nil }
      state.owner = nil
      return .capturePhoto
    case .cancel(let source):
      guard state.owner == source else { return nil }
      state.owner = nil
      return nil
    case .activate:
      guard state.owner == nil, canPress else { return nil }
      return .capturePhoto
    }
  }
}
