class_name AdvertisingSim
extends RefCounted
## Fase 8 — publicidad: campañas (periódico → radio → TV) que aumentan la demanda de tus negocios.
## Contrato: demand_mult(gs, b) >= 1 multiplica la disposición a comprarle a ese negocio.


static func demand_mult(_gs, _b: Dictionary) -> float:
	return 1.0


static func monthly(_gs) -> void:
	pass
