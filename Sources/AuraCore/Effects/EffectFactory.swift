import Foundation

public enum EffectFactory {
    public static func make(_ settings: EffectSettings) -> Effect {
        let effect = makeCold(settings)
        (effect as? FlameGridEffect)?.warmUp()
        return effect
    }

    private static func makeCold(_ settings: EffectSettings) -> Effect {
        switch settings.kind {
        case .off: OffEffect()
        case .staticColor: StaticEffect(settings: settings)
        case .breathing: BreathingEffect(settings: settings)
        case .spectrum: SpectrumEffect(settings: settings)
        case .wave: WaveEffect(settings: settings)
        case .flow: FlowEffect(settings: settings)
        case .morph: MorphEffect(settings: settings)
        case .starlight: StarlightEffect(settings: settings)
        case .orbit: OrbitEffect(settings: settings)
        case .wheel: WheelEffect(settings: settings)
        case .hearth: HearthFlame(settings: settings)
        case .inferno: InfernoFlame(settings: settings)
        case .embers: EmbersFlame(settings: settings)
        case .wisp: WispFlame(settings: settings)
        case .wildfire: WildfireFlame(settings: settings)
        }
    }

    /// Overlay layers enabled by the reactive settings, bottom to top.
    public static func overlays(_ settings: ReactiveSettings) -> [OverlayLayer] {
        var layers: [OverlayLayer] = []
        if settings.keyGlow { layers.append(KeyGlowLayer(settings: settings)) }
        if settings.ripple { layers.append(RippleLayer(settings: settings)) }
        if settings.clickPulse { layers.append(ClickPulseLayer(settings: settings)) }
        return layers
    }
}
