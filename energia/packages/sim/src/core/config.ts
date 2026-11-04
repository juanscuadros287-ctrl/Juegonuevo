/** Lo que el motor necesita de los datos del juego (lo llena @voltaje/data a partir de los YAML). */
export interface SimConfig {
  dataVersion: number;
  startDate: string; // ISO
  startCountry: string; // código ADM0_A3
  company: { cashUsd: number; monthlyFixedCostUsd: number };
}
