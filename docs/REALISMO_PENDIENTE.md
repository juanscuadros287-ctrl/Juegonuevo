# Lo que falta para más realismo (empresas y economía)

Lista priorizada que salió al armar «Mis empresas» (docs/MIS_EMPRESAS.md). No repite lo que ya está en
`docs/PENDIENTES.md` (contabilidad por empresa con balance, fusiones, franquicias, patentes, juicios, salud laboral,
reputación, publicidad, rivales, etc.); son huecos más finos de la simulación.

## Alta
1. **Precio de transferencia entre tus empresas.** La fábrica que entrega al almacén no factura; «Mis empresas» le
   imputa la producción a precio de mercado. Falta un precio interno configurable (costo, mercado o costo + %) que
   quede en el libro de quien entrega y de quien vende.
2. **Costo de la mercancía vendida.** La tienda, el contrato y la exportación registran la venta completa como
   utilidad: no descuentan lo que costó producir lo vendido. Con el punto 1 se corrige el doble beneficio.
3. **Inventario en libros.** Lo producido y no vendido es gasto del mes; falta valorar el inventario (costo
   promedio) y su variación, para que un mes de acopio no parezca pérdida.
4. **Ventas y compras a plazo.** Todo es de contado. Faltan cuentas por cobrar y por pagar (30/60/90 días), clientes
   morosos y capital de trabajo; sería la base para quiebras por liquidez y no solo por pérdidas.
5. **Registrar a quién se vende.** Las ventas no guardan el comprador (ciudadano, empresa NPC, pueblo, contrato) ni
   las cantidades. La ficha deduce los canales; con un registro por canal saldría la cuota de cada cliente.

## Media
6. **Deuda y costo del capital por empresa.** Los préstamos son del jugador. Asignarlos a la empresa que financian
   daría intereses en su resultado, ROI neto de deuda y apalancamiento.
7. **Depreciación contable y valor en libros que baja.** Hoy el valor de un edificio es el 70 % de lo invertido para
   siempre; debería depreciarse con los años y el desgaste, y la depreciación debería entrar en el resultado, no
   solo en el costeo.
8. **Gastos generales del grupo.** La oficina, la gerencia y los seguros no se reparten entre las empresas.
9. **Arrastre de pérdidas fiscales.** La renta se cobra mes a mes por edificio; falta compensar las pérdidas de meses
   anteriores (y, si es el caso, consolidar las de una misma razón social).
10. **Competencia y cuota de mercado por bien.** Mostrar y simular cuánto vende cada productor del pueblo (tú y los
    NPC) del mismo bien, y la elasticidad de tu demanda al subir el precio.

## Baja
11. **Caducidad y merma en almacén** de perecederos (pan, carne, leche) además de los robos.
12. **Estacionalidad de la demanda** (navidad, cosecha, fiestas), no solo de la producción.
13. **Capacidad usada y cuellos de botella:** % de la capacidad instalada que se usa y qué la limita (personal,
    insumos, almacén, energía).
14. **Descuentos por volumen e indexación** en los contratos con proveedores (precio atado a la inflación).
15. **Turnos, horas extra y ausentismo** como palancas de producción con costo propio.
