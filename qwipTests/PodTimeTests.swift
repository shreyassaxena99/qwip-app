import Foundation
import Testing
@testable import qwip

struct PodTimeTests {
    private func at(_ hour: Int, _ minute: Int) -> Date {
        PodTime.calendar.date(from: DateComponents(year: 2026, month: 11, day: 10,
                                                   hour: hour, minute: minute))!
    }

    private var slots: [ReservationSlot] {
        [at(14, 0), at(14, 15), at(14, 30)].map {
            ReservationSlot(startAt: $0, durations: [])
        }
    }

    @Test func requestedTimeRoundsToNearestQuarterHour() {
        #expect(PodTime.closestStart(slots, desiredTime: at(14, 7)) == at(14, 0))
        #expect(PodTime.closestStart(slots, desiredTime: at(14, 8)) == at(14, 15))
    }

    @Test func unavailableRoundedTimeUsesLaterSlotOnTie() {
        let available = [slots[0], slots[2]]
        #expect(PodTime.closestStart(available, desiredTime: at(14, 15)) == at(14, 30))
    }
}
