// 3D actuator built from the real printable STL parts in website/models
// (5010 cycloidal gear actuator). Units: mm, actuator axis = +z (output faces +z).
//
// Kinematics (15:1 cycloidal, 16 ring pins, 15-lobe disc, eccentricity 1.25 mm):
//   motor / input shaft angle  thIn = -15 * q
//   disc: orbits at e on the eccentric (follows thIn) and spins by q
//   output flange, pins, arm:  q
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { STLLoader } from "three/addons/loaders/STLLoader.js";
import { CSS2DRenderer, CSS2DObject } from "three/addons/renderers/CSS2DRenderer.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

const ECC = 1.25;
const RATIO = 15;

const PARTS = [
  // file, label, group, z-offset (assembly), explode z, colour, cut (clip in cutaway)
  { file: "housing_front", label: "Housing · front", group: "static", z: 0, ex: 70, color: 0x9fb3c8, cut: true },
  { file: "housing_middle", label: "Ring-pin housing (16 pins)", group: "static", z: 0, ex: 5, color: 0x8aa0b8, cut: true },
  { file: "housing_rear", label: "Housing · rear", group: "static", z: 0, ex: -40, color: 0x9fb3c8, cut: true },
  { file: "output_shaft_front", label: "Output flange + 6 pins", group: "output", z: 0, ex: 45, color: 0xf0a04b, cut: false },
  { file: "output_shaft_rear", label: "Output carrier · rear", group: "output", z: 0, ex: -22, color: 0xe08a2e, cut: false },
  { file: "cycloidal_disk", label: "Cycloidal disc (15 lobes)", group: "disc", z: -15.5, ex: 20, color: 0xe45756, cut: false },
  { file: "input_shaft", label: "Eccentric input shaft (e = 1.25 mm)", group: "input", z: -20.55, ex: -8, color: 0x5b6b7c, cut: false },
  { file: "motor_shaft", label: "Motor coupling", group: "input", z: -23, ex: -55, color: 0x4c5a68, cut: false },
  { file: "motor_shell", label: "Motor shell", group: "static", z: -29, ex: -95, color: 0x3a4652, cut: true },
];

const geomCache = new Map();
async function loadGeometry(base, name) {
  if (!geomCache.has(name)) {
    geomCache.set(name, new STLLoader().loadAsync(`${base}/${name}.stl`).then((g) => { g.computeVertexNormals(); return g; }));
  }
  return geomCache.get(name);
}

export class ActuatorView {
  constructor(container, { modelBase = "models", autoRotate = false, labels = true, background = null, cameraPos, dial = true, ghost = true, fitRadius = 0 } = {}) {
    this.opt = { dial, ghost };
    this.fitRadius = fitRadius;   // mm around controls.target that must stay in frame at any aspect ratio (0 = fixed camera)
    this.container = container;
    this.explode = 0; this.explodeTarget = 0;
    this.cutaway = false;
    this.showLabels = labels;
    this.q = 0; this.qRef = 0; this.showGhost = ghost; this.labelCount = 0;
    this.ready = false;

    const w = container.clientWidth, h = container.clientHeight;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: background === null, preserveDrawingBuffer: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(w, h);
    this.renderer.localClippingEnabled = true;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    container.appendChild(this.renderer.domElement);
    this.labelRenderer = new CSS2DRenderer();
    this.labelRenderer.setSize(w, h);
    this.labelRenderer.domElement.className = "label-layer";
    container.appendChild(this.labelRenderer.domElement);

    this.scene = new THREE.Scene();
    if (background !== null) this.scene.background = new THREE.Color(background);
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.camera = new THREE.PerspectiveCamera(35, w / h, 1, 5000);
    this.camera.position.set(...(cameraPos || [210, 140, 260]));
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(20, 0, -20);
    this.controls.enableDamping = true;
    this.controls.autoRotate = autoRotate;
    this.controls.autoRotateSpeed = 0.6;
    this.controls.enableZoom = true;
    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x223344, 0.6));
    const key = new THREE.DirectionalLight(0xffffff, 1.6); key.position.set(150, 220, 200); this.scene.add(key);

    // actuator axis = +z, displayed as is (output toward the camera side)
    this.root = new THREE.Group();
    this.scene.add(this.root);
    this.groups = { static: new THREE.Group(), output: new THREE.Group(), disc: new THREE.Group(), input: new THREE.Group() };
    Object.values(this.groups).forEach((g) => this.root.add(g));
    this.clipPlane = new THREE.Plane(new THREE.Vector3(0, -1, 0), 0);
    this.parts = [];
    this._load(modelBase);
    this._buildMotor();
    this._buildArm();

    const ro = new ResizeObserver(() => this.resize());
    ro.observe(container);
    this.clock = new THREE.Clock();
  }

  async _load(base) {
    const geoms = await Promise.all(PARTS.map((p) => loadGeometry(base, p.file)));
    PARTS.forEach((p, i) => {
      const mat = new THREE.MeshStandardMaterial({ color: p.color, metalness: 0.15, roughness: 0.55, side: THREE.DoubleSide });
      if (p.cut) mat.clippingPlanes = [];
      const mesh = new THREE.Mesh(geoms[i], mat);
      const holder = new THREE.Group();
      holder.add(mesh);
      holder.position.z = p.z;
      this.groups[p.group].add(holder);
      const part = { ...p, text: p.label, label: null, holder, mesh, mat };
      if (this.showLabels) part.label = this._label(holder, p.label);
      this.parts.push(part);
    });
    // six spacers on the output pins (one STL instance at 0 deg, replicated every 60 deg)
    const spacerGeom = await loadGeometry(base, "output_shaft_spacer");
    for (let k = 0; k < 6; k++) {
      const m = new THREE.Mesh(spacerGeom, new THREE.MeshStandardMaterial({ color: 0xd9d9d9, roughness: 0.5 }));
      const g = new THREE.Group(); g.add(m); g.rotation.z = (k * Math.PI) / 3;
      this.groups.output.add(g);
      this.parts.push({ file: "spacer", label: null, holder: g, ex: 32, z: 0, mesh: m, mat: m.material, cut: false });
    }
    this.ready = true;
    this.container.dispatchEvent(new CustomEvent("actuator-ready"));
  }

  _label(obj, text) {
    const el = document.createElement("div");
    el.className = "part-label";
    el.textContent = text;
    const l = new CSS2DObject(el);
    const k = this.labelCount++;
    l.position.set(0, (k % 2 ? -1 : 1) * (44 + 14 * (k % 3)), 0);
    obj.add(l);
    return l;
  }

  _buildMotor() {
    // MAD 5010 110KV is not part of the printed set; drawn procedurally inside the shell
    const rotor = new THREE.Group();
    const bell = new THREE.Mesh(new THREE.CylinderGeometry(28.5, 28.5, 22, 64, 1, true),
      new THREE.MeshStandardMaterial({ color: 0x1d1f24, metalness: 0.7, roughness: 0.35, side: THREE.DoubleSide }));
    bell.rotation.x = Math.PI / 2;
    rotor.add(bell);
    const cap = new THREE.Mesh(new THREE.CircleGeometry(28.5, 64), new THREE.MeshStandardMaterial({ color: 0x2b2f36, metalness: 0.6, roughness: 0.4 }));
    cap.position.z = 11; rotor.add(cap);
    for (let k = 0; k < 28; k++) {   // 28 magnets = 14 pole pairs, alternating colour
      const m = new THREE.Mesh(new THREE.BoxGeometry(5, 1.2, 20), new THREE.MeshStandardMaterial({ color: k % 2 ? 0xb03030 : 0x3050b0 }));
      const a = (k / 28) * Math.PI * 2;
      m.position.set(27.5 * Math.cos(a), 27.5 * Math.sin(a), 0);
      m.rotation.z = a + Math.PI / 2;
      rotor.add(m);
    }
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(4, 22, 0.8), new THREE.MeshStandardMaterial({ color: 0xffd34d, emissive: 0x443300 }));
    stripe.position.set(0, 14, 11.2); rotor.add(stripe);
    rotor.position.z = -44;
    this.groups.input.add(rotor);
    this.motorRotor = rotor;
    this.parts.push({ file: "motor", label: this.showLabels ? this._label(rotor, "MAD 5010 110KV rotor (14 pole pairs)") : null,
      holder: rotor, ex: -75, z: -44, mesh: bell, mat: bell.material, cut: false });
  }

  _buildArm() {
    const mk = (color, opacity) => new THREE.MeshStandardMaterial({ color, metalness: 0.2, roughness: 0.5, transparent: opacity < 1, opacity });
    const build = (mat) => {
      const g = new THREE.Group();
      const link = new THREE.Mesh(new THREE.BoxGeometry(120, 16, 6), mat);
      link.position.set(60, 0, 6);
      const hub = new THREE.Mesh(new THREE.CylinderGeometry(14, 14, 6, 40), mat);
      hub.rotation.x = Math.PI / 2; hub.position.z = 6;
      const mass = new THREE.Mesh(new THREE.CylinderGeometry(11, 11, 14, 40), mat);
      mass.rotation.x = Math.PI / 2; mass.position.set(120, 0, 8);
      g.add(link, hub, mass);
      return g;
    };
    this.arm = build(mk(0x2e86de, 1));
    this.groups.output.add(this.arm);
    this.ghost = build(mk(0x9be7a0, 0.28));
    this.root.add(this.ghost);
    this.parts.push({ file: "arm", label: this.showLabels ? this._label(this.arm, "Output link (q)") : null,
      holder: this.arm, ex: 75, z: 0, mesh: this.arm, mat: null, cut: false });
    // dial ring
    const ring = new THREE.Mesh(new THREE.TorusGeometry(140, 0.6, 8, 160), new THREE.MeshBasicMaterial({ color: 0x5f7a99 }));
    ring.position.z = 6; ring.visible = this.opt.dial; this.root.add(ring);
    this.dial = ring;
  }

  setState(q, qRef = null) {
    this.q = q;
    if (qRef !== null) this.qRef = qRef;
  }

  setCutaway(on) {
    this.cutaway = on;
    if (this.arm) this.arm.visible = !on;          // the link would hide the reducer internals
    for (const p of this.parts) if (p.cut && p.mat) p.mat.clippingPlanes = on ? [this.clipPlane] : [];
  }

  setLabels(on) {
    this.showLabels = on;
    this.labelRenderer.domElement.style.display = on ? "" : "none";
  }

  resize() {
    const w = this.container.clientWidth, h = this.container.clientHeight;
    if (!w || !h) return;
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h); this.labelRenderer.setSize(w, h);
    this.fit();
  }

  // Keep a sphere of fitRadius around the orbit target inside the narrower of the two FOVs.
  // A fixed camera distance clips the arm and dial in tall, narrow panels.
  fit() {
    if (!this.fitRadius) return;
    const vHalf = THREE.MathUtils.degToRad(this.camera.fov) / 2;
    const hHalf = Math.atan(Math.tan(vHalf) * this.camera.aspect);
    const dist = this.fitRadius / Math.sin(Math.min(vHalf, hHalf));
    const dir = this.camera.position.clone().sub(this.controls.target).normalize();
    this.camera.position.copy(this.controls.target).addScaledVector(dir, dist);
    this.camera.far = Math.max(5000, dist + this.fitRadius * 4);   // a far plane short of the model hides it
    this.camera.updateProjectionMatrix();
    this.controls.update();
  }

  render() {
    const dt = Math.min(0.05, this.clock.getDelta());
    this.explode += (this.explodeTarget - this.explode) * Math.min(1, dt * 4);
    const q = this.q, thIn = -RATIO * q;
    this.groups.output.rotation.z = q;
    this.groups.input.rotation.z = thIn;
    this.groups.disc.rotation.z = 0;
    this.groups.disc.position.set(ECC * Math.cos(thIn + Math.PI), ECC * Math.sin(thIn + Math.PI), 0);
    for (const p of this.parts) {
      if (p.file === "cycloidal_disk") p.holder.rotation.z = q;
      const ez = p.ex * this.explode;
      if (p.file === "motor") p.holder.position.z = -44 + ez;
      else if (p.file === "arm") p.holder.position.z = ez;
      else if (p.file === "spacer") p.holder.position.z = ez;
      else p.holder.position.z = p.z + ez;
    }
    this.ghost.rotation.z = this.qRef;
    this.ghost.visible = this.showGhost;
    this.ghost.position.z = 75 * this.explode;
    this.dial.position.z = 6 + 75 * this.explode;
    for (const p of this.parts) if (p.label) p.label.element.style.opacity = this.explode > 0.35 ? 1 : 0;
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
    this.labelRenderer.render(this.scene, this.camera);
  }
}
