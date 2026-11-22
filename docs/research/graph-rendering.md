# Graph rendering

Source: Apple developer documentation (read as DocC JSON on 2026-11-22), WWDC sessions [2021/10021](https://developer.apple.com/videos/play/wwdc2021/10021/), [2021/10147](https://developer.apple.com/videos/play/wwdc2021/10147/), [2022/10136](https://developer.apple.com/videos/play/wwdc2022/10136/), [2022/10137](https://developer.apple.com/videos/play/wwdc2022/10137/), [2023/10037](https://developer.apple.com/videos/play/wwdc2023/10037/), [2023/10156](https://developer.apple.com/videos/play/wwdc2023/10156/), [2024/10155](https://developer.apple.com/videos/play/wwdc2024/10155/), [2025/306](https://developer.apple.com/videos/play/wwdc2025/306/), [2025/313](https://developer.apple.com/videos/play/wwdc2025/313/), the tech talk [Explore UI animation hitches](https://developer.apple.com/videos/play/tech-talks/10855/), the HIG, and the source of the third-party libraries named below. Nothing here was measured on a device; costs are *unmeasured* until the prototype below runs.

## What the graph must do

From spec `rules/history.md` ("Graph ranges", "Drawing") and `docs/history-redesign.md`: one line per Target per Link (up to ~18), a Link picker, 60–300 points per line, line breaks at empty buckets, Paused buckets shaded, all-lost buckets as loss marks, a per-bucket loss strip, a marked provisional point, Link-change markers on Raw ranges, closed points that never change, scrolling with the clock on short ranges, animated range switches, light and dark. That is up to ~5,400 line points plus a few hundred rectangles.

## Swift Charts with marks

- One `LineMark` per point. Apple: "Use the Mark API when you have fewer data points, but need to customize each element", and vectorized plots "for larger datasets" ([WWDC24 10155](https://developer.apple.com/videos/play/wwdc2024/10155/), Best practices).
- Animation is SwiftUI's: "Swift Charts works with SwiftUI animations" ([WWDC22 10136](https://developer.apple.com/videos/play/wwdc2022/10136/)). Marks are matched by the `id` given to `Chart`/`ForEach` ([WWDC22 10137](https://developer.apple.com/videos/play/wwdc2022/10137/)). Apple documents no per-frame scroll model.
- This repo tried it: points changed identity as gaps scrolled off, flew in and out, and each 1 s animation stalled on a slow refresh (`App/Sources/Graphs.swift`, comment on `LatencyChart`). Sparklines kept marks with the scroll animation off.
- Gaps: a new `series` value per run. Shading: `RectangleMark`. Markers: `RuleMark`. Provisional: a separate `PointMark` or a styled last segment.
- Free with any Swift Charts chart: VoiceOver elements per mark, Audio Graphs, Dark Mode, Dynamic Type, High Contrast ([WWDC22 10136](https://developer.apple.com/videos/play/wwdc2022/10136/); [HIG Charts](https://developer.apple.com/design/human-interface-guidelines/charts), "Enhancing the accessibility of a chart").
- Selection and scrolling: `chartXSelection(value:)`, `chartXSelection(range:)`, `chartGesture`, `chartScrollableAxes`, `chartXVisibleDomain`, `chartScrollPosition`, all iOS 17 ([WWDC23 10037](https://developer.apple.com/videos/play/wwdc2023/10037/); [docs](https://developer.apple.com/documentation/swiftui/view/chartxselection(value:))).

## Swift Charts vectorized plots (iOS 18)

- `LinePlot`, `AreaPlot`, `PointPlot`, `RectanglePlot`, `RulePlot`, `BarPlot`, `SectorPlot`, all iOS 18 ([LinePlot](https://developer.apple.com/documentation/charts/lineplot), [RectanglePlot](https://developer.apple.com/documentation/charts/rectangleplot), [RulePlot](https://developer.apple.com/documentation/charts/ruleplot), [updates](https://developer.apple.com/documentation/updates/swiftcharts)). "Plot large collections of data with greater efficiency."
- One plot per collection: `LinePlot(data, x:, y:, series:)` with key paths; styling by key path, uniform across the plot ([LinePlot](https://developer.apple.com/documentation/charts/lineplot); [VectorizedChartContent](https://developer.apple.com/documentation/charts/vectorizedchartcontent)). A run id in `series` breaks lines at gaps (inference from the `series:` initializer).
- Apple's performance advice: stored properties, not computed; group data by style; give known styles and chart bounds up front ([WWDC24 10155](https://developer.apple.com/videos/play/wwdc2024/10155/), 11:27). No benchmark or size threshold is published.
- Identity: plots have no per-element `id`. How a `LinePlot` animates a data or domain change isn't documented; the talk says only that a plot "animates smoothly" while scrubbing a linked chart. *Unconfirmed.*
- Scrolling with the clock means changing `chartXScale(domain:)` every frame from a `TimelineView`, rebuilding the chart body per frame. Its cost is *unmeasured*.
- Accessibility modifiers exist on vectorized content (`accessibilityLabel`, `accessibilityValue`, `accessibilityHidden`) ([VectorizedChartContent](https://developer.apple.com/documentation/charts/vectorizedchartcontent)). Whether the default Audio Graph covers plots as it does marks is *unconfirmed*.
- `Chart3D` and `SurfacePlot` (iOS 26) are for 3D shape over exact values, and need interaction to read ([WWDC25 313](https://developer.apple.com/videos/play/wwdc2025/313/); [Chart3D](https://developer.apple.com/documentation/charts/chart3d)). Not for this graph, and above our iOS 18 floor.
- No Swift Charts headline at WWDC26 that I could find in Apple's sources. A forum thread reports [bar mark bugs on iOS 27 betas](https://developer.apple.com/forums/thread/835801). *Low confidence* that nothing relevant shipped.

## SwiftUI Canvas + TimelineView (current)

- Canvas is immediate mode; it "doesn't offer interactivity or accessibility for individual elements", but "might provide better performance for a complex drawing that involves dynamic data" ([Canvas](https://developer.apple.com/documentation/swiftui/canvas)). Apple introduced it for when per-view "bookkeeping and storage" is too much ([WWDC21 10021](https://developer.apple.com/videos/play/wwdc2021/10021/)).
- `TimelineView(.animation(minimumInterval:paused:))` updates "no more quickly than the provided interval" and works like a display link ([schedule](https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:)); [WWDC21 10021](https://developer.apple.com/videos/play/wwdc2021/10021/)). The system may use a slower `cadence` than asked ([TimelineView](https://developer.apple.com/documentation/swiftui/timelineview)).
- Movement: every point's x comes from one edge time, so all lines move at one speed whatever the refresh rate. This is the property the owner wants; keep it in any engine.
- Cost: the Canvas closure rebuilds and strokes every path each frame on the main actor, ~5,400 points at up to 30 fps today. `rendersAsynchronously` lets the canvas present asynchronously ([docs](https://developer.apple.com/documentation/swiftui/canvas/rendersasynchronously)); its effect here is *unmeasured*.
- Cheaper variant (inference): closed points never change, so build each line's `Path` in absolute time once per closed bucket, and per frame apply only a translation. Built-in animatable effects run "off the main thread and without calling into any of your view code" ([WWDC23 10156](https://developer.apple.com/videos/play/wwdc2023/10156/); `scaleEffect` is the example named, `offset` is *unconfirmed*).
- Accessibility: none for free. `accessibilityChartDescriptor(_:)` "may be applied to any View that represents a chart" and drives Audio Graphs ([docs](https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:)); [Audio graph guide](https://developer.apple.com/documentation/accessibility/representing-chart-data-as-an-audio-graph)).
- Selection, axes, gaps, shading, markers and range transitions are all ours to write; the current file already draws gaps, the no-data region and the loss strip.

## Core Animation or Metal via UIViewRepresentable

- `CAShapeLayer.path` is animatable, but "if the two paths have a different number of control points or segments the results are undefined" ([docs](https://developer.apple.com/documentation/quartzcore/cashapelayer/path)). So don't animate the path: one layer per line, path in absolute time, replaced when a bucket closes, scrolled by animating the layer's position.
- Core Animation "does all of the frame-by-frame drawing for you in hardware"; the render tree, private to Core Animation, performs the animations ([Core Animation Basics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html)). Rendering happens in the render server, "a separate process" ([tech talk 10855](https://developer.apple.com/videos/play/tech-talks/10855/)). A linear position animation therefore costs the app nothing per frame (inference).
- Shape rasterisation "may favor speed over accuracy" ([CAShapeLayer](https://developer.apple.com/documentation/quartzcore/cashapelayer)).
- Per-frame code: `CADisplayLink`, or iOS 18 `UIUpdateLink`, tied to a view and its display ([UIUpdateLink](https://developer.apple.com/documentation/uikit/uiupdatelink)).
- Costs: axes, labels, selection, Dark Mode (`CGColor` must be re-resolved on trait change), and accessibility (`AXChart`) are all ours. Metal (`MTKView`) adds a shader pipeline for a load Core Animation already handles; not worth it at 5,400 points (judgement).

## Third-party libraries

| Library | Last release | Engine | Notes |
|---|---|---|---|
| [DGCharts](https://github.com/ChartsOrg/Charts) (ex-Charts) | 5.1.0, 2024-02-15; last commit 2026-03-04 (docs) | Core Graphics in `UIView.draw(_:)` (`LineChartRenderer.swift`) | Swift 5 language mode (`Package.swift`), own `Animator` on a display link, `UIAccessibilityElement`s but no `AXChart`, no NaN gap handling in `LineChartRenderer` at `1bad546`. Looks Android-ported, not iOS. |
| [SciChart iOS](https://www.scichart.com/frequently-asked-questions/ios-macos/) | *Unconfirmed* | Metal, OpenGL ES fallback | Commercial (trial only on the FAQ). SwiftUI via `UIViewRepresentable`. No accessibility statement. |
| [AppPear/ChartView](https://github.com/AppPear/ChartView) | 2.0.0, 2026-03-02 | SwiftUI shapes | iOS 13 floor; line, bar, pie, rings. No time-series, gap or a11y features seen in the README. |
| [willdale/SwiftUICharts](https://github.com/willdale/SwiftUICharts) | 2.10.4, 2025-04-05 | SwiftUI shapes | iOS 14 floor; no release since. |

None beats Swift Charts on platform look, accessibility or maintenance (judgement).

## Comparison

| | Marks | Vectorized plots | Canvas + TimelineView | Core Animation |
|---|---|---|---|---|
| ~18 × 300 pts at 30–60 fps | Poor: Apple steers large data away from marks | Built for it; per-frame domain change *unmeasured* | Full redraw per frame, *unmeasured*; cached-path variant cheaper | Path rebuilt once per bucket; scroll is free |
| Scroll with the clock | Per-mark identity; failed here | Domain per frame; identity undocumented | Exact, one edge time | Linear position animation in the render server |
| Range switch | Mark animation | Undocumented | Hand-written | Hand-written |
| Gaps, shading, rules | Yes | Yes (`series`, `RectanglePlot`, `RulePlot`) | Hand-drawn (done) | Hand-drawn |
| VoiceOver, Audio Graphs | Free | Modifiers exist; default *unconfirmed* | `accessibilityChartDescriptor` | `AXChart` |
| Scrubbing | `chartXSelection` | `chartXSelection` | Hand-written gesture | Hand-written gesture |
| Dark mode | Free | Free | Palette resolved per frame | Re-resolve `CGColor` |
| Maintenance | Apple | Apple, iOS 18 | Apple | Apple |

## ProMotion and Reduce Motion

- SwiftUI, UIKit and `CAAnimation` get automatic frame pacing. On iPhone, `CADisplayLink` and `CAAnimation` get no rate above 60 Hz unless `CADisableMinimumFrameDurationOnPhone` is `true` in Info.plist ([ProMotion guide](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)). This app doesn't set it. Whether the key affects a SwiftUI `TimelineView` is *unconfirmed*.
- Ask for a range, not a rate: `preferredFrameRateRange` is best effort, limited by Low Power Mode, thermals and accessibility settings; rates are factors of the display maximum ([docs](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)). Apple: "choose the lowest frame rate that achieve's your desired visual flow"; drive motion from `targetTimestamp` ([ProMotion guide](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)).
- A slow scroll needs few frames. A ~340 pt plot moves 5.7 pt/s on 1m and 0.4 pt/s on 15m (arithmetic), so 30 Hz on 1m and the current `span / 600` interval elsewhere suffice. The frame budget is 16.7 ms at 60 Hz, 8.3 ms at 120 Hz (arithmetic).
- Reduce Motion: "reduce automatic and repetitive animations" ([HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)); "UI should avoid large animations" when `accessibilityReduceMotion` is true ([docs](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)). A chart that glides forever is automatic and repetitive. With it on, step the edge once per closed bucket and crossfade range switches. The app reads neither today.
- HIG: animate chart changes so people notice them, but also signal them another way for VoiceOver users and people with animation off ([HIG Charts](https://developer.apple.com/design/human-interface-guidelines/charts), Best practices). Make the plot area the scrub target ([same](https://developer.apple.com/design/human-interface-guidelines/charts)). Keep one chart style across charts of one dataset ([HIG Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)).

## For this app

Keep the clock-driven model: one edge time, every x derived from it, closed points fixed. That alone gives consistent movement in any engine. Choose the renderer by measurement between two candidates:

1. **Swift Charts vectorized plots**, preferred if they hold the budget: native axes, look, selection, Audio Graphs, and one engine for the main chart and sparklines (HIG consistency).
2. **Canvas with cached closed paths**, otherwise: a `Path` per line per closed bucket in absolute time, translated per frame, with only the provisional edge redrawn; add `accessibilityChartDescriptor` and a scrub gesture. Core Animation is the step after this if the translation alone still hitches.

Drop marks and third-party libraries. Add Reduce Motion handling and an `accessibilityChartDescriptor` (or confirm the plot's default) whichever wins. Confidence: **medium** that one of the two passes, **low** on which.

### Prototype

- Build both in a `#Preview`-able screen fed by `fixtures/`, scaled to 6 Targets × 3 Links × 300 points, with Paused, all-lost, provisional and Link-change buckets, on 1m and 15m, light and dark.
- Vectorized: one `LinePlot` with `series` = Target·Link·run, `RectanglePlot` for Paused, no-data and loss, `RulePlot` for Link changes, `PointPlot` for the provisional point and loss marks, domain set from a `TimelineView` at 30 Hz.
- Test a range switch (15m → 1h → 15m) with `withAnimation(.smooth)` on each, and check how `LinePlot` interpolates.
- Measure on an iPhone with ProMotion and on a 60 Hz one, release build:
  - Instruments 26 SwiftUI instrument: Long View Body Updates and Update Groups per frame ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/)).
  - Animation Hitches template: hitch time ratio under 5 ms/s is "good", 5–10 "should be investigated", over 10 "greatly impacting" ([tech talk 10855](https://developer.apple.com/videos/play/tech-talks/10855/)). Run 60 s of 1m scrolling, then the range switch.
  - Time Profiler: main-thread ms per frame against the 16.7/8.3 ms budget.
  - With Reduce Motion on: the edge steps and nothing glides.
  - VoiceOver: Describe chart and Play Audio Graph both work.
- Decide in an ADR, with the numbers.
