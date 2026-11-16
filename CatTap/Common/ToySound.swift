import AVFoundation
import os

/// プレミアムのおもちゃの効果音。
/// 音の素材は使わず、初めて鳴らすときにコードで合成して、起動中は使い回す。
/// 同じ音が続いても機械的に聞こえないように、音ごとに少しずつ違う鳴り方をいくつか持つ
enum ToySound: Int, CaseIterable {
    case mouseHit, mouseMove
    case butterflyHit, butterflyMove
    case laserHit, laserMove
    case teaserHit, teaserMove
    case yarnHit, yarnMove
    case photoHit, photoMove

    /// 当たったときの音。無料の虫・鳥・魚は nil にして、今までどおり papa.mp3 を鳴らす
    static func hit(for toy: Toy) -> ToySound? {
        switch toy {
        case .standard: return nil
        case .mouse: return .mouseHit
        case .butterfly: return .butterflyHit
        case .laser: return .laserHit
        case .teaser: return .teaserHit
        case .yarn: return .yarnHit
        case .photo: return .photoHit
        }
    }

    /// 動いている間にときどき鳴らす音
    static func move(for toy: Toy) -> ToySound? {
        switch toy {
        case .standard: return nil
        case .mouse: return .mouseMove
        case .butterfly: return .butterflyMove
        case .laser: return .laserMove
        case .teaser: return .teaserMove
        case .yarn: return .yarnMove
        case .photo: return .photoMove
        }
    }

    /// 動いている間の音を、前に鳴らしてから次に鳴らすまでにあける最短の時間（秒）
    static func moveInterval(for toy: Toy) -> TimeInterval {
        switch toy {
        case .mouse, .laser: return 1.2
        case .butterfly: return 1.6
        case .teaser, .photo: return 2.2
        default: return 3
        }
    }

    /// 1 つの音が持つ鳴り方の数
    static let variantCount = 4

    /// 音の中身。本物の鳴き声や物音に近づけるために、高さ・強さ・間を不規則に揺らし、
    /// ノイズを響きに通して作る。乱数の種を音と鳴り方ごとに決めているので、毎回同じ音になる
    fileprivate func synthesize(variant: Int) -> [Float] {
        var synth = Synth(seed: UInt32(rawValue * ToySound.variantCount + variant + 1) &* 2_654_435_761)
        switch self {
        case .mouseHit:
            synth.mouseHit(variant)
            return synth.finished(loudness: Synth.hitLoudness, room: 0.5)
        case .mouseMove:
            synth.mouseMove(variant)
            return synth.finished(loudness: Synth.moveLoudness, room: 0.6)
        case .butterflyHit:
            synth.butterflyHit(variant)
            return synth.finished(loudness: Synth.hitLoudness * 0.8, room: 0.25)
        case .butterflyMove:
            synth.butterflyMove(variant)
            return synth.finished(loudness: Synth.moveLoudness * 0.9, room: 0.25)
        case .laserHit:
            synth.laserHit(variant)
            return synth.finished(loudness: Synth.hitLoudness * 0.6, room: 0.6)
        case .laserMove:
            synth.laserMove(variant)
            return synth.finished(loudness: Synth.moveLoudness * 0.75, room: 0.6)
        case .teaserHit:
            synth.teaserHit(variant)
            return synth.finished(loudness: Synth.hitLoudness, room: 0.3)
        case .teaserMove:
            synth.teaserMove(variant)
            return synth.finished(loudness: Synth.moveLoudness, room: 0.3)
        case .yarnHit:
            synth.yarnHit(variant)
            return synth.finished(loudness: Synth.hitLoudness * 0.85, room: 0.3)
        case .yarnMove:
            synth.yarnMove(variant)
            return synth.finished(loudness: Synth.moveLoudness, room: 0.3)
        case .photoHit:
            synth.photoHit(variant)
            return synth.finished(loudness: Synth.hitLoudness, room: 0.6)
        case .photoMove:
            synth.photoMove(variant)
            return synth.finished(loudness: Synth.moveLoudness, room: 0.6)
        }
    }
}

/// 合成した効果音を鳴らす。おもちゃの左右の位置に合わせて、音を左右に振り分ける。
/// メインスレッドから使う
final class ToySoundPlayer {

    static let shared = ToySoundPlayer()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    /// 合成した音。音と鳴り方の組ごとに持つ
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    /// 合成している途中の組
    private var pendingKeys: Set<Int> = []
    /// 音ごとの、前に鳴らした鳴り方
    private var lastVariants: [ToySound: Int] = [:]
    /// 合成の間に画面の動きが止まらないように、合成は裏でする。
    /// すぐ鳴らす音が待たされないように、先に作っておくだけの音は別の列で作る
    private let synthesisQueue = DispatchQueue(label: "kayashida.CatTap.ToySound", qos: .userInitiated)
    private let prewarmQueue = DispatchQueue(label: "kayashida.CatTap.ToySound.prewarm", qos: .utility)
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!

    private init() {
        // 音が重なっても切れないように、鳴らす口を 6 つ用意して順番に使う
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        // イヤホンの抜き差しなどで止まったら、次に鳴らすときに動かし直す
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: engine,
                                               queue: .main) { [weak self] _ in
            self?.startIfNeeded()
        }
    }

    /// - Parameters:
    ///   - volume: 0〜1
    ///   - pan: -1（左）〜 1（右）
    func play(_ sound: ToySound, volume: Float, pan: Float) {
        startIfNeeded()
        guard engine.isRunning else { return }
        let variants = 0..<ToySound.variantCount
        var ready = variants.filter { buffers[key(for: sound, variant: $0)] != nil }
        guard !ready.isEmpty else {
            // 初めて鳴らす音は、作り終わってから鳴らす。残りの鳴り方も続けて作っておく
            let first = Int.random(in: variants)
            prepare(sound, variant: first, on: synthesisQueue) { [weak self] buffer in
                self?.lastVariants[sound] = first
                self?.schedule(buffer, volume: volume, pan: pan)
            }
            for variant in variants where variant != first {
                prepare(sound, variant: variant, on: prewarmQueue, completion: nil)
            }
            return
        }
        // 同じ鳴り方が続かないように、前とは違うものを選ぶ
        if 1 < ready.count, let last = lastVariants[sound] {
            ready.removeAll { $0 == last }
        }
        guard let variant = ready.randomElement(), let buffer = buffers[key(for: sound, variant: variant)] else { return }
        lastVariants[sound] = variant
        schedule(buffer, volume: volume, pan: pan)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, volume: Float, pan: Float) {
        guard engine.isRunning else { return }
        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        player.stop()
        // 本物の物音のように、鳴らすたびに強さを少し変える
        player.volume = volume * Float.random(in: 0.85...1)
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    private func startIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            // 消音モードのときは鳴らさず、ほかのアプリの音楽も止めない
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            logger.notice("効果音の再生を始めました")
        } catch {
            logger.error("効果音を鳴らせませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    private let logger = Logger(subsystem: "kayashida.CatTap", category: "ToySound")

    private func key(for sound: ToySound, variant: Int) -> Int {
        sound.rawValue * ToySound.variantCount + variant
    }

    /// 音を裏で合成して、覚えておく。completion は、できあがったときにメインスレッドで呼ぶ
    private func prepare(_ sound: ToySound,
                         variant: Int,
                         on queue: DispatchQueue,
                         completion: ((AVAudioPCMBuffer) -> Void)?) {
        let key = key(for: sound, variant: variant)
        guard buffers[key] == nil, !pendingKeys.contains(key) else { return }
        pendingKeys.insert(key)
        queue.async { [weak self] in
            let samples = sound.synthesize(variant: variant)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingKeys.remove(key)
                guard let buffer = self.makeBuffer(samples) else { return }
                self.buffers[key] = buffer
                completion?(buffer)
            }
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

/// 短い効果音を作るための、ごく小さな合成器。毎回同じ音になるように、乱数も決まった順で作る
private struct Synth {

    static let sampleRate: Double = 44_100
    /// 当たったときの音と、動いている間の音の、聞こえる大きさの目安
    static let hitLoudness = 0.1
    static let moveLoudness = 0.058

    /// 音の部品を重ねていく場所
    private var mix: [Double] = []
    /// 乱数の種。決まった値から始めるので、毎回同じ音になる
    private var seed: UInt32

    init(seed: UInt32) {
        self.seed = seed == 0 ? 1 : seed
        for _ in 0..<8 {
            _ = unit()
        }
    }

    // MARK: 乱数

    /// 0〜1 の乱数（xorshift）
    mutating func unit() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Double(seed) / 4_294_967_296
    }

    /// -1〜1 のノイズ
    mutating func noise() -> Double {
        unit() * 2 - 1
    }

    mutating func pick(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    /// 値を ±amount の割合でずらす
    mutating func vary(_ value: Double, by amount: Double) -> Double {
        value * (1 + amount * noise())
    }

    /// -1〜1 の間をなめらかに揺れ続ける値。高さや強さを不規則に揺らすのに使う
    mutating func wander(count: Int, rate: Double) -> [Double] {
        let step = max(1, Int(Self.sampleRate / rate))
        var result = [Double](repeating: 0, count: count)
        var from = noise(), to = noise()
        var start = 0
        while start < count {
            let end = min(count, start + step)
            for index in start..<end {
                let ratio = Double(index - start) / Double(step)
                result[index] = from + (to - from) * (0.5 - 0.5 * cos(.pi * ratio))
            }
            from = to
            to = noise()
            start = end
        }
        return result
    }

    // MARK: 音の部品

    /// 音量の形
    enum Shape {
        /// なめらかに立ち上がって、なめらかに消える。peak は山の位置（0〜1）
        case swell(peak: Double)
        /// すばやく立ち上がって、だんだん消える。attack は立ち上がりの秒数
        case strike(attack: Double)

        func level(at time: Double, duration: Double) -> Double {
            switch self {
            case .swell(let peak):
                let position = time / duration
                if position < peak {
                    return 0.5 - 0.5 * cos(.pi * position / peak)
                }
                return 0.5 + 0.5 * cos(.pi * (position - peak) / (1 - peak))
            case .strike(let attack):
                if time < attack {
                    return 0.5 - 0.5 * cos(.pi * time / attack)
                }
                let rest = (time - attack) / max(duration - attack, 0.001)
                return exp(-6 * rest) * (1 - rest)
            }
        }
    }

    /// ねずみや小鳥の鳴き声を 1 つ。倍音を重ねた声の高さと強さを不規則に揺らし、かすれと息の音を混ぜる
    /// - Parameters:
    ///   - pitch: 声の高さの動き。位置（0〜1）と Hz の点を、なめらかにつなぐ
    ///   - harmonics: 基音、2 倍音、3 倍音…の強さ
    ///   - jitter: 高さの不規則な揺れ（割合）
    ///   - roughness: 声のかすれ
    ///   - breath: 息の音の強さ
    ///   - subharmonic: 半分の高さの成分。裏返ったような濁りになる
    ///   - flutter: 細かく震わせる速さ（Hz）、高さの幅（割合）、強さの幅（0〜1）
    ///   - formant: 口や体の響きの中心（Hz）
    mutating func call(at start: Double,
                       duration: Double,
                       amplitude: Double,
                       pitch: [(position: Double, frequency: Double)],
                       harmonics: [Double],
                       jitter: Double,
                       roughness: Double,
                       breath: Double,
                       subharmonic: Double = 0,
                       flutter: (rate: Double, pitch: Double, level: Double)? = nil,
                       formant: Double,
                       attack: Double,
                       release: Double) {
        let rate = Self.sampleRate
        let count = Int(duration * rate)
        guard 1 < count, 1 < pitch.count else { return }
        let slowDrift = wander(count: count, rate: 30)
        let fastDrift = wander(count: count, rate: 220)
        let shimmers = harmonics.map { _ in wander(count: count, rate: 70) }
        let growl = wander(count: count, rate: 28)
        var hoarse = Biquad(.lowPass, frequency: 1_400, q: 0.6)
        var breathBand = Biquad(.bandPass, frequency: pitch[0].frequency * 1.6, q: 1.2)
        var body = Biquad(.bandPass, frequency: formant, q: 1.8)
        var layer = [Double](repeating: 0, count: count)
        var phase = 0.0
        var flutterPhase = pick(0...(2 * .pi))
        var segment = 0
        for index in 0..<count {
            let time = Double(index) / rate
            let position = Double(index) / Double(count)
            while segment + 2 < pitch.count, pitch[segment + 1].position <= position {
                segment += 1
            }
            let from = pitch[segment], to = pitch[segment + 1]
            let ratio = min(max((position - from.position) / max(to.position - from.position, 0.001), 0), 1)
            var frequency = from.frequency + (to.frequency - from.frequency) * (0.5 - 0.5 * cos(.pi * ratio))
            frequency *= 1 + jitter * (slowDrift[index] + 0.6 * fastDrift[index])
            var level = 1.0
            if let flutter {
                flutterPhase += 2 * .pi * flutter.rate * (1 + 0.35 * slowDrift[index]) / rate
                let wave = sin(flutterPhase)
                frequency *= 1 + flutter.pitch * wave
                level -= flutter.level * (0.5 + 0.5 * wave)
            }
            phase += 2 * .pi * frequency / rate

            var value = 0.0
            for (order, strength) in harmonics.enumerated() {
                // 高すぎる倍音は折り返して濁るので、鳴らさない
                let partial = frequency * Double(order + 1)
                if 17_000 <= partial { break }
                let guardBand = min(1, (17_000 - partial) / 2_000)
                value += strength * (1 + 0.3 * shimmers[order][index]) * guardBand * sin(phase * Double(order + 1))
            }
            if 0 < subharmonic {
                value += subharmonic * max(0, growl[index]) * (sin(phase * 0.5) + 0.5 * sin(phase * 1.5))
            }
            value *= 1 + roughness * 3 * hoarse.process(noise())
            if index % 8 == 0 {
                breathBand.set(.bandPass, frequency: frequency * 1.6, q: 1.2)
            }
            value += breath * 2 * breathBand.process(noise())
            value = 0.35 * value + body.process(value)

            if time < attack {
                level *= 0.5 - 0.5 * cos(.pi * time / attack)
            }
            let remaining = duration - time
            if remaining < release {
                level *= 0.5 - 0.5 * cos(.pi * remaining / release)
            }
            layer[index] = value * level
        }
        add(layer, at: start, peak: amplitude)
    }

    /// 硬いものや床が鳴る小さな音。物が当たる一瞬の力で、いくつかの響きを鳴らす
    /// - Parameters:
    ///   - strike: 当たっている時間（秒）。短いほど硬く、高い響きまで鳴る
    ///   - resonances: 響きの高さ（Hz）、消えるまでの時間の目安（秒）、強さ
    mutating func tap(at start: Double,
                      amplitude: Double,
                      strike: Double,
                      resonances: [(frequency: Double, decay: Double, level: Double)]) {
        let rate = Self.sampleRate
        let strikeCount = max(4, Int(strike * rate))
        let longest = resonances.map(\.decay).max() ?? 0
        let count = strikeCount + Int(longest * 7 * rate)
        var excitation = [Double](repeating: 0, count: count)
        for index in 0..<strikeCount {
            excitation[index] = 0.5 - 0.5 * cos(2 * .pi * (Double(index) + 0.5) / Double(strikeCount))
        }
        var layer = [Double](repeating: 0, count: count)
        for resonance in resonances {
            let quality = max(0.5, .pi * resonance.frequency * resonance.decay)
            var filter = Biquad(.resonator, frequency: resonance.frequency, q: quality)
            for index in 0..<count {
                layer[index] += resonance.level * filter.process(excitation[index])
            }
        }
        // 響きの終わりを無音につなぐ
        let fade = min(count, Int(0.002 * rate))
        for index in 0..<fade {
            layer[count - 1 - index] *= Double(index) / Double(fade)
        }
        add(layer, at: start, peak: amplitude)
    }

    /// 空気や繊維が立てる、やわらかい音。帯域を絞ったノイズを shape の形で鳴らす
    /// - Parameters:
    ///   - edge: 音が小さいときの帯域の中心（Hz）
    ///   - center: 音がいちばん大きいときの帯域の中心（Hz）
    ///   - flicker: 強さを不規則に揺らす速さ（Hz）と深さ（0〜1）
    mutating func air(at start: Double,
                      duration: Double,
                      amplitude: Double,
                      from edge: Double,
                      to center: Double,
                      q: Double,
                      shape: Shape,
                      flicker: (rate: Double, depth: Double)? = nil) {
        let rate = Self.sampleRate
        let count = Int(duration * rate)
        guard 1 < count else { return }
        let wobble = flicker.map { wander(count: count, rate: $0.rate) }
        var band = Biquad(.bandPass, frequency: edge, q: q)
        // 帯域より上は、こもって聞こえるようにしっかり落とす
        var firstCut = Biquad(.lowPass, frequency: edge * 2, q: 0.6)
        var secondCut = firstCut
        var layer = [Double](repeating: 0, count: count)
        for index in 0..<count {
            var level = shape.level(at: Double(index) / rate, duration: duration)
            if index % 8 == 0 {
                let frequency = edge + (center - edge) * level
                band.set(.bandPass, frequency: frequency, q: q)
                firstCut.set(.lowPass, frequency: frequency * 2, q: 0.6)
                secondCut.set(.lowPass, frequency: frequency * 2, q: 0.6)
            }
            if let wobble, let flicker {
                level *= 1 - flicker.depth * (0.5 + 0.5 * wobble[index])
            }
            layer[index] = secondCut.process(firstCut.process(band.process(noise()))) * level
        }
        add(layer, at: start, strength: amplitude)
    }

    /// 乾いた草がこすれる音。ごく短いノイズの粒を、高さを変えながら不規則にたくさん鳴らす
    /// - Parameters:
    ///   - density: いちばん多いときの、1 秒あたりの粒の数
    ///   - peak: 粒がいちばん多くなる位置（0〜1）
    mutating func rustle(at start: Double,
                         duration: Double,
                         amplitude: Double,
                         density: Double,
                         peak: Double,
                         low: Double,
                         high: Double) {
        let rate = Self.sampleRate
        let count = Int(duration * rate)
        guard 1 < count else { return }
        let bandCount = 5
        var filters: [Biquad] = []
        for band in 0..<bandCount {
            // 帯域の中心を low〜high に並べて、少しずつずらす
            let ratio = (Double(band) + pick(0.2...0.8)) / Double(bandCount)
            filters.append(Biquad(.bandPass, frequency: low * pow(high / low, ratio), q: pick(1.4...2.8)))
        }
        var targets = [Double](repeating: 0, count: bandCount)
        var levels = [Double](repeating: 0, count: bandCount)
        var decays = [Double](repeating: 0.99, count: bandCount)
        var layer = [Double](repeating: 0, count: count)
        var ceiling = Biquad(.lowPass, frequency: 11_000, q: 0.6)
        let shape = Shape.swell(peak: peak)
        for index in 0..<count {
            let swell = shape.level(at: Double(index), duration: Double(count))
            if unit() < density * swell * swell / rate {
                // 小さな粒が多く、ときどき大きな粒が混じる
                let band = min(bandCount - 1, Int(unit() * Double(bandCount)))
                let strength = 0.15 + 0.85 * pow(unit(), 2)
                targets[band] = max(targets[band], strength)
                decays[band] = exp(-1 / (pick(0.0003...0.0025) * rate))
            }
            var value = 0.0
            for band in 0..<bandCount {
                levels[band] += (targets[band] - levels[band]) * 0.3
                value += filters[band].process(noise()) * levels[band]
                targets[band] *= decays[band]
            }
            layer[index] = ceiling.process(value) * swell.squareRoot()
        }
        // 飛び抜けて大きい粒だけを、なめらかにおさえる
        let limit = 8 * (layer.reduce(0) { $0 + $1 * $1 } / Double(count)).squareRoot()
        if 0 < limit {
            for index in 0..<count {
                let ratio = layer[index] / limit
                layer[index] /= (1 + ratio * ratio).squareRoot()
            }
        }
        add(layer, at: start, strength: amplitude)
    }

    /// 部品を重ねる。peak は、いちばん大きいところの値
    private mutating func add(_ layer: [Double], at start: Double, peak: Double) {
        let largest = layer.reduce(0) { max($0, abs($1)) }
        guard 0 < largest else { return }
        add(layer, at: start, gain: peak / largest)
    }

    /// ノイズの部品を重ねる。strength は平均の強さの 3 倍で、peak とだいたい同じ大きさになる
    private mutating func add(_ layer: [Double], at start: Double, strength: Double) {
        let power = layer.reduce(0) { $0 + $1 * $1 } / Double(layer.count)
        guard 0 < power else { return }
        add(layer, at: start, gain: strength / 3 / power.squareRoot())
    }

    private mutating func add(_ layer: [Double], at start: Double, gain: Double) {
        let offset = max(0, Int(start * Self.sampleRate))
        if mix.count < offset + layer.count {
            mix += [Double](repeating: 0, count: offset + layer.count - mix.count)
        }
        for index in 0..<layer.count {
            mix[offset + index] += layer[index] * gain
        }
    }

    // MARK: 仕上げ

    /// 部屋の短い響きを足し、低すぎる成分を落とし、聞こえる大きさをそろえて、両端を無音につなぐ
    /// - Parameters:
    ///   - loudness: 聞こえる大きさの目安
    ///   - room: 部屋の響きの量
    func finished(loudness: Double, room: Double) -> [Float] {
        let rate = Self.sampleRate
        guard !mix.isEmpty else { return [] }
        let tailCount = Int(0.065 * rate)
        var output = mix + [Double](repeating: 0, count: tailCount)

        // 部屋の響き。小さな反射を、決まった位置にまばらに足す
        if 0 < room {
            var tail = [Double](repeating: 0, count: output.count)
            var reflections = Synth(seed: 0x5EED_1234)
            for _ in 0..<22 {
                let delay = reflections.pick(0.005...0.06)
                let sign: Double = reflections.unit() < 0.5 ? -1 : 1
                let gain = sign * 0.2 * room * exp(-delay / 0.018)
                let offset = Int(delay * rate)
                for index in 0..<mix.count {
                    tail[offset + index] += gain * mix[index]
                }
            }
            // 反射は、高い音と低い音が減って返ってくる
            var soften = Biquad(.lowPass, frequency: 4_500, q: 0.6)
            var thin = Biquad(.highPass, frequency: 350, q: 0.6)
            for index in output.indices {
                output[index] += thin.process(soften.process(tail[index]))
            }
        }

        // 低すぎる成分と、片寄り（直流）を落とす
        var rumble = Biquad(.highPass, frequency: 130, q: 0.7)
        for index in output.indices {
            output[index] = rumble.process(output[index])
        }

        // 聞こえる大きさをそろえる。大きすぎるときは、形を変えずに全体を下げる
        var gain = loudness / max(Self.loudness(of: output), 1e-9)
        let peak = output.reduce(0) { max($0, abs($1)) }
        if 0.85 < peak * gain {
            gain = 0.85 / peak
        }

        // 聞こえない終わりの部分を切って、両端を無音につなぐ
        var end = output.count
        while 1 < end, abs(output[end - 1]) < peak * 0.001 {
            end -= 1
        }
        end = min(output.count, end + Int(0.004 * rate))
        let fadeIn = min(end, Int(0.002 * rate))
        let fadeOut = min(end, Int(0.006 * rate))
        var samples = [Float](repeating: 0, count: end)
        for index in 0..<end {
            var value = output[index] * gain
            if index < fadeIn {
                value *= 0.5 - 0.5 * cos(.pi * Double(index) / Double(fadeIn))
            }
            if end - 1 - index < fadeOut {
                value *= 0.5 - 0.5 * cos(.pi * Double(end - 1 - index) / Double(fadeOut))
            }
            samples[index] = Float(value)
        }
        return samples
    }

    /// 耳に聞こえる大きさの目安。聞こえやすい高さに重みを付けて、いちばん大きい 60 ミリ秒の強さを測る。
    /// 全体の平均で比べると、まばらな音や低い音の大きさがそろわない
    private static func loudness(of samples: [Double]) -> Double {
        var low = Biquad(.highPass, frequency: 500, q: 0.5)
        var high = Biquad(.lowPass, frequency: 9_000, q: 0.5)
        var sums = [Double](repeating: 0, count: samples.count + 1)
        for index in samples.indices {
            let value = high.process(low.process(samples[index]))
            sums[index + 1] = sums[index] + value * value
        }
        let window = Int(0.06 * sampleRate)
        var loudest = 0.0
        var start = 0
        while true {
            let end = min(samples.count, start + window)
            loudest = max(loudest, sums[end] - sums[start])
            if end == samples.count { break }
            start += 64
        }
        return (loudest / Double(window)).squareRoot()
    }
}

/// 双二次フィルタ
private struct Biquad {

    enum Kind {
        case lowPass, highPass
        /// 帯域通過。中心の高さをそのまま通す
        case bandPass
        /// たたくと frequency の高さで鳴る響き
        case resonator
    }

    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(_ kind: Kind, frequency: Double, q: Double) {
        set(kind, frequency: frequency, q: q)
    }

    /// 鳴らしている途中で、係数だけを変える
    mutating func set(_ kind: Kind, frequency: Double, q: Double) {
        let omega = 2 * .pi * min(max(frequency, 20), 0.45 * Synth.sampleRate) / Synth.sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let a0 = 1 + alpha
        switch kind {
        case .lowPass:
            b0 = (1 - cosine) / 2 / a0
            b1 = (1 - cosine) / a0
            b2 = b0
        case .highPass:
            b0 = (1 + cosine) / 2 / a0
            b1 = -(1 + cosine) / a0
            b2 = b0
        case .bandPass:
            b0 = alpha / a0
            b1 = 0
            b2 = -b0
        case .resonator:
            b0 = 0.5 / a0
            b1 = 0
            b2 = -b0
        }
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}

// MARK: - おもちゃごとの音

private extension Synth {

    // MARK: ねずみ

    /// ねずみの鳴き声を 1 つ。キュッ
    /// - Parameters:
    ///   - top: いちばん高いところ（Hz）
    ///   - fall: 終わりの高さ（top に対する割合）
    mutating func squeak(at start: Double, duration: Double, amplitude: Double, top: Double, fall: Double = 0.8) {
        let top = vary(top, by: 0.04)
        call(at: start,
             duration: duration,
             amplitude: amplitude,
             pitch: [(0, top * pick(0.7...0.78)), (pick(0.16...0.3), top), (0.7, top * pick(0.88...0.95)), (1, top * fall)],
             harmonics: [1, 0.5, 0.2, 0.07],
             jitter: 0.03,
             roughness: 0.5,
             breath: 0.15,
             subharmonic: pick(0.05...0.3),
             flutter: (rate: pick(130...190), pitch: 0.02, level: 0.2),
             formant: 4_300,
             attack: 0.006,
             release: duration * 0.45)
    }

    /// 当たったとき。驚いて、キュッと鳴く
    mutating func mouseHit(_ variant: Int) {
        switch variant {
        case 0:
            squeak(at: 0.003, duration: pick(0.08...0.09), amplitude: 1, top: 4_200)
        case 1:
            squeak(at: 0.003, duration: 0.055, amplitude: 0.8, top: 3_900)
            squeak(at: 0.058 + pick(0.03...0.045), duration: 0.07, amplitude: 1, top: 4_400)
        case 2:
            squeak(at: 0.003, duration: pick(0.105...0.12), amplitude: 1, top: 4_000, fall: 0.68)
        default:
            squeak(at: 0.003, duration: 0.045, amplitude: 1, top: 4_500)
            squeak(at: 0.048 + pick(0.025...0.04), duration: 0.052, amplitude: 0.75, top: 4_100, fall: 0.72)
        }
    }

    /// 爪が硬い床に当たる音を 1 つ。チッ
    mutating func clawTap(at start: Double, amplitude: Double) {
        tap(at: start,
            amplitude: amplitude,
            strike: pick(0.00012...0.0002),
            resonances: [(vary(750, by: 0.15), 0.004, pick(0.15...0.3)),
                         (vary(1_900, by: 0.12), pick(0.003...0.005), pick(0.35...0.6)),
                         (vary(3_400, by: 0.15), pick(0.0015...0.003), 1),
                         (vary(6_200, by: 0.15), pick(0.0008...0.0015), pick(0.4...0.8))])
        // 爪が床をかすかにこする
        air(at: start, duration: 0.004, amplitude: amplitude * 0.25,
            from: 5_000, to: vary(8_000, by: 0.1), q: 1.2, shape: .strike(attack: 0.0005))
    }

    /// 動いているとき。小さな足音が続き、ときどきかすかに鳴く
    mutating func mouseMove(_ variant: Int) {
        var time = 0.003
        let steps = 7 + variant
        for _ in 0..<steps {
            clawTap(at: time, amplitude: pick(0.45...1))
            // 2 本の足が、ほぼ同時に着くことがある
            if unit() < 0.3 {
                clawTap(at: time + pick(0.005...0.009), amplitude: pick(0.3...0.6))
            }
            time += pick(0.022...0.04)
        }
        if variant % 2 == 1 {
            squeak(at: time + pick(0.01...0.03), duration: 0.045, amplitude: 0.4, top: 4_600)
        }
    }

    // MARK: ちょうちょ

    /// 羽ばたき 1 回ぶん。打ち下ろしと打ち上げの空気の音に、羽のかすかな紙のような音を重ねる
    mutating func wingBeat(at start: Double, period: Double, amplitude: Double) {
        let down = period * pick(0.5...0.6)
        air(at: start, duration: down, amplitude: amplitude,
            from: vary(380, by: 0.1), to: vary(1_150, by: 0.15), q: 1.1, shape: .swell(peak: 0.4))
        air(at: start + down * 0.2, duration: down * 0.6, amplitude: amplitude * 0.22,
            from: 2_600, to: vary(4_200, by: 0.2), q: 1.4, shape: .swell(peak: 0.35), flicker: (500, 0.7))
        air(at: start + down, duration: period - down, amplitude: amplitude * pick(0.35...0.5),
            from: 550, to: vary(1_500, by: 0.15), q: 1.2, shape: .swell(peak: 0.45))
    }

    /// 当たったとき。前足が羽に触れ、あわてて速く羽ばたく
    mutating func butterflyHit(_ variant: Int) {
        air(at: 0.003, duration: 0.02, amplitude: 0.5,
            from: 1_300, to: vary(3_000, by: 0.15), q: 1, shape: .strike(attack: 0.004))
        var time = 0.012
        var period = 1 / pick(20...24)
        let beats = 4 + variant % 3
        for beat in 0..<beats {
            wingBeat(at: time, period: period, amplitude: pow(0.82, Double(beat)) * pick(0.8...1))
            time += period
            period *= pick(1...1.12)
        }
    }

    /// 動いているとき。ゆっくりした羽ばたき
    mutating func butterflyMove(_ variant: Int) {
        var time = 0.003
        let beats = 4 + variant % 2
        let rhythm = 1 / pick(13...17)
        for beat in 0..<beats {
            let period = vary(rhythm, by: 0.1)
            // だんだん近づいて、遠ざかる
            let swell = sin(.pi * (Double(beat) + 0.8) / (Double(beats) + 0.6))
            wingBeat(at: time, period: period, amplitude: (0.4 + 0.6 * swell) * pick(0.85...1))
            time += period
        }
    }

    // MARK: レーザーポインター

    /// かすかに、チッ。小さく軽いものが鳴る音
    mutating func tick(at start: Double, amplitude: Double, pitch: Double) {
        tap(at: start,
            amplitude: amplitude,
            strike: 0.00016,
            resonances: [(vary(2_500, by: 0.04) * pitch, 0.0022, pick(0.35...0.55)),
                         (vary(4_000, by: 0.04) * pitch, 0.002, 1),
                         (vary(6_200, by: 0.04) * pitch, 0.0014, pick(0.45...0.7)),
                         (vary(9_000, by: 0.04) * pitch, 0.0008, pick(0.15...0.3))])
    }

    /// 当たったとき。スイッチを押して離すような、小さな音が 2 つ
    mutating func laserHit(_ variant: Int) {
        let pitch = vary(1, by: 0.03) * (1 + 0.04 * Double(variant - 1))
        tick(at: 0.003, amplitude: 1, pitch: pitch)
        tick(at: 0.003 + pick(0.038...0.06), amplitude: pick(0.4...0.6), pitch: pitch * pick(1.08...1.16))
    }

    /// 動いているとき。かすかな音が 1 つ
    mutating func laserMove(_ variant: Int) {
        tick(at: 0.003, amplitude: 1, pitch: 1.1 * (1 + 0.05 * Double(variant - 1)))
    }

    // MARK: ねこじゃらし

    /// 乾いた穂が 1 回ゆれる音。カサッ
    mutating func swish(at start: Double, duration: Double, amplitude: Double, density: Double, peak: Double) {
        rustle(at: start, duration: duration, amplitude: amplitude,
               density: density, peak: peak, low: 2_200, high: 9_500)
        // 穂が風を切る音
        air(at: start, duration: duration * 0.85, amplitude: amplitude * 0.4,
            from: 2_400, to: vary(5_600, by: 0.15), q: 0.8, shape: .swell(peak: peak))
    }

    /// 当たったとき。はじかれて、穂が大きくゆれる
    mutating func teaserHit(_ variant: Int) {
        swish(at: 0.003, duration: pick(0.16...0.2), amplitude: 1, density: pick(800...1_000), peak: pick(0.14...0.2))
        if variant % 2 == 1 {
            // ゆれ戻し
            swish(at: pick(0.1...0.13), duration: 0.11, amplitude: pick(0.3...0.45), density: 500, peak: 0.3)
        }
    }

    /// 動いているとき。カサカサと、不規則に何回かゆれる
    mutating func teaserMove(_ variant: Int) {
        var time = 0.003
        let count = 2 + variant % 2
        for _ in 0..<count {
            let duration = pick(0.09...0.15)
            swish(at: time, duration: duration, amplitude: pick(0.5...1), density: pick(450...650), peak: pick(0.25...0.5))
            time += duration * pick(0.6...0.95)
        }
    }

    // MARK: 毛糸玉

    /// 毛糸玉が床に当たる、こもった音を 1 つ
    mutating func woolBump(at start: Double, amplitude: Double) {
        // 床の低い響き
        tap(at: start,
            amplitude: amplitude * 0.35,
            strike: pick(0.0025...0.0035),
            resonances: [(vary(170, by: 0.08), 0.014, 0.25),
                         (vary(330, by: 0.1), 0.011, 0.8),
                         (vary(580, by: 0.1), 0.007, 1)])
        // 毛糸がつぶれる、やわらかい当たり
        air(at: start, duration: 0.12, amplitude: amplitude * 0.7,
            from: 420, to: vary(1_000, by: 0.1), q: 0.9, shape: .strike(attack: 0.006))
        // 毛羽のこすれ
        air(at: start + 0.002, duration: 0.05, amplitude: amplitude * 0.12,
            from: 1_400, to: 2_600, q: 1, shape: .strike(attack: 0.006), flicker: (400, 0.6))
    }

    /// 当たったとき。ぽふっと当たって、小さく弾む
    mutating func yarnHit(_ variant: Int) {
        woolBump(at: 0.003, amplitude: 1)
        let bounce = pick(0.085...0.125)
        woolBump(at: 0.003 + bounce, amplitude: pick(0.25...0.4))
        if variant % 2 == 1 {
            woolBump(at: 0.003 + bounce * pick(1.55...1.7), amplitude: pick(0.1...0.16))
        }
    }

    /// 動いているとき。床をころころ転がる
    mutating func yarnMove(_ variant: Int) {
        let duration = pick(0.3...0.36)
        // でこぼこした玉が転がる、低くこもった音
        air(at: 0.003, duration: duration, amplitude: 0.6,
            from: 300, to: vary(620, by: 0.1), q: 0.8, shape: .swell(peak: pick(0.3...0.5)), flicker: (pick(18...26), 0.75))
        // 毛羽が床をこする音
        air(at: 0.003, duration: duration, amplitude: 0.1,
            from: 900, to: 1_900, q: 0.9, shape: .swell(peak: 0.4), flicker: (120, 0.6))
        var time = pick(0.02...0.05)
        for _ in 0..<(3 + variant % 2) {
            woolBump(at: time, amplitude: pick(0.25...0.5))
            time += pick(0.06...0.1)
        }
    }

    // MARK: 写真のおもちゃ

    /// 小鳥の声を 1 つ。すばやく上がって、下がる
    /// - Parameters:
    ///   - rise: いちばん高くなる位置（0〜1）
    ///   - buzz: 声を細かく震わせる強さ。ジュッという濁った声になる
    mutating func chirp(at start: Double, duration: Double, amplitude: Double,
                        low: Double, high: Double, rise: Double = 0.18, buzz: Double = 0) {
        let low = vary(low, by: 0.04), high = vary(high, by: 0.04)
        call(at: start,
             duration: duration,
             amplitude: amplitude,
             pitch: [(0, low * pick(1.1...1.25)), (rise, high), (rise + (1 - rise) * 0.45, low + (high - low) * pick(0.35...0.5)), (1, low)],
             harmonics: [1, 0.42, 0.16, 0.06],
             jitter: 0.012,
             roughness: 0.22 + buzz * 0.4,
             breath: 0.05,
             flutter: 0 < buzz
                 ? (rate: pick(85...125), pitch: 0.05 * buzz, level: 0.6 * buzz)
                 : (rate: pick(180...260), pitch: 0.022, level: 0.15),
             formant: 3_800,
             attack: 0.004,
             release: duration * 0.5)
    }

    /// 当たったとき。小鳥が短くさえずる
    mutating func photoHit(_ variant: Int) {
        switch variant {
        case 0:
            chirp(at: 0.003, duration: 0.085, amplitude: 1, low: 2_600, high: 5_200)
        case 1:
            chirp(at: 0.003, duration: 0.038, amplitude: 0.75, low: 3_600, high: 5_500, rise: 0.55)
            chirp(at: 0.041 + pick(0.02...0.035), duration: 0.085, amplitude: 1, low: 2_500, high: 5_000)
        case 2:
            chirp(at: 0.003, duration: 0.06, amplitude: 0.85, low: 3_000, high: 4_700, rise: 0.3, buzz: 1)
            chirp(at: 0.063 + pick(0.015...0.03), duration: 0.07, amplitude: 1, low: 2_700, high: 5_400)
        default:
            chirp(at: 0.003, duration: 0.065, amplitude: 1, low: 2_800, high: 5_300)
            chirp(at: 0.068 + pick(0.03...0.045), duration: 0.072, amplitude: 0.8, low: 2_500, high: 4_900)
        }
    }

    /// 動いているとき。小さく、チチチッとさえずる
    mutating func photoMove(_ variant: Int) {
        var time = 0.003
        let notes = 3 + variant % 2
        var high = pick(4_600...5_200)
        for note in 0..<notes {
            let duration = pick(0.03...0.05)
            chirp(at: time, duration: duration, amplitude: note == notes - 1 ? 1 : pick(0.6...0.9),
                  low: high * pick(0.62...0.72), high: high, rise: pick(0.3...0.7))
            time += duration + pick(0.03...0.055)
            high *= pick(0.95...1.12)
        }
    }
}
