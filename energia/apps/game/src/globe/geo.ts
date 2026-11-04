import * as THREE from 'three';

const D = Math.PI / 180;

/** Convención única del juego: lon/lat (grados) → punto en la esfera. */
export function lonLatToVec3(lon: number, lat: number, r = 1, out = new THREE.Vector3()): THREE.Vector3 {
  const la = lat * D, lo = lon * D;
  return out.set(r * Math.cos(la) * Math.cos(lo), r * Math.sin(la), -r * Math.cos(la) * Math.sin(lo));
}

export function vec3ToLonLat(v: THREE.Vector3): { lon: number; lat: number } {
  const n = v.clone().normalize();
  return { lat: Math.asin(n.y) / D, lon: Math.atan2(-n.z, n.x) / D };
}
