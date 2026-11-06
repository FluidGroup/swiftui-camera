import Testing

@testable import Camera

@MainActor
struct CommandLaneTests {
  @Test func commandsArriveInTheOrderTheyWereSent() async {
    let lane = CommandLane(intent: DeviceIntent(position: .back))
    lane.send(.start)
    lane.updateIntent { $0.zoom = ZoomFactor(2) }
    lane.send(.stop)

    var iterator = lane.commands.makeAsyncIterator()
    var received: [String] = []
    for _ in 0..<3 {
      switch await iterator.next() {
      case .start: received.append("start")
      case .reconcile: received.append("reconcile")
      case .stop: received.append("stop")
      case .capturePhoto, nil: received.append("other")
      }
    }
    #expect(received == ["start", "reconcile", "stop"])
  }

  @Test func aReconcileReadsTheLatestIntentNotTheOneItWasSentWith() async {
    let lane = CommandLane(intent: DeviceIntent(position: .back))
    lane.updateIntent { $0.zoom = ZoomFactor(2) }
    lane.updateIntent { $0.zoom = ZoomFactor(3) }
    lane.adoptIntent { $0.exposure = .isoPriority(ISO(200)) }

    var iterator = lane.commands.makeAsyncIterator()
    _ = await iterator.next()
    #expect(lane.intentBox.value.zoom == ZoomFactor(3))
    #expect(lane.intentBox.value.exposure == .isoPriority(ISO(200)))
  }

  @Test func theStreamEndsWhenTheLaneGoesAway() async {
    var lane: CommandLane? = CommandLane(intent: DeviceIntent(position: .back))
    let commands = lane!.commands
    lane?.send(.start)
    lane = nil

    var iterator = commands.makeAsyncIterator()
    guard case .start? = await iterator.next() else {
      Issue.record("the queued command should still arrive")
      return
    }
    #expect(await iterator.next() == nil)
  }
}
