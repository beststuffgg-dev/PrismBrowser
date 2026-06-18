// 3D geometric wallpapers for Prism's start page — "Ubuntu-style, but in 3D".
//
// A field of neon-wireframe geometric solids drifting over a dark gradient,
// lit by two customizable accent colors. Several presets vary the shape and
// arrangement; colors are fully customizable while keeping the Prism look.

import * as THREE from '../../node_modules/three/build/three.module.js';

export const WALLPAPERS = [
  { id: 'icospheres', name: 'Icosphere Field' },
  { id: 'lattice',    name: 'Cube Lattice' },
  { id: 'torus',      name: 'Torus Knot' },
  { id: 'octahedra',  name: 'Octahedron Cluster' },
  { id: 'prisms',     name: 'Prism Tunnel' }
];

export function createWallpaper(canvas, initial = {}) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(50, 1, 0.1, 100);
  camera.position.set(0, 0, 9);

  const keyLight = new THREE.PointLight(0xffffff, 500, 0, 1.2);
  keyLight.position.set(6, 5, 8);
  const rimLight = new THREE.PointLight(0xffffff, 500, 0, 1.2);
  rimLight.position.set(-6, -4, 4);
  scene.add(keyLight, rimLight, new THREE.AmbientLight(0xffffff, 0.5));

  let group = new THREE.Group();
  scene.add(group);

  let state = {
    preset: initial.preset || 'icospheres',
    colorA: new THREE.Color(initial.colorA || '#59f2ff'),  // primary / wireframe
    colorB: new THREE.Color(initial.colorB || '#ff59d9')   // secondary / rim
  };

  // ---- Geometry builders ----

  function shapeGeometry(preset) {
    switch (preset) {
      case 'lattice':   return new THREE.BoxGeometry(0.9, 0.9, 0.9);
      case 'torus':     return new THREE.TorusKnotGeometry(0.7, 0.24, 120, 18);
      case 'octahedra': return new THREE.OctahedronGeometry(0.8, 0);
      case 'prisms':    return new THREE.CylinderGeometry(0.7, 0.7, 1.4, 6);
      case 'icospheres':
      default:          return new THREE.IcosahedronGeometry(0.8, 1);
    }
  }

  // Placement of N solids for a given preset.
  function placements(preset) {
    const out = [];
    if (preset === 'lattice') {
      for (let x = -1; x <= 1; x++)
        for (let y = -1; y <= 1; y++)
          for (let z = -1; z <= 1; z++)
            out.push({ pos: [x * 2.4, y * 2.4, z * 2.4], scale: 1 });
    } else if (preset === 'torus') {
      out.push({ pos: [0, 0, 0], scale: 2.4 });
    } else if (preset === 'prisms') {
      const ring = 8;
      for (let i = 0; i < ring; i++) {
        const a = (i / ring) * Math.PI * 2;
        out.push({ pos: [Math.cos(a) * 3.2, Math.sin(a) * 3.2, -2], scale: 1, rot: [Math.PI / 2, 0, a] });
      }
      for (let i = 0; i < ring; i++) {
        const a = (i / ring) * Math.PI * 2 + Math.PI / ring;
        out.push({ pos: [Math.cos(a) * 1.8, Math.sin(a) * 1.8, 1.5], scale: 0.7, rot: [Math.PI / 2, 0, a] });
      }
    } else {
      // scattered field (icospheres / octahedra)
      const n = 9;
      for (let i = 0; i < n; i++) {
        out.push({
          pos: [(Math.random() - 0.5) * 9, (Math.random() - 0.5) * 6, (Math.random() - 0.5) * 6],
          scale: 0.7 + Math.random() * 0.9
        });
      }
    }
    return out;
  }

  function build() {
    scene.remove(group);
    group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) o.material.dispose();
    });
    group = new THREE.Group();

    const geo = shapeGeometry(state.preset);
    const bodyMat = new THREE.MeshStandardMaterial({
      color: 0x10141f, metalness: 0.7, roughness: 0.35
    });

    for (const p of placements(state.preset)) {
      const solid = new THREE.Group();
      const body = new THREE.Mesh(geo, bodyMat);
      const wire = new THREE.LineSegments(
        new THREE.WireframeGeometry(geo),
        new THREE.LineBasicMaterial({ color: state.colorA })
      );
      solid.add(body, wire);
      solid.position.set(...p.pos);
      if (p.rot) solid.rotation.set(...p.rot);
      const s = p.scale || 1;
      solid.scale.set(s, s, s);
      solid.userData.spin = 0.1 + Math.random() * 0.4;
      group.add(solid);
    }
    keyLight.color.copy(state.colorA);
    rimLight.color.copy(state.colorB);
    scene.add(group);
  }

  build();

  // ---- Controls ----

  function setPreset(id) { state.preset = id; build(); }
  function setColors(colorA, colorB) {
    if (colorA) state.colorA = new THREE.Color(colorA);
    if (colorB) state.colorB = new THREE.Color(colorB);
    build();
  }

  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', resize);
  resize();

  const clock = new THREE.Clock();
  (function animate() {
    requestAnimationFrame(animate);
    const t = clock.getElapsedTime();
    const dt = clock.getDelta();
    group.children.forEach((solid, i) => {
      const k = solid.userData.spin || 0.2;
      solid.rotation.x += dt * k;
      solid.rotation.y += dt * k * 1.3;
      solid.position.y += Math.sin(t * 0.4 + i) * dt * 0.15; // gentle bob
    });
    group.rotation.y = Math.sin(t * 0.1) * 0.3;
    camera.position.x = Math.sin(t * 0.15) * 0.6;
    camera.lookAt(0, 0, 0);
    renderer.render(scene, camera);
  })();

  return { setPreset, setColors };
}
