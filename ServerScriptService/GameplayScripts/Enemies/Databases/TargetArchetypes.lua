-- Module Script
local TargetArchetypes = {

	["Corporate Executive"] = {
		Occupations = {
			"Chief Executive Officer",
			"Corporate Executive",
			"Financial Director",
			"Investment Executive",
		},

		Affiliations = {
			"Private Corporation",
			"International Conglomerate",
			"Investment Group",
		},

		ContractValue = {100000, 200000},
		Threat = "Moderate",
		TargetBehaviour = "Surrender",
	},

	["Arms Dealer"] = {
		Occupations = {
			"International Arms Broker",
			"Weapons Trafficker",
			"Defence Contractor",
		},

		Affiliations = {
			"Private Military Network",
			"Black Market Network",
			"International Arms Syndicate",
		},

		ContractValue = {220000, 425000},
		Threat = "High",
		TargetBehaviour = "Fighter",
	},

	["Criminal Broker"] = {
		Occupations = {
			"Criminal Broker",
			"Underworld Intermediary",
			"Organised Crime Broker",
		},

		Affiliations = {
			"Criminal Organisation",
			"International Syndicate",
			"Black Market Network",
		},

		ContractValue = {220000, 400000},
		Threat = "High",
		TargetBehaviour = "Flee",
	},

	["Military Officer"] = {
		Occupations = {
			"Senior Military Officer",
			"Special Operations Commander",
			"Military Intelligence Officer",
		},

		Affiliations = {
			"Military",
			"Special Operations Command",
			"Military Intelligence",
		},

		ContractValue = {250000, 450000},
		Threat = "High",
		TargetBehaviour = "Fighter",
	},

	["Intelligence Asset"] = {
		Occupations = {
			"Intelligence Officer",
			"Intelligence Asset",
			"Former Intelligence Operative",
		},

		Affiliations = {
			"Intelligence Service",
			"Private Intelligence Network",
			"Foreign Intelligence Service",
		},

		ContractValue = {450000, 750000},
		Threat = "Extreme",
		TargetBehaviour = "Flee",
	},

	["Cybercriminal"] = {
		Occupations = {
			"Cybercriminal",
			"Network Intrusion Specialist",
			"Data Broker",
		},

		Affiliations = {
			"Cybercrime Network",
			"Black Market Network",
			"Independent",
		},

		ContractValue = {220000, 400000},
		Threat = "High",
		TargetBehaviour = "Flee",
	},

	["Scientist"] = {
		Occupations = {
			"Research Scientist",
			"Biotechnology Executive",
			"Defence Researcher",
		},

		Affiliations = {
			"Private Research Group",
			"Defence Contractor",
			"Biotechnology Corporation",
		},

		ContractValue = {100000, 200000},
		Threat = "Moderate",
		TargetBehaviour = "Surrender",
	},

	["Smuggler"] = {
		Occupations = {
			"International Smuggler",
			"Logistics Broker",
			"Contraband Dealer",
		},

		Affiliations = {
			"Smuggling Network",
			"Criminal Organisation",
			"Independent",
		},

		ContractValue = {100000, 190000},
		Threat = "Moderate",
		TargetBehaviour = "Flee",
	},

	["Political Figure"] = {
		Occupations = {
			"Government Minister",
			"Political Official",
			"Senior Government Advisor",
		},

		Affiliations = {
			"Government",
			"Political Organisation",
			"Government Intelligence Office",
		},

		ContractValue = {550000, 850000},
		Threat = "Extreme",
		TargetBehaviour = "Surrender",
	},

	["PMC Executive"] = {
		Occupations = {
			"Private Military Contractor",
			"PMC Executive",
			"Security Operations Director",
		},

		Affiliations = {
			"Private Military Company",
			"International Security Firm",
		},

		ContractValue = {250000, 450000},
		Threat = "High",
		TargetBehaviour = "Fighter",
	},

}

return TargetArchetypes
