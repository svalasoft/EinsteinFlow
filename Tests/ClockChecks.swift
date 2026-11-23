import Foundation

@main struct ClockChecks {
    static func main() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func date(_ offset: Double) -> Date { start.addingTimeInterval(offset) }
        var clock = FlowClock(at: start)
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name)
            checks += 1
        }
        func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-10 }
        check(clock.running && clock.elapsed(at: date(10)) == 10, "Visible view starts without waiting for a scene event")
        check(clock.rotationStep == 1 && close(clock.rotationAngle(at: date(10)), 0.65),
              "Rotation starts at its independent normal rate")
        clock.togglePaused(at: date(10))
        check(clock.paused && !clock.running && clock.elapsed(at: date(90)) == 10, "Pause freezes time")
        check(close(clock.rotationAngle(at: date(90)), 0.65), "Pause freezes the rotation angle too")
        clock.setVisible(false, at: date(100))
        clock.setVisible(true, at: date(200))
        check(clock.paused && !clock.running, "Returning to the view preserves user pause")
        clock.togglePaused(at: date(200))
        check(clock.running && clock.elapsed(at: date(205)) == 15, "Play resumes without jumping")
        clock.setVisible(false, at: date(210))
        check(clock.elapsed(at: date(300)) == 20, "Background time is excluded")
        check(close(clock.rotationAngle(at: date(300)), 1.3), "Background time does not rotate the field")
        clock.setVisible(true, at: date(400))
        check(clock.elapsed(at: date(405)) == 25, "Foreground resumes the same clock")
        clock.setReducedMotion(true, at: date(410))
        check(!clock.running && clock.elapsed(at: date(500)) == 30, "Reduce Motion freezes the composition")
        check(close(clock.rotationAngle(at: date(500)), 1.95), "Reduce Motion freezes rotation")
        clock.togglePaused(at: date(500))
        clock.togglePaused(at: date(501))
        check(!clock.running, "Play cannot bypass Reduce Motion")
        clock.setReducedMotion(false, at: date(600))
        check(clock.running && clock.elapsed(at: date(605)) == 35, "Disabling Reduce Motion resumes")
        clock.setVisible(true, at: date(700))
        check(clock.elapsed(at: date(705)) == 135, "Duplicate activation does not reset the clock")
        check(clock.elapsed(at: date(600)) == 30, "A clock adjustment never produces a negative interval")
        var variable = FlowClock(at: start)
        variable.setSpeed(2, at: date(10))
        check(variable.elapsed(at: date(10)) == 10 && variable.elapsed(at: date(15)) == 20,
              "Changing speed preserves progress and changes only future time")
        check(close(variable.rotationAngle(at: date(10)), 0.65) && close(variable.rotationAngle(at: date(15)), 0.975),
              "Cutter speed changes neither the current angle nor the future rotation rate")
        variable.togglePaused(at: date(15))
        variable.setSpeed(0.5, at: date(20))
        check(variable.elapsed(at: date(30)) == 20, "Changing speed while paused keeps progress frozen")
        check(close(variable.rotationAngle(at: date(30)), 0.975), "A paused speed change also preserves the rotation angle")
        variable.togglePaused(at: date(30))
        check(variable.elapsed(at: date(40)) == 25, "Resuming uses the selected speed")
        check(close(variable.rotationAngle(at: date(40)), 1.625), "Resuming rotation remains independent of cutter speed")
        variable.stepRotation(by: -1, at: date(40))
        check(variable.rotationStep == 0 && close(variable.rotationAngle(at: date(40)), 1.625),
              "Stepping rotation to zero preserves its angle")
        check(close(variable.rotationAngle(at: date(50)), 1.625) && variable.elapsed(at: date(50)) == 30,
              "Zero rotation leaves the cutters running")
        variable.stepRotation(by: -1, at: date(50))
        check(variable.rotationStep == -1 && close(variable.rotationAngle(at: date(50)), 1.625),
              "Reversing through zero preserves the angle")
        check(close(variable.rotationAngle(at: date(60)), 0.975) && variable.elapsed(at: date(60)) == 35,
              "Reverse rotation decreases the angle without changing cutter progress")
        variable.stepRotation(by: -1, at: date(60))
        check(variable.rotationStep == -2 && close(variable.rotationAngle(at: date(65)), 0.325)
                && variable.elapsed(at: date(65)) == 37.5,
              "A stronger reverse step changes only future angular speed")
        variable.stepRotation(by: -20, at: date(65))
        check(variable.rotationStep == -4 && close(variable.rotationAngle(at: date(65)), 0.325),
              "The reverse endpoint clamps at minus four without an angle jump")
        check(close(variable.rotationAngle(at: date(70)), -0.975), "The reverse endpoint uses the clamped angular rate")
        variable.stepRotation(by: 20, at: date(70))
        check(variable.rotationStep == 4 && close(variable.rotationAngle(at: date(70)), -0.975),
              "The forward endpoint clamps at four without an angle jump")
        check(close(variable.rotationAngle(at: date(75)), 0.325) && variable.elapsed(at: date(75)) == 42.5,
              "The forward endpoint preserves the independent cutter clock")
        variable.stepRotation(by: 1, at: date(75))
        check(variable.rotationStep == 4 && close(variable.rotationAngle(at: date(80)), 1.625),
              "Stepping beyond the endpoint retains its angle and rate")

        var suspended = FlowClock(at: start)
        suspended.togglePaused(at: date(10))
        suspended.setSpeed(8, at: date(20))
        suspended.stepRotation(by: -2, at: date(25))
        check(suspended.elapsed(at: date(40)) == 10 && close(suspended.rotationAngle(at: date(40)), 0.65),
              "Changing both rates while paused keeps both clocks frozen")
        suspended.togglePaused(at: date(40))
        check(suspended.elapsed(at: date(45)) == 50 && close(suspended.rotationAngle(at: date(45)), 0.325),
              "Play resumes the selected cutter and reverse rotation rates")
        suspended.setVisible(false, at: date(45))
        suspended.stepRotation(by: 1, at: date(60))
        suspended.setSpeed(0.5, at: date(70))
        check(suspended.elapsed(at: date(80)) == 50 && close(suspended.rotationAngle(at: date(80)), 0.325),
              "Rate changes while hidden preserve both suspended clocks")
        suspended.setVisible(true, at: date(80))
        check(suspended.elapsed(at: date(90)) == 55 && close(suspended.rotationAngle(at: date(90)), 0.325),
              "Returning from the background applies the selected rates")
        suspended.setReducedMotion(true, at: date(90))
        suspended.stepRotation(by: -1, at: date(95))
        suspended.setSpeed(2, at: date(100))
        check(suspended.elapsed(at: date(110)) == 55 && close(suspended.rotationAngle(at: date(110)), 0.325),
              "Rate changes cannot bypass Reduce Motion")
        suspended.setReducedMotion(false, at: date(120))
        check(suspended.elapsed(at: date(125)) == 65 && close(suspended.rotationAngle(at: date(125)), 0),
              "Disabling Reduce Motion resumes both clocks from their preserved values")
        print("Playback clock: \(checks) checks passed")
    }
}
