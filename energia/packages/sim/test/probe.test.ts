import { it } from 'vitest';
import { stateHash, step } from '../src';
import { ctx, newGame } from './helpers';

it('probe', () => {
  for (const seed of [1, 2]) {
    const s = newGame(seed, 1e9);
    const t0 = performance.now();
    const counts: Record<string, number> = {};
    for (let d = 0; d < 3650; d++) for (const e of step(s, [], ctx)) counts[e.type] = (counts[e.type] ?? 0) + 1;
    const t1 = performance.now();
    console.log('ms', Math.round(t1 - t0), stateHash(s));
    console.log(JSON.stringify(counts));
    for (const c of s.competitors) {
      console.log(c.id, c.name, c.status, 'cash', Math.round(c.company.cashUsd / 1e3), 'k; proj', c.projects.map((p) => `${p.stage}:${p.mw}`).join(','),
        'won', c.business.bidsWon, 'lost', c.business.bidsLost, 'rej', c.rejectedCommands, 'res', c.business.research.completed.join('|'), 'k', c.business.contracts.map((k) => `${k.kind}:${k.status}`).join(','));
    }
    for (const c of s.competitors) for (const p of c.projects) if (false) console.log(c.id, p.id, p.mw, p.techId, 'ppa', p.ppa?.status, p.ppa?.channelId, 'sup', !!p.suppliers, 'fin', p.financing?.status, p.financing?.failReason, 'sale', p.sale?.status, 'k', p.contractId, 'sigma', p.estimate.sigma, 'created', p.createdTick);
    for (const c of s.competitors) { const t: Record<string, number> = {}; for (const st of c.finance.statements) for (const [k, v] of Object.entries(st.lines)) t[k] = Math.round(((t[k] ?? 0) + v / 1000)); console.log(c.id, 'bk', c.finance.bankruptTick, JSON.stringify(t)); }
    console.log('opps', s.market.opportunities.length, JSON.stringify(s.market.supply.materials), s.market.supply.demandIndex);
  }
}, 60000);
