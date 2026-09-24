class_name Citizen
extends RefCounted
## Datos de un ciudadano. Toda la lógica está en PopulationSim.

var id: int = 0
var first_name: String = ""
var last_name: String = ""
var gender: String = "M"            # "M" o "F"
var birth_day: int = 0              # día absoluto de nacimiento
var health: float = 100.0           # 0-100
var sick: bool = false
var skills: Dictionary = {}         # habilidad -> 0-100
var experience: float = 0.0         # años de experiencia laboral
var education: int = 0             # índice en education_levels
var money: float = 0.0
var debt: float = 0.0
var happiness: float = 60.0         # 0-100
var job_id: int = -1               # id del edificio donde trabaja (-1 = subsistencia)
var job_kind: String = ""          # "" | "empleo" | "obra" (jornalero de construcción)
var wage: float = 0.0              # salario diario
var unpaid_days: int = 0           # días sin pagar alquiler
var home_id: int = -1
var spouse_id: int = -1
var parent_ids: Array = []
var children_ids: Array = []
var last_birth_day: int = -100000
var needs_met: float = 1.0          # 0-1, necesidades cubiertas hoy
var school_id: int = -1             # escuela/universidad donde estudia
var school_years: float = 0.0
var school_level: int = 0           # nivel máximo de escuela cursado (1 escuela, 2 colegio)
var uni_years: float = 0.0
var profession: String = ""         # profesión universitaria (cientifico, medico…)
var career: String = ""             # carrera que estudia
var visual_seed: int = 0


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


@warning_ignore("integer_division")
func age_years(today: int) -> int:
	return maxi(0, (today - birth_day) / 365)


func is_employed() -> bool:
	return job_id >= 0


func best_skill() -> String:
	var best := ""
	var best_v := -1.0
	for k in skills:
		if float(skills[k]) > best_v:
			best_v = float(skills[k])
			best = k
	return best


func to_dict() -> Dictionary:
	return {
		"id": id, "first_name": first_name, "last_name": last_name, "gender": gender,
		"birth_day": birth_day, "health": health, "sick": sick, "skills": skills,
		"experience": experience, "education": education, "money": money, "debt": debt,
		"happiness": happiness, "job_id": job_id, "job_kind": job_kind,
		"wage": wage, "unpaid_days": unpaid_days, "home_id": home_id, "spouse_id": spouse_id,
		"parent_ids": parent_ids, "children_ids": children_ids,
		"last_birth_day": last_birth_day, "needs_met": needs_met, "visual_seed": visual_seed,
		"school_id": school_id, "school_years": school_years, "school_level": school_level, "uni_years": uni_years,
		"profession": profession, "career": career,
	}


static func from_dict(d: Dictionary) -> Citizen:
	var c := Citizen.new()
	c.id = int(d.get("id", 0))
	c.first_name = str(d.get("first_name", ""))
	c.last_name = str(d.get("last_name", ""))
	c.gender = str(d.get("gender", "M"))
	c.birth_day = int(d.get("birth_day", 0))
	c.health = float(d.get("health", 100.0))
	c.sick = bool(d.get("sick", false))
	c.skills = d.get("skills", {})
	c.experience = float(d.get("experience", 0.0))
	c.education = int(d.get("education", 0))
	c.money = float(d.get("money", 0.0))
	c.debt = float(d.get("debt", 0.0))
	c.happiness = float(d.get("happiness", 60.0))
	c.job_id = int(d.get("job_id", -1))
	c.job_kind = str(d.get("job_kind", ""))
	c.wage = float(d.get("wage", 0.0))
	c.unpaid_days = int(d.get("unpaid_days", 0))
	if c.job_id < 0:
		c.job_kind = ""
	c.home_id = int(d.get("home_id", -1))
	c.spouse_id = int(d.get("spouse_id", -1))
	c.parent_ids = []
	for p in d.get("parent_ids", []):
		c.parent_ids.append(int(p))
	c.children_ids = []
	for ch in d.get("children_ids", []):
		c.children_ids.append(int(ch))
	c.last_birth_day = int(d.get("last_birth_day", -100000))
	c.needs_met = float(d.get("needs_met", 1.0))
	c.visual_seed = int(d.get("visual_seed", c.id))
	c.school_id = int(d.get("school_id", -1))
	c.school_years = float(d.get("school_years", 0.0))
	c.school_level = int(d.get("school_level", 0))
	c.uni_years = float(d.get("uni_years", 0.0))
	c.profession = str(d.get("profession", ""))
	c.career = str(d.get("career", ""))
	return c
