// Policies used on the site: VQC (6 qubits, 4 layers, 72 angles), MLP 6-8-1,
// nominal model feed-forward, and PD-only. Same math as pynq-can/vqc/vqc_model.py.

export class Encoding {
  constructor(enc) {
    this.index = enc.feat_index;
    this.scale = enc.feat_scale;
    this.names = enc.features;
    this.tauMax = enc.tau_max;
    this.gain = enc.out_gain;
  }
  // obs[8] = [pos_err, vel_err, pos_err_int, qd, q_ref, qd_ref, qdd_ref, tau_prev]
  angles(obs, out = new Float64Array(6)) {
    for (let q = 0; q < 6; q++) out[q] = Math.PI * Math.tanh(this.scale[q] * obs[this.index[q]]);
    return out;
  }
  squash(y) { return this.tauMax * Math.tanh(this.gain * y); }
}

// ---------------------------------------------------------------- VQC
// 2x2 complex as [re00, im00, re01, im01, re10, im10, re11, im11]
function cmul(a, b) {
  const o = new Float64Array(8);
  for (let r = 0; r < 2; r++)
    for (let c = 0; c < 2; c++) {
      let re = 0, im = 0;
      for (let k = 0; k < 2; k++) {
        const ar = a[(r * 2 + k) * 2], ai = a[(r * 2 + k) * 2 + 1];
        const br = b[(k * 2 + c) * 2], bi = b[(k * 2 + c) * 2 + 1];
        re += ar * br - ai * bi;
        im += ar * bi + ai * br;
      }
      o[(r * 2 + c) * 2] = re;
      o[(r * 2 + c) * 2 + 1] = im;
    }
  return o;
}
const RX = (t) => { const c = Math.cos(t / 2), s = Math.sin(t / 2); return Float64Array.of(c, 0, 0, -s, 0, -s, c, 0); };
const RY = (t) => { const c = Math.cos(t / 2), s = Math.sin(t / 2); return Float64Array.of(c, 0, -s, 0, s, 0, c, 0); };
const RZ = (t) => { const c = Math.cos(t / 2), s = Math.sin(t / 2); return Float64Array.of(c, -s, 0, 0, 0, 0, c, s); };

export class VQC {
  constructor(p, enc) {
    this.enc = enc;
    this.nq = p.n_qubits;
    this.nl = p.n_layers;
    this.dim = 1 << this.nq;
    this.perm = Int32Array.from(p.perm);
    this.theta = p.theta;
    this.nParams = p.theta.length;
    // fused W[l][q] = RZ(t2) RY(t1) RX(t0)  (computed once, like the PS does for the PL core)
    this.W = [];
    for (let l = 0; l < this.nl; l++)
      for (let q = 0; q < this.nq; q++) {
        const t = p.theta.slice((l * this.nq + q) * 3, (l * this.nq + q) * 3 + 3);
        this.W.push(cmul(cmul(RZ(t[2]), RY(t[1])), RX(t[0])));
      }
    this.re = new Float64Array(this.dim); this.im = new Float64Array(this.dim);
    this.tr = new Float64Array(this.dim); this.ti = new Float64Array(this.dim);
    this.prob = new Float64Array(this.dim);
    this.x = new Float64Array(this.nq);
    this.z = 0;
  }
  expval(x) {
    const { re, im, tr, ti, dim, nq } = this;
    re.fill(0); im.fill(0); re[0] = 1;
    for (let l = 0; l < this.nl; l++) {
      for (let q = 0; q < nq; q++) {
        const w = this.W[l * nq + q], c = Math.cos(x[q] / 2), s = Math.sin(x[q] / 2);
        // U = W * RY(x)
        const u0 = w[0] * c + w[2] * s, u1 = w[1] * c + w[3] * s, u2 = -w[0] * s + w[2] * c, u3 = -w[1] * s + w[3] * c;
        const u4 = w[4] * c + w[6] * s, u5 = w[5] * c + w[7] * s, u6 = -w[4] * s + w[6] * c, u7 = -w[5] * s + w[7] * c;
        const stride = 1 << (nq - 1 - q);
        for (let k = 0; k < dim / 2; k++) {
          const i0 = ((k & ~(stride - 1)) << 1) | (k & (stride - 1)), i1 = i0 | stride;
          const ar = re[i0], ai = im[i0], br = re[i1], bi = im[i1];
          re[i0] = u0 * ar - u1 * ai + u2 * br - u3 * bi; im[i0] = u0 * ai + u1 * ar + u2 * bi + u3 * br;
          re[i1] = u4 * ar - u5 * ai + u6 * br - u7 * bi; im[i1] = u4 * ai + u5 * ar + u6 * bi + u7 * br;
        }
      }
      for (let i = 0; i < dim; i++) { tr[i] = re[this.perm[i]]; ti[i] = im[this.perm[i]]; }
      re.set(tr); im.set(ti);
    }
    let z = 0;
    for (let i = 0; i < dim; i++) {
      const p = re[i] * re[i] + im[i] * im[i];
      this.prob[i] = p;
      z += i < dim / 2 ? p : -p;
    }
    this.z = z;
    return z;
  }
  act(obs) {
    this.enc.angles(obs, this.x);
    return this.enc.squash(this.expval(this.x));
  }
}

// ---------------------------------------------------------------- MLP 6-8-1
export class MLP {
  constructor(p, enc) {
    this.enc = enc;
    this.sizes = p.sizes;
    this.theta = p.theta;
    this.nParams = p.theta.length;
    this.x = new Float64Array(6);
  }
  act(obs) {
    let h = Array.from(this.enc.angles(obs, this.x));
    let k = 0;
    for (let j = 0; j < this.sizes.length - 1; j++) {
      const ni = this.sizes[j], no = this.sizes[j + 1], out = new Array(no).fill(0);
      for (let o = 0; o < no; o++) {
        let s = 0;
        for (let i = 0; i < ni; i++) s += this.theta[k + o * ni + i] * h[i];
        out[o] = s;
      }
      k += no * ni;
      for (let o = 0; o < no; o++) out[o] += this.theta[k + o];
      k += no;
      h = j < this.sizes.length - 2 ? out.map(Math.tanh) : out;
    }
    return this.enc.squash(h[0]);
  }
}

// ---------------------------------------------------------------- classical
export class ModelFF {
  constructor(plant, tauMax) { this.p = plant; this.tauMax = tauMax; this.nParams = 0; }
  act(obs) {
    const n = this.p.nominal, kd = this.p.firmware_pd.kd, qdRef = obs[5], qddRef = obs[6];
    const tauOut = n.J * qddRef + n.b * qdRef + n.tau_c * Math.tanh(qdRef / 0.05);
    const t = kd * qdRef + tauOut / (this.p.gear * n.eta);
    return Math.max(-this.tauMax, Math.min(this.tauMax, t));
  }
}

export class PDOnly { constructor() { this.nParams = 0; } act() { return 0; } }
