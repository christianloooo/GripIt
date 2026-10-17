import * as THREE from 'three';
import { MarchingCubes } from 'three/examples/jsm/objects/MarchingCubes.js';
import type { FingerRig, Measurements } from './grip';

// A continuous implicit skin surface. Smooth unions connect the palm, thumb pad,
// wrist, and tapered finger capsules without cylinder caps or disconnected joints.
export function createHandSurface(rigs: FingerRig[], measurements: Measurements) {
  const resolution=64, size=220, center=new THREE.Vector3(0,-8,8);
  const mc=new MarchingCubes(resolution,new THREE.MeshStandardMaterial(),false,false,150000);
  mc.isolation=0;
  const capsules=rigs.flatMap(r=>r.points.slice(0,-1).map((a,i)=>{
    const b=r.points[i+1], dx=b.x-a.x,dy=b.y-a.y,dz=b.z-a.z;
    return {a,dx,dy,dz,len:dx*dx+dy*dy+dz*dz,r:r.radius*(1-i*.095)};
  }));
  const smooth=(a:number,b:number,k=4)=>{const h=Math.max(k-Math.abs(a-b),0)/k;return Math.min(a,b)-h*h*k*.25;};
  const width=measurements.palmWidth, palmLength=measurements.palmLength ?? 72;
  const ellipsoid=(x:number,y:number,z:number,cx:number,cy:number,cz:number,rx:number,ry:number,rz:number)=>{
    x-=cx;y-=cy;z-=cz;
    const k0=Math.hypot(x/rx,y/ry,z/rz), k1=Math.hypot(x/(rx*rx),y/(ry*ry),z/(rz*rz));
    return k1>1e-8?k0*(k0-1)/k1:-Math.min(rx,ry,rz);
  };
  let index=0;
  for(let z=0;z<resolution;z++)for(let y=0;y<resolution;y++)for(let x=0;x<resolution;x++){
    const px=(x/resolution-.5)*size+center.x,py=(y/resolution-.5)*size+center.y,pz=(z/resolution-.5)*size+center.z;
    let sdf=ellipsoid(px,py,pz,0,-palmLength*.43,-26,width*.48,palmLength*.55,13);
    sdf=smooth(sdf,ellipsoid(px,py,pz,width*.3,-palmLength*.46,-20,width*.24,palmLength*.35,15),6);
    sdf=smooth(sdf,ellipsoid(px,py,pz,-width*.25,-palmLength*.48,-25,width*.21,palmLength*.36,12),5);
    sdf=smooth(sdf,ellipsoid(px,py,pz,0,-palmLength-8,-27,width*.30,30,13),6);
    for(const c of capsules){
      const t=Math.max(0,Math.min(1,((px-c.a.x)*c.dx+(py-c.a.y)*c.dy+(pz-c.a.z)*c.dz)/c.len));
      const d=Math.hypot(px-c.a.x-c.dx*t,py-c.a.y-c.dy*t,pz-c.a.z-c.dz*t)-c.r*(1-.07*t);
      sdf=smooth(sdf,d,3);
    }
    mc.field[index++]=-sdf;
  }
  mc.update();
  const geometry=mc.geometry.clone();
  // MarchingCubes uses normalized [-1,+1] coordinates.
  geometry.scale(size/2,size/2,size/2);geometry.translate(center.x,center.y,center.z);
  mc.geometry.dispose();(mc.material as THREE.Material).dispose();
  return geometry;
}
