// Loads a .3mf model into a Three.js group, mirroring Model3MF.swift.
//
// A 3MF file is an OPC/ZIP container whose mesh lives at `3D/3dmodel.model`
// as XML. We unzip it with JSZip (loaded as a global), parse the
// <vertices>/<triangles>, center + normalize the mesh, and return a
// flat-shaded body with a glowing cyan wireframe overlay.

import * as THREE from '../../node_modules/three/build/three.module.js';

export async function loadModelFromFile(file) {
  const buffer = await file.arrayBuffer();
  const zip = await window.JSZip.loadAsync(buffer);
  const entry = zip.file('3D/3dmodel.model');
  if (!entry) throw new Error('No 3D/3dmodel.model found inside the .3mf file.');
  const xml = await entry.async('string');
  return buildFromXML(xml);
}

function buildFromXML(xml) {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');

  const positions = [];
  for (const v of doc.getElementsByTagName('vertex')) {
    positions.push(
      parseFloat(v.getAttribute('x') || '0'),
      parseFloat(v.getAttribute('y') || '0'),
      parseFloat(v.getAttribute('z') || '0')
    );
  }
  const indices = [];
  for (const t of doc.getElementsByTagName('triangle')) {
    indices.push(
      parseInt(t.getAttribute('v1'), 10),
      parseInt(t.getAttribute('v2'), 10),
      parseInt(t.getAttribute('v3'), 10)
    );
  }
  if (indices.length === 0) throw new Error('The model contained no triangles.');

  // Center on origin and scale so the largest dimension is ~2 units.
  let min = [Infinity, Infinity, Infinity];
  let max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let a = 0; a < 3; a++) {
      min[a] = Math.min(min[a], positions[i + a]);
      max[a] = Math.max(max[a], positions[i + a]);
    }
  }
  const center = [(min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2];
  const extent = Math.max(max[0] - min[0], max[1] - min[1], max[2] - min[2]);
  const scale = extent > 0 ? 2.0 / extent : 1.0;

  const normalized = new Float32Array(positions.length);
  for (let i = 0; i < positions.length; i += 3) {
    normalized[i] = (positions[i] - center[0]) * scale;
    normalized[i + 1] = (positions[i + 1] - center[1]) * scale;
    normalized[i + 2] = (positions[i + 2] - center[2]) * scale;
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(normalized, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();

  const group = new THREE.Group();
  const body = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
    color: 0x1a2438, metalness: 0.8, roughness: 0.35
  }));
  const wire = new THREE.LineSegments(
    new THREE.WireframeGeometry(geo),
    new THREE.LineBasicMaterial({ color: 0x59f2ff })
  );
  group.add(body, wire);
  return group;
}
