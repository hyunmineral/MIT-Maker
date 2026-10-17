// Joint + Recoil firmware position loop + 1 kHz host loop.
// Mirrors pynq-can/vqc/actuator_sim.py and host/run_controller.py (1 s ramp-in,
// host-side velocity estimate), so the numbers match the PYNQ measurements.

export class Joint {
  constructor(P, params = {}) {
    this.P = P;
    const n = P.nominal;
    this.J = params.J ?? n.J; this.b = params.b ?? n.b; this.tau_c = params.tau_c ?? n.tau_c;
    this.eta = params.eta ?? n.eta; this.delay = params.delay ?? n.delay;
    this.kp = P.firmware_pd.kp; this.kd = P.firmware_pd.kd;
    this.reset();
  }
  reset() { this.q = 0; this.qd = 0; this.tau_m = 0; this.pipe = []; this.motorAngle = 0; }
  step(qRef, tauFF) {
    const P = this.P;
    this.pipe.push([qRef, Math.max(-1, Math.min(1, tauFF))]);
    const cmd = this.pipe.length > this.delay ? this.pipe.shift() : [this.q, 0];
    const h = P.dt / P.substeps;
    for (let s = 0; s < P.substeps; s++) {
      const tau = this.kp * (cmd[0] - this.q) - this.kd * this.qd + cmd[1];
      this.tau_m = Math.max(-P.torque_limit, Math.min(P.torque_limit, this.tau_m + P.ema_alpha * (tau - this.tau_m)));
      const qdd = (P.gear * this.eta * this.tau_m - this.b * this.qd - this.tau_c * Math.tanh(this.qd / 0.05)) / this.J;
      this.qd = Math.max(-P.qd_limit, Math.min(P.qd_limit, this.qd + qdd * h));
      this.q += this.qd * h;
    }
  }
}

export class ObsBuilder {
  constructor(dt) { this.dt = dt; this.reset(); }
  reset() { this.eInt = 0; this.tauPrev = 0; this.qdRefPrev = null; }
  build(q, qd, qRef, qdRef) {
    const e = qRef - q;
    this.eInt = Math.max(-0.05, Math.min(0.05, this.eInt + e * this.dt));
    const qddRef = this.qdRefPrev === null ? 0 : (qdRef - this.qdRefPrev) / this.dt;
    this.qdRefPrev = qdRef;
    return [e, qdRef - qd, this.eInt, qd, qRef, qdRef, qddRef, this.tauPrev];
  }
}

export function reference(t, kind, amp, freq) {
  const w = 2 * Math.PI * freq;
  switch (kind) {
    case "step": return [(t % (1 / freq)) < 0.5 / freq ? amp : -amp, 0];
    case "chirp": {
      const k = 0.5, ph = 2 * Math.PI * (freq * t + 0.5 * k * t * t);
      return [amp * Math.sin(ph), amp * 2 * Math.PI * (freq + k * t) * Math.cos(ph)];
    }
    case "multisine": {
      const w2 = 2.7 * w;
      return [0.65 * amp * Math.sin(w * t) + 0.35 * amp * Math.sin(w2 * t + 1.1),
              0.65 * amp * w * Math.cos(w * t) + 0.35 * amp * w2 * Math.cos(w2 * t + 1.1)];
    }
    default: return [amp * Math.sin(w * t), amp * w * Math.cos(w * t)];
  }
}

// One controller run: policy + joint + observation, 1 kHz ticks.
export class Run {
  constructor(P, policy, opts) {
    this.P = P; this.policy = policy; this.opts = opts;
    this.joint = new Joint(P, opts.plant || {});
    this.obsb = new ObsBuilder(P.dt);
    this.k = 0; this.q = 0; this.qd = 0; this.qPrev = 0;
    this.sumSq = 0; this.n = 0; this.maxErr = 0;
    this.last = { t: 0, qRef: 0, q: 0, err: 0, tau: 0, tauMeas: 0, obs: new Array(8).fill(0) };
  }
  tick() {
    const { P, opts } = this;
    const t = this.k * P.dt;
    const ramp = opts.ramp === false ? 1 : Math.min(1, t);
    const [r, rd] = reference(t, opts.traj, opts.amp, opts.freq);
    const qRef = ramp * r, qdRef = ramp * rd;
    const obs = this.obsb.build(this.q, this.qd, qRef, qdRef);
    const tau = this.policy.act(obs) * ramp;
    this.obsb.tauPrev = tau;
    this.joint.step(qRef, tau);
    this.q = this.joint.q;
    this.qd = 0.7 * this.qd + 0.3 * (this.q - this.qPrev) / P.dt;
    this.qPrev = this.q;
    const err = qRef - this.q;
    if (t >= 1.0) {
      this.sumSq += err * err; this.n++;
      this.maxErr = Math.max(this.maxErr, Math.abs(err));
    }
    this.k++;
    this.last = { t, qRef, q: this.q, err, tau, tauMeas: this.joint.tau_m, obs };
    return this.last;
  }
  get rmsMrad() { return this.n ? 1e3 * Math.sqrt(this.sumSq / this.n) : 0; }
  get maxMrad() { return 1e3 * this.maxErr; }
}

export function sampleRandomPlant(P, rnd = Math.random) {
  const R = P.random, U = (k) => R[k][0] + (R[k][1] - R[k][0]) * rnd();
  return { J: U("J"), b: U("b"), tau_c: U("tau_c"), eta: U("eta"), delay: Math.floor(rnd() * (R.delay[1] + 1)) };
}
