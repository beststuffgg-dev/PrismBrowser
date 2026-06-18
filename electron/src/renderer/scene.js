// Live 3D backdrop, mirroring Scene3DView.swift: a continuously spinning
// neon wireframe object (or a user-supplied .3mf model) lit by cyan + magenta
// rim lights over a faint grid floor, rendered dimly behind the whole UI.

import * as THREE from '../../node_modules/three/build/three.module.js';
import { OrbitControls } from '../../node_modules/three/examples/jsm/controls/OrbitControls.js';

export function createBackdrop(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
  camera.position.set(0, 0, 6);

  const controls = new OrbitControls(camera, canvas);
  controls.enablePan = false;
  controls.enableZoom = false;

  // Rim lights
  const cyan = new THREE.PointLight(0x59f2ff, 600, 0, 1.2);
  cyan.position.set(5, 4, 6);
  const magenta = new THREE.PointLight(0xff59d9, 600, 0, 1.2);
  magenta.position.set(-5, -3, 4);
  scene.add(cyan, magenta, new THREE.AmbientLight(0xffffff, 0.6));

  // Grid floor
  const grid = new THREE.GridHelper(14, 14, 0x3399cc, 0x276680);
  grid.position.y = -2.4;
  grid.material.opacity = 0.35;
  grid.material.transparent = true;
  scene.add(grid);

  let spinner = makeWireframeIcosahedron();
  scene.add(spinner);

  function makeWireframeIcosahedron() {
    const group = new THREE.Group();
    const geo = new THREE.IcosahedronGeometry(1.6, 1);
    const body = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
      color: 0x1a2438, metalness: 0.85, roughness: 0.3
    }));
    const wire = new THREE.LineSegments(
      new THREE.WireframeGeometry(geo),
      new THREE.LineBasicMaterial({ color: 0x59f2ff })
    );
    group.add(body, wire);
    return group;
  }

  /** Swap in a custom model group (from the .3mf loader). */
  function setCustom(node) {
    scene.remove(spinner);
    spinner = node || makeWireframeIcosahedron();
    scene.add(spinner);
  }
  function reset() { setCustom(null); }

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
    const dt = clock.getDelta();
    spinner.rotation.x += dt * 0.25;
    spinner.rotation.y += dt * 0.5;
    spinner.rotation.z += dt * 0.1;
    controls.update();
    renderer.render(scene, camera);
  })();

  return { setCustom, reset };
}
