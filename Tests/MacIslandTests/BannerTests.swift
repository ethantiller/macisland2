import Foundation
import Testing

@testable import MacIsland

/// The AirPods and low-battery banners: alerts with nothing to press, centered on a smaller island.
@MainActor
struct BannerTests {
    @Test func theEmptierEarbudDecidesWhetherHeadphonesAreLow() {
        let fine = AudioAccessory(name: "AirPods Pro", left: 80, right: 75, caseLevel: 5)
        #expect(fine.lowestLevel == 75 && !fine.isLow, "the case doesn't count")
        #expect(AudioAccessory(name: "AirPods Pro", left: 80, right: 20, caseLevel: 90).isLow)
        #expect(AudioAccessory(name: "AirPods Pro", left: 19, right: 80).isLow)
        #expect(AudioAccessory(name: "Headphones", main: 15).isLow, "a headset has one battery")
        #expect(!AudioAccessory(name: "Headphones").isLow, "no reading is not low")
    }

    @Test func headphonesDrawAGreenRingOrARedOneWhenLow() {
        let fine = Announcements.headphones(AudioAccessory(name: "AirPods Pro", left: 80, right: 75))
        let low = Announcements.headphones(AudioAccessory(name: "AirPods Pro", left: 80, right: 10))
        #expect(fine.ringTint == Theme.Tint.positive)
        #expect(low.ringTint == Theme.Tint.attention)
        #expect(fine.isAlert && low.isAlert)
    }

    @Test func lowBatteryIsACenteredAlertWithNothingToPress() {
        let low = Announcements.lowBattery(percent: 15)
        #expect(low.banner.actions.isEmpty && low.banner.isAlert, "Low Power Mode asks for a password every time")
        #expect(low.banner.detail == "15% remaining")
        #expect(low.followUp.staysUntilSeen)
    }

    @Test func aBannerWithNothingToPressIsASmallerIsland() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.showBanner(Announcements.headphones(AudioAccessory(name: "AirPods Pro", left: 80, right: 75)))
        #expect(viewModel.size.width == Theme.Metrics.bannerAlertWidth)
        #expect(Theme.Metrics.bannerAlertWidth < Theme.Metrics.bannerWidth)
        viewModel.performBannerAction()
        viewModel.showBanner(
            IslandBanner(
                systemImage: "calendar", tint: Theme.Tint.neutral, title: "Design Review",
                actions: [.init(title: "Join") {}]))
        #expect(viewModel.size.width == Theme.Metrics.bannerWidth, "with buttons it keeps its width")
    }
}
