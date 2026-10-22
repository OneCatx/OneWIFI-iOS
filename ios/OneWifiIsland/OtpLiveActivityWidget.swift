import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// OneWIFI 品牌标记，与 App 图标同形（左月牙 + 右圆）。
/// 以模板方式渲染，颜色交给使用处，深浅背景都清晰。
struct OneWifiMark: View {
  var body: some View {
    if let image = UIImage(named: "OneWifiMark") {
      Image(uiImage: image.withRenderingMode(.alwaysTemplate))
        .resizable()
        .scaledToFit()
    } else {
      // 资源缺失时退到系统符号，避免灵动岛出现空白。
      Image(systemName: "dot.radiowaves.left.and.right")
    }
  }
}

struct OtpCodeWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: OtpActivityAttributes.self) { context in
      OtpBannerView(code: context.state.displayCode(isStale: context.isStale))
    } dynamicIsland: { context in
      let code = context.state.displayCode(isStale: context.isStale)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 4) {
            OneWifiMark()
              .frame(width: 18, height: 12)
              .foregroundStyle(.primary)
              .accessibilityHidden(true)
            Text(code.isEmpty ? "等待验证码" : "验证码")
              .font(.caption.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
          .frame(minHeight: 24, alignment: .center)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(code)
            .font(.headline.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(minHeight: 24, alignment: .center)
        }
      } compactLeading: {
        OneWifiMark()
          .frame(width: 21, height: 13)
          .foregroundStyle(.primary)
          .accessibilityHidden(true)
      } compactTrailing: {
        Text(code.isEmpty ? "待收" : code)
          .font(.caption.monospacedDigit().weight(.bold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      } minimal: {
        OneWifiMark()
          .frame(width: 18, height: 11)
          .foregroundStyle(.primary)
          .accessibilityLabel(code.isEmpty ? "等待验证码" : "验证码已收到")
      }
    }
  }
}

struct OtpBannerView: View {
  // Only accept projected content so a stale code cannot leak into the banner.
  let code: String

  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 4) {
        OneWifiMark()
          .frame(width: 20, height: 14)
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
          }
          .accessibilityHidden(true)
        Text(code.isEmpty ? "等待验证码" : "验证码")
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      Spacer(minLength: 12)
      Text(code)
        .font(.headline.monospacedDigit().weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
    .frame(minHeight: 32, alignment: .center)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}
