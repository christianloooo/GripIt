import {it} from 'vitest';import {solveGrip,DEFAULT_MEASUREMENTS,PITCHES} from './grip';
it('report',()=>{const s=solveGrip(DEFAULT_MEASUREMENTS,PITCHES[0]);console.log(s.ball,s.objective,s.fingers.map(f=>[f.name,f.error,f.clearance,f.target.toArray()]));});
